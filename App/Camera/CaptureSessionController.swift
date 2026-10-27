import AVFoundation
import CameraCore
import UIKit

/// Everything that touches AVCaptureSession. Work runs on a private serial queue, so this class is
/// deliberately not main-actor isolated.
///
/// How switching stays fast, following Lampa and react-native-vision-camera:
/// - Formats are picked by hand (`.inputPriority`). Photos use a 4:3 stream about 1920 wide, and 1080p SDR
///   video reuses it cropped to 16:9, so photo ↔ video changes nothing in the session.
/// - The microphone lives in its own capture session. Adding audio to the camera session restarts it;
///   a separate session starts in the background without touching the viewfinder.
/// - The back cameras are one virtual device, so lens changes are zoom changes.
/// - The viewfinder and the recording have separate video outputs: the viewfinder stream is never
///   stabilized (stabilization buffers frames and makes the preview lag), the recording stream is.
final class CaptureSessionController: NSObject, @unchecked Sendable {
    struct Config: Sendable {
        var lens: LensID
        var mode: CaptureMode
        var format: VideoFormat
        var stabilization: VideoStabilization
        var appleLog: Bool
        var digitalZoom: Double
        var exposureBias: Double
        var wantsRAW: Bool
        var rawFormat: RAWFormat
        var photoResolution: PhotoResolution
        /// Portrait photo mode: stream depth for the live background blur.
        var portrait: Bool = false
    }

    struct DeviceInfo: Sendable {
        var focalLengths: [LensID: Double]
        var rawAvailable: Bool
        var appleLogActive: Bool
        /// The session was rebuilt, so the viewfinder paused for a moment.
        var didReconfigure: Bool
        /// Frame rates the camera runs for each video width (1920, 3840).
        var frameRates: [Int: [Int]] = [:]
    }

    struct PhotoOutcome: @unchecked Sendable {
        var raw: Data?
        var processed: Data?
        /// Depth for portrait photos. Nil when the photo was taken without depth.
        var depth: AVDepthData?
        var error: Error?
    }

    let session = AVCaptureSession()
    let hub: FrameHub

    private let sessionQueue = DispatchQueue(label: "rcamera.session")
    private let captureQueue = DispatchQueue(label: "rcamera.capture", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "rcamera.audio")
    private let photoOutput = AVCapturePhotoOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private let recordOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let depthQueue = DispatchQueue(label: "rcamera.depth", qos: .userInteractive)
    private var depthOutputAdded = false

    private let audioSession = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var audioSettings: [String: Any]?

    private var videoInput: AVCaptureDeviceInput?
    private var outputsInstalled = false
    private var hasRecordOutput = false
    private var currentPosition: AVCaptureDevice.Position?
    /// True while the input is the physical wide camera for 120/240 fps video.
    private var currentHighFrameRate = false
    private var currentFormatIndex: Int?
    private var currentAppleLog = false
    /// Cameras whose hand-picked 4:3 format gave no RAW. Their photos use the `.photo` preset instead,
    /// which always offers RAW where the camera has it, at the cost of a rebuild when switching to video.
    private var photoPresetPositions: Set<AVCaptureDevice.Position> = []
    /// Zoom factor of the virtual device at which each lens takes over. 1 is the widest lens.
    private var lensZoomFactors: [LensID: Double] = [.wide: 1]
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]

    /// One list the Camera Control button can scroll through, e.g. the presets.
    struct ControlPicker: @unchecked Sendable {
        var title: String
        var symbol: String
        var titles: [String]
        var selected: Int
        var pick: (Int) -> Void
    }

    /// What Camera Control offers besides zoom and exposure. Read on the session queue.
    private var controlPickers: [ControlPicker] = []
    /// The titles the installed pickers were built with; a change rebuilds them.
    private var installedPickerTitles: [[String]] = []
    private var installedControlsDevice: AVCaptureDevice?
    /// `AVCaptureIndexPicker`s by title, kept to move their selection when the app changes it.
    private var indexPickers: [String: AnyObject] = [:]
    private var controlsDelegate: AnyObject?

    override init() {
        hub = FrameHub(queue: captureQueue)
        super.init()
    }

    // MARK: Permissions

    func requestVideoAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: Session

    /// Brings the session in line with `config`. Safe to call repeatedly; the last call wins.
    func apply(_ config: Config) async -> DeviceInfo {
        setMicrophone(enabled: config.mode == .video)
        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: self.applyOnQueue(config))
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        setMicrophone(enabled: false)
    }

    private func backDevice() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    private func device(for position: AVCaptureDevice.Position, highFrameRate: Bool = false) -> AVCaptureDevice? {
        if position == .front { return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) }
        if highFrameRate, let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) { return wide }
        return backDevice()
    }

    private struct FormatPlan {
        var index: Int?
        var appleLog: Bool
        /// Used only when no format matched.
        var fallbackPreset: AVCaptureSession.Preset
    }

    private func plan(for config: Config, device: AVCaptureDevice) -> FormatPlan {
        let formats = Self.describe(device.formats)
        let photo = FormatChooser.photoFormat(formats)
        let fallback: AVCaptureSession.Preset = config.mode == .photo
            ? .photo
            : (config.format.width >= 3840 ? .hd4K3840x2160 : .hd1920x1080)
        if config.mode == .photo {
            let usePreset = config.wantsRAW && photoPresetPositions.contains(device.position)
            return FormatPlan(index: usePreset ? nil : photo?.index, appleLog: false, fallbackPreset: fallback)
        }
        let choice = FormatChooser.videoFormat(
            formats,
            width: config.format.width,
            fps: config.format.fps,
            appleLog: config.appleLog && device.position == .back,
            photo: photo
        )
        return FormatPlan(index: choice?.format.index, appleLog: choice?.appleLog ?? false, fallbackPreset: fallback)
    }

    static func describe(_ formats: [AVCaptureDevice.Format]) -> [FormatDescriptor] {
        formats.enumerated().map { index, format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            return FormatDescriptor(
                index: index,
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                maxFPS: format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0,
                supportsAppleLog: format.supportedColorSpaces.contains(.appleLog),
                isFullRange8Bit: subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                maxPhotoPixels: format.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
            )
        }
    }

    private func applyOnQueue(_ config: Config) -> DeviceInfo {
        let position: AVCaptureDevice.Position = config.lens == .front ? .front : .back
        // The multi-camera virtual device offers no formats above 60 fps; the main camera alone does.
        let highFrameRate = config.mode == .video && config.format.fps > FormatChooser.highFrameRate && position == .back
        let needsInput = videoInput == nil || currentPosition != position || currentHighFrameRate != highFrameRate
        let candidate = needsInput ? self.device(for: position, highFrameRate: highFrameRate) : videoInput?.device
        guard let device = candidate else {
            return DeviceInfo(focalLengths: ZoomStop.defaultFocalLengths, rawAvailable: false, appleLogActive: false, didReconfigure: false, frameRates: [:])
        }

        let formatPlan = self.plan(for: config, device: device)
        let needsFormat = needsInput
            || formatPlan.index != currentFormatIndex
            || formatPlan.appleLog != currentAppleLog
            || (formatPlan.index == nil && session.sessionPreset != formatPlan.fallbackPreset)
        let structural = needsFormat || !outputsInstalled
        let wasRunning = session.isRunning

        if structural {
            session.beginConfiguration()
            session.automaticallyConfiguresCaptureDeviceForWideColor = false
            installOutputsIfNeeded()
            if needsInput {
                swapInput(to: device, position: position)
                currentHighFrameRate = highFrameRate
            }
            if let index = formatPlan.index, index < device.formats.count {
                setFormat(device.formats[index], appleLog: formatPlan.appleLog, on: device)
            } else if session.canSetSessionPreset(formatPlan.fallbackPreset) {
                session.sessionPreset = formatPlan.fallbackPreset
                setColorSpace(appleLog: false, on: device)
            }
            currentFormatIndex = formatPlan.index
            currentAppleLog = formatPlan.appleLog
            setDepthFormat(on: device)
            configurePhotoOutput(device: device, resolution: config.photoResolution, rawFormat: config.rawFormat)
            if #available(iOS 18.0, *) { installControls(device: device) }
            session.commitConfiguration()
            // 10-bit Y'CbCr keeps Apple Log precise. The list of pixel formats is only valid after the commit.
            setPixelFormat(tenBit: formatPlan.appleLog)
        }

        // A new photo size does not need a new format, so it is applied on every configuration.
        if !structural { configurePhotoOutput(device: device, resolution: config.photoResolution, rawFormat: config.rawFormat) }

        // RAW is what Redevelop works from. If the chosen format has none, fall back to the photo preset once.
        if structural, config.mode == .photo, config.wantsRAW, position == .back, formatPlan.index != nil,
           photoOutput.availableRawPhotoPixelFormatTypes.isEmpty, !photoPresetPositions.contains(position) {
            photoPresetPositions.insert(position)
            return applyOnQueue(config)
        }

        configureDevice(config, device: device)
        configureConnections(config)
        updateDepthOutput(enabled: config.portrait && config.mode == .photo && position == .back, device: device)

        if !session.isRunning { session.startRunning() }

        // Rates come from the camera in use and, on the back, from the main camera alone, which is where
        // 120 and 240 fps live.
        var described = Self.describe(device.formats)
        if position == .back, let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), wide != device {
            described += Self.describe(wide.formats)
        }
        return DeviceInfo(
            focalLengths: focalLengths(),
            rawAvailable: !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty,
            appleLogActive: formatPlan.appleLog,
            didReconfigure: structural && wasRunning,
            frameRates: [1920: FormatChooser.frameRates(described, width: 1920), 3840: FormatChooser.frameRates(described, width: 3840)]
        )
    }

    // MARK: Cine exposure

    private var cineTimer: DispatchSourceTimer?
    private var cineFPS = 24
    private var userLocked = false
    /// What the cine loop shows: shutter and ISO, and how they stand against the cinematic rule.
    struct CineState: Equatable, Sendable {
        var readout: String
        var status: CineExposure.Status
    }

    /// Called on the main queue with the loop's state, or nil when it stops.
    var onCineState: (@Sendable (CineState?) -> Void)?
    /// Mains frequency where the phone is, for flicker-free shutter times.
    private let mainsHz = CineExposure.mainsFrequency(regionCode: Locale.current.region?.identifier)

    /// Starts or stops cinematic auto exposure (`CineExposure`) for video at `fps`.
    func setCineExposure(_ enabled: Bool, fps: Int) {
        sessionQueue.async {
            self.cineFPS = fps
            if enabled {
                guard self.cineTimer == nil else { return }
                let timer = DispatchSource.makeTimerSource(queue: self.sessionQueue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(120))
                timer.setEventHandler { [weak self] in self?.cineTick() }
                self.cineTimer = timer
                timer.resume()
            } else if let timer = self.cineTimer {
                timer.cancel()
                self.cineTimer = nil
                if let device = self.videoInput?.device, !self.userLocked, device.isExposureModeSupported(.continuousAutoExposure) {
                    try? device.lockForConfiguration()
                    device.exposureMode = .continuousAutoExposure
                    device.unlockForConfiguration()
                }
                self.lastCineState = nil
                let report = self.onCineState
                DispatchQueue.main.async { report?(nil) }
            }
        }
    }

    private var lastCineState: CineState?

    private func cineTick() {
        guard !userLocked, let device = videoInput?.device, device.isExposureModeSupported(.custom) else { return }
        let format = device.activeFormat
        let limits = CineExposure.Limits(
            minISO: Double(format.minISO),
            maxISO: Double(format.maxISO),
            minDuration: format.minExposureDuration.seconds,
            maxDuration: format.maxExposureDuration.seconds
        )
        let current = CineExposure.Setting(iso: Double(device.iso), duration: device.exposureDuration.seconds)
        guard current.duration > 0, current.iso > 0 else { return }
        let step = CineExposure.step(current: current, offset: Double(device.exposureTargetOffset), fps: cineFPS, limits: limits, mainsHz: mainsHz)
        let next = step.setting
        let changed = abs(next.iso - current.iso) / current.iso > 0.01 || abs(next.duration - current.duration) / current.duration > 0.01
        if changed || device.exposureMode != .custom {
            do {
                try device.lockForConfiguration()
                device.setExposureModeCustom(
                    duration: CMTime(seconds: next.duration, preferredTimescale: 1_000_000),
                    iso: Float(next.iso),
                    completionHandler: nil
                )
                device.unlockForConfiguration()
            } catch {
                return
            }
        }
        let state = CineState(readout: CineExposure.readout(next), status: step.status)
        if state != lastCineState {
            lastCineState = state
            let report = onCineState
            DispatchQueue.main.async { report?(state) }
        }
    }

    // MARK: Camera Control

    /// Sets the lists on the Camera Control button (iPhone 16 and later). Only a change of the lists
    /// themselves rebuilds the controls; a new selection just moves the pickers.
    func setControlPickers(_ pickers: [ControlPicker]) {
        sessionQueue.async {
            self.controlPickers = pickers
            guard #available(iOS 18.0, *), let device = self.installedControlsDevice else { return }
            if pickers.map(\.titles) != self.installedPickerTitles || pickers.count != self.installedPickerTitles.count {
                self.session.beginConfiguration()
                self.installControls(device: device, force: true)
                self.session.commitConfiguration()
            } else {
                let selections = pickers.map { ($0.title, $0.selected) }
                DispatchQueue.main.async {
                    for (title, index) in selections {
                        (self.indexPickers[title] as? AVCaptureIndexPicker)?.selectedIndex = index
                    }
                }
            }
        }
    }

    /// Zoom and exposure as the system draws them, then the app's own pickers. Call inside a configuration.
    @available(iOS 18.0, *)
    private func installControls(device: AVCaptureDevice, force: Bool = false) {
        guard session.supportsControls else { return }
        guard force || device !== installedControlsDevice || controlPickers.map(\.titles) != installedPickerTitles else { return }
        if controlsDelegate == nil {
            let delegate = CameraControlsDelegate()
            controlsDelegate = delegate
            session.setControlsDelegate(delegate, queue: sessionQueue)
        }
        for control in session.controls { session.removeControl(control) }
        indexPickers = [:]

        var controls: [AVCaptureControl] = [
            AVCaptureSystemZoomSlider(device: device),
            AVCaptureSystemExposureBiasSlider(device: device),
        ]
        for item in controlPickers where !item.titles.isEmpty {
            let picker = AVCaptureIndexPicker(item.title, symbolName: item.symbol, localizedIndexTitles: item.titles)
            picker.selectedIndex = min(max(item.selected, 0), item.titles.count - 1)
            let pick = item.pick
            picker.setActionQueue(.main) { index in pick(index) }
            indexPickers[item.title] = picker
            controls.append(picker)
        }
        for control in controls.prefix(session.maxControlsCount) where session.canAddControl(control) {
            session.addControl(control)
        }
        installedControlsDevice = device
        installedPickerTitles = controlPickers.map(\.titles)
    }

    /// Streams depth to the hub while portrait mode is on; the connection is simply switched off otherwise.
    private func updateDepthOutput(enabled: Bool, device: AVCaptureDevice) {
        let wanted = enabled && device.activeDepthDataFormat != nil
        if wanted, !depthOutputAdded {
            session.beginConfiguration()
            if session.canAddOutput(depthOutput) {
                session.addOutput(depthOutput)
                depthOutput.isFilteringEnabled = true
                depthOutput.alwaysDiscardsLateDepthData = true
                depthOutput.setDelegate(hub, callbackQueue: depthQueue)
                depthOutputAdded = true
            }
            session.commitConfiguration()
        }
        guard depthOutputAdded, let connection = depthOutput.connection(with: .depthData) else {
            hub.setPortraitDepthAvailable(false)
            return
        }
        if connection.isEnabled != wanted { connection.isEnabled = wanted }
        var rotated = false
        if connection.isVideoRotationAngleSupported(90) {
            if connection.videoRotationAngle != 90 { connection.videoRotationAngle = 90 }
            rotated = true
        }
        hub.setDepthRotated(rotated)
        hub.setPortraitDepthAvailable(wanted)
    }

    private func installOutputsIfNeeded() {
        guard !outputsInstalled else { return }
        outputsInstalled = true

        for output in [previewOutput, recordOutput] {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(hub, queue: captureQueue)
        }
        if session.canAddOutput(previewOutput) { session.addOutput(previewOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        // A second video output needs iOS 16 and a capable device. Without it the viewfinder stream is recorded.
        if session.canAddOutput(recordOutput) {
            session.addOutput(recordOutput)
            hasRecordOutput = true
            // Writing is slower than showing; let the recording queue up frames rather than drop them.
            recordOutput.alwaysDiscardsLateVideoFrames = false
        }
        hub.setRecordOutput(hasRecordOutput ? recordOutput : nil)
    }

    private func swapInput(to device: AVCaptureDevice, position: AVCaptureDevice.Position) {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        if let old = videoInput { session.removeInput(old) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            currentPosition = position
            lensZoomFactors = position == .back ? zoomFactors(of: device) : [.wide: 1]
        }
    }

    private func setFormat(_ format: AVCaptureDevice.Format, appleLog: Bool, on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.activeFormat != format { device.activeFormat = format }
            applyColorSpace(appleLog: appleLog, on: device)
        } catch {
            // The device keeps its previous format.
        }
    }

    /// Portrait photos need a depth map. The device can only deliver one for a depth format that goes with its
    /// active video format, so the largest disparity or depth format is chosen. Nil when there is none.
    private func setDepthFormat(on device: AVCaptureDevice) {
        let depthTypes: Set<OSType> = [
            kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DepthFloat32,
            kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_DisparityFloat32,
        ]
        let usable = device.activeFormat.supportedDepthDataFormats.filter {
            depthTypes.contains(CMFormatDescriptionGetMediaSubType($0.formatDescription))
        }
        let largest = usable.max { lhs, rhs in
            let a = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(a.width) * Int(a.height) < Int(b.width) * Int(b.height)
        }
        guard device.activeDepthDataFormat != largest, (try? device.lockForConfiguration()) != nil else { return }
        device.activeDepthDataFormat = largest
        device.unlockForConfiguration()
    }

    private func setColorSpace(appleLog: Bool, on device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        applyColorSpace(appleLog: appleLog, on: device)
        device.unlockForConfiguration()
    }

    /// Call with the device locked.
    private func applyColorSpace(appleLog: Bool, on device: AVCaptureDevice) {
        let supported = device.activeFormat.supportedColorSpaces
        let wanted: AVCaptureColorSpace = appleLog && supported.contains(.appleLog) ? .appleLog : .sRGB
        if supported.contains(wanted), device.activeColorSpace != wanted { device.activeColorSpace = wanted }
    }

    private func setPixelFormat(tenBit: Bool) {
        for output in hasRecordOutput ? [previewOutput, recordOutput] : [previewOutput] {
            let available = output.availableVideoPixelFormatTypes
            let wanted: OSType
            if tenBit, available.contains(kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange) {
                wanted = kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
            } else if tenBit, available.contains(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) {
                wanted = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            } else {
                wanted = kCVPixelFormatType_32BGRA
            }
            let current = (output.videoSettings?[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber)?.uint32Value
            if current != wanted {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: wanted]
            }
        }
    }

    /// 12 MP photos (or the closest the format offers), and ProRAW where the format supports it unless Bayer RAW is wanted.
    private func configurePhotoOutput(device: AVCaptureDevice, resolution: PhotoResolution, rawFormat: RAWFormat) {
        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        let limit = resolution.pixelLimit ?? Int.max
        let fitting = dimensions.filter { Int($0.width) * Int($0.height) <= limit }
        let pixels: (CMVideoDimensions) -> Int = { Int($0.width) * Int($0.height) }
        if let best = fitting.max(by: { pixels($0) < pixels($1) }) ?? dimensions.min(by: { pixels($0) < pixels($1) }) {
            let current = photoOutput.maxPhotoDimensions
            if current.width != best.width || current.height != best.height { photoOutput.maxPhotoDimensions = best }
        }
        let proRAW = photoOutput.isAppleProRAWSupported && rawFormat == .proRAW
        if proRAW != photoOutput.isAppleProRAWEnabled {
            photoOutput.isAppleProRAWEnabled = proRAW
        }
        if photoOutput.isDepthDataDeliverySupported != photoOutput.isDepthDataDeliveryEnabled {
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        }
    }

    /// Where each lens of a virtual device takes over: the first constituent at zoom 1, the next ones at the switch-over factors.
    private func zoomFactors(of device: AVCaptureDevice) -> [LensID: Double] {
        let constituents = device.isVirtualDevice ? device.constituentDevices : [device]
        let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue)
        var result: [LensID: Double] = [:]
        for (index, constituent) in constituents.enumerated() {
            let lens: LensID?
            switch constituent.deviceType {
            case .builtInUltraWideCamera: lens = .ultraWide
            case .builtInWideAngleCamera: lens = .wide
            case .builtInTelephotoCamera: lens = .telephoto
            default: lens = nil
            }
            guard let lens else { continue }
            result[lens] = index == 0 ? 1.0 : (index - 1 < switchOver.count ? switchOver[index - 1] : 1.0)
        }
        if result[.wide] == nil { result[.wide] = result.values.min() ?? 1 }
        return result
    }

    // MARK: Microphone

    /// The microphone runs in its own session, started only in video mode so the indicator stays off for photos.
    private func setMicrophone(enabled: Bool) {
        audioQueue.async {
            guard enabled else {
                if self.audioSession.isRunning { self.audioSession.stopRunning() }
                return
            }
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
            if self.audioSession.inputs.isEmpty {
                self.audioSession.beginConfiguration()
                if let mic = AVCaptureDevice.default(for: .audio),
                   let input = try? AVCaptureDeviceInput(device: mic),
                   self.audioSession.canAddInput(input) {
                    self.audioSession.addInput(input)
                }
                if self.audioSession.canAddOutput(self.audioOutput) {
                    self.audioSession.addOutput(self.audioOutput)
                    self.audioOutput.setSampleBufferDelegate(self.hub, queue: self.captureQueue)
                }
                self.audioSession.commitConfiguration()
            }
            if !self.audioSession.isRunning { self.audioSession.startRunning() }
            // The first call can take a second or more, so it is done here rather than when recording starts.
            if self.audioSettings == nil, !self.audioSession.inputs.isEmpty {
                self.audioSettings = self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov)
            }
        }
    }

    private func configureConnections(_ config: Config) {
        let recordMode: AVCaptureVideoStabilizationMode = switch config.stabilization {
        case .off: .off
        case .standard: .standard
        case .cinematic: .cinematic
        }
        if hasRecordOutput {
            // The viewfinder is never stabilized; the recording always is, so switching modes changes nothing.
            configure(previewOutput.connection(with: .video), stabilization: .off)
            configure(recordOutput.connection(with: .video), stabilization: recordMode)
        } else {
            configure(previewOutput.connection(with: .video), stabilization: config.mode == .video ? recordMode : .off)
        }
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90), connection.videoRotationAngle != 90 { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported, connection.isVideoMirrored { connection.isVideoMirrored = false }
        }
    }

    private func configure(_ connection: AVCaptureConnection?, stabilization: AVCaptureVideoStabilizationMode) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(90), connection.videoRotationAngle != 90 { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported, connection.isVideoMirrored { connection.isVideoMirrored = false }
        if connection.isVideoStabilizationSupported, connection.preferredVideoStabilizationMode != stabilization {
            connection.preferredVideoStabilizationMode = stabilization
        }
    }

    private func configureDevice(_ config: Config, device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let fps = config.mode == .video ? Double(config.format.fps) : 30
            let supported = device.activeFormat.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }
            if supported {
                let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
                if device.activeVideoMinFrameDuration != duration { device.activeVideoMinFrameDuration = duration }
                if device.activeVideoMaxFrameDuration != duration { device.activeVideoMaxFrameDuration = duration }
            }

            device.videoZoomFactor = clampedZoom(zoomFactor(lens: config.lens, digital: config.digitalZoom), for: device)
            let bias = min(max(Float(config.exposureBias), device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureTargetBias(bias)
        } catch {
            // The device keeps its previous configuration.
        }
    }

    private func zoomFactor(lens: LensID, digital: Double) -> Double {
        (lens == .front ? 1.0 : (lensZoomFactors[lens] ?? 1.0)) * digital
    }

    private func clampedZoom(_ zoom: Double, for device: AVCaptureDevice) -> CGFloat {
        let upper = min(device.maxAvailableVideoZoomFactor, 30)
        return CGFloat(min(max(zoom, Double(device.minAvailableVideoZoomFactor)), Double(upper)))
    }

    /// 35 mm equivalent focal lengths, anchored to 24 mm for the main lens and scaled by where each lens takes over.
    private func focalLengths() -> [LensID: Double] {
        let wideZoom = lensZoomFactors[.wide] ?? 1
        var result: [LensID: Double] = [:]
        for (lens, zoom) in lensZoomFactors { result[lens] = 24 * zoom / wideZoom }
        return result.isEmpty ? ZoomStop.defaultFocalLengths : result
    }

    // MARK: Live adjustments

    /// Switches lens or zooms. With the virtual device this is only a zoom change, so it is instant.
    func setZoom(lens: LensID, digital: Double) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            try? device.lockForConfiguration()
            if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
            device.videoZoomFactor = self.clampedZoom(self.zoomFactor(lens: lens, digital: digital), for: device)
            device.unlockForConfiguration()
        }
    }

    func setExposureBias(_ bias: Double) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            try? device.lockForConfiguration()
            let clamped = min(max(Float(bias), device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
        }
    }

    func setLocked(_ locked: Bool) {
        sessionQueue.async {
            self.userLocked = locked
            guard let device = self.videoInput?.device else { return }
            // Unlocking hands exposure back to the cine loop when it runs.
            if !locked, self.cineTimer != nil {
                try? device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                device.unlockForConfiguration()
                return
            }
            try? device.lockForConfiguration()
            let focus: AVCaptureDevice.FocusMode = locked ? .locked : .continuousAutoFocus
            let exposure: AVCaptureDevice.ExposureMode = locked ? .locked : .continuousAutoExposure
            if device.isFocusModeSupported(focus) { device.focusMode = focus }
            if device.isExposureModeSupported(exposure) { device.exposureMode = exposure }
            device.unlockForConfiguration()
        }
    }

    /// `point` is in the device's coordinate space: (0,0) top-left to (1,1) bottom-right of the landscape sensor.
    func focus(at point: CGPoint, lockAfter: Bool) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = lockAfter ? .autoFocus : .continuousAutoFocus
            }
            // The cine loop owns exposure while it runs; a tap only moves the focus.
            if self.cineTimer == nil, device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = lockAfter ? .autoExpose : .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: Photo

    /// `portrait` asks for a depth map with the photo. RAW is skipped then, because depth is delivered with the processed image.
    func capturePhoto(flash: FlashMode, wantsRAW: Bool, rawFormat: RAWFormat, portrait: Bool, completion: @escaping @Sendable (PhotoOutcome) -> Void) {
        sessionQueue.async {
            let codec: AVVideoCodecType = self.photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
            let settings: AVCapturePhotoSettings
            let rawTypes = self.photoOutput.availableRawPhotoPixelFormatTypes
            // ProRAW carries Apple's merge and tone mapping; Bayer RAW is the plain sensor frame. Either falls back to the other.
            let proRAW = rawTypes.first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
            let bayer = rawTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
            let rawType = rawFormat == .bayer ? bayer ?? proRAW : proRAW ?? bayer
            if wantsRAW, !portrait, flash == .off, let rawType {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: [AVVideoCodecKey: codec])
                settings.photoQualityPrioritization = .speed
            } else {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
            }

            let flashMode: AVCaptureDevice.FlashMode = switch flash {
            case .off: .off
            case .auto: .auto
            case .on: .on
            }
            if self.photoOutput.supportedFlashModes.contains(flashMode) { settings.flashMode = flashMode }
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions

            if let connection = self.photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            settings.isDepthDataDeliveryEnabled = portrait && self.photoOutput.isDepthDataDeliveryEnabled

            let id = settings.uniqueID
            let delegate = PhotoCaptureDelegate { outcome in
                self.sessionQueue.async { self.photoDelegates[id] = nil }
                completion(outcome)
            }
            self.photoDelegates[id] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: Video

    func startRecording(url: URL, fps: Int, quarterTurns: Int = 0, onStart: @escaping @Sendable () -> Void, onFail: @escaping @Sendable (Error) -> Void) {
        // The audio queue owns the microphone session and its cached writer settings.
        audioQueue.async {
            let settings = self.audioSession.isRunning ? self.audioSettings : nil
            self.hub.startRecording(url: url, fps: fps, quarterTurns: quarterTurns, audioSettings: settings, onStart: onStart, onFail: onFail)
        }
    }

    func stopRecording(completion: @escaping @Sendable (URL?, Error?) -> Void) {
        hub.stopRecording(completion: completion)
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var raw: Data?
    private var processed: Data?
    private var depth: AVDepthData?
    private var failure: Error?
    private let completion: (CaptureSessionController.PhotoOutcome) -> Void

    init(completion: @escaping (CaptureSessionController.PhotoOutcome) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            failure = error
            return
        }
        if photo.isRawPhoto {
            raw = photo.fileDataRepresentation()
        } else {
            processed = photo.fileDataRepresentation()
            depth = photo.depthData
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(.init(raw: raw, processed: processed, depth: depth, error: error ?? failure))
    }
}

/// Camera Control needs a delegate on the session; RCamera keeps its own interface as it is meanwhile.
@available(iOS 18.0, *)
private final class CameraControlsDelegate: NSObject, AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

/// "1.8", "2.8", "11": f-numbers as camera dials print them.
enum ApertureTitle {
    static func format(_ value: Double) -> String {
        value >= 10 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}
