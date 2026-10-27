import AVFoundation
import CameraCore
import UIKit

/// Everything that touches AVCaptureSession. Work runs on a private serial queue, so this class is
/// deliberately not main-actor isolated.
///
/// The back cameras are driven as one virtual device (triple, dual-wide or dual). Switching lenses is then
/// just a zoom change, which is instant and keeps the viewfinder running. The session is only reconfigured
/// when something structural changes: front/back, photo/video, or the microphone.
final class CaptureSessionController: NSObject, @unchecked Sendable {
    struct Config: Sendable {
        var lens: LensID
        var mode: CaptureMode
        var format: VideoFormat
        var stabilization: VideoStabilization
        var appleLog: Bool
        var digitalZoom: Double
        var exposureBias: Double
    }

    struct DeviceInfo: Sendable {
        var focalLengths: [LensID: Double]
        var rawAvailable: Bool
        var hasMicrophone: Bool
        var appleLogActive: Bool
    }

    struct PhotoOutcome: @unchecked Sendable {
        var raw: Data?
        var processed: Data?
        var error: Error?
    }

    let session = AVCaptureSession()
    let hub: FrameHub

    private let sessionQueue = DispatchQueue(label: "rcamera.session")
    private let captureQueue = DispatchQueue(label: "rcamera.capture")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var outputsInstalled = false
    private var currentPosition: AVCaptureDevice.Position?
    /// Zoom factor of the virtual device at which each lens takes over. 1 is the widest lens.
    private var lensZoomFactors: [LensID: Double] = [.wide: 1]
    private var currentLens: LensID = .wide
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]

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
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: self.applyOnQueue(config))
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func backDevice() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    private func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        position == .front
            ? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            : backDevice()
    }

    private func applyOnQueue(_ config: Config) -> DeviceInfo {
        let position: AVCaptureDevice.Position = config.lens == .front ? .front : .back
        let preset: AVCaptureSession.Preset = config.mode == .photo
            ? .photo
            : (config.format.width >= 3840 ? .hd4K3840x2160 : .hd1920x1080)
        let wantsAudio = config.mode == .video && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        let needsInput = videoInput == nil || currentPosition != position
        let needsPreset = session.sessionPreset != preset
        let needsAudio = wantsAudio != (audioInput != nil)

        // Reconfigure only when the structure changes, so lens switches stay instant.
        if needsInput || needsPreset || needsAudio || !outputsInstalled {
            session.beginConfiguration()
            installOutputsIfNeeded()
            if needsInput { swapInput(to: position) }
            if session.canSetSessionPreset(preset) { session.sessionPreset = preset }
            updateAudio(enabled: wantsAudio)
            if photoOutput.isAppleProRAWSupported, !photoOutput.isAppleProRAWEnabled {
                photoOutput.isAppleProRAWEnabled = true
            }
            session.commitConfiguration()
        }

        currentLens = config.lens
        let appleLogActive = configureDevice(config)
        configureConnections(config)

        if !session.isRunning { session.startRunning() }

        return DeviceInfo(
            focalLengths: focalLengths(),
            rawAvailable: !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty,
            hasMicrophone: audioInput != nil,
            appleLogActive: appleLogActive
        )
    }

    private func installOutputsIfNeeded() {
        guard !outputsInstalled else { return }
        outputsInstalled = true

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(hub, queue: captureQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        audioOutput.setSampleBufferDelegate(hub, queue: captureQueue)
    }

    private func swapInput(to position: AVCaptureDevice.Position) {
        guard let device = device(for: position), let input = try? AVCaptureDeviceInput(device: device) else { return }
        if let old = videoInput { session.removeInput(old) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            currentPosition = position
            lensZoomFactors = position == .back ? zoomFactors(of: device) : [.wide: 1]
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

    private func updateAudio(enabled: Bool) {
        if enabled {
            if audioInput == nil, let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
            if !session.outputs.contains(audioOutput), session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }
        } else {
            if let input = audioInput {
                session.removeInput(input)
                audioInput = nil
            }
            if session.outputs.contains(audioOutput) { session.removeOutput(audioOutput) }
        }
    }

    private func configureConnections(_ config: Config) {
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90), connection.videoRotationAngle != 90 { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported, connection.isVideoMirrored { connection.isVideoMirrored = false }
            if connection.isVideoStabilizationSupported {
                // `.auto` picks cinematic modes that buffer frames, which makes the viewfinder lag.
                let mode: AVCaptureVideoStabilizationMode
                switch (config.mode, config.stabilization) {
                case (.photo, _), (_, .off): mode = .off
                case (.video, .standard): mode = .standard
                case (.video, .cinematic): mode = .cinematic
                }
                if connection.preferredVideoStabilizationMode != mode { connection.preferredVideoStabilizationMode = mode }
            }
        }
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90), connection.videoRotationAngle != 90 { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported, connection.isVideoMirrored { connection.isVideoMirrored = false }
        }
    }

    /// Returns whether the camera is now delivering Apple Log.
    private func configureDevice(_ config: Config) -> Bool {
        guard let device = videoInput?.device else { return false }
        var appleLogActive = false
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let wantsFPS = config.mode == .video && config.format.fps > 0
            let fps = Double(config.format.fps)
            func supportsFPS(_ format: AVCaptureDevice.Format) -> Bool {
                format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }
            }

            if config.mode == .video, config.appleLog, device.position == .back {
                let width = Int32(config.format.width)
                let candidate = device.formats.first {
                    CMVideoFormatDescriptionGetDimensions($0.formatDescription).width == width
                        && $0.supportedColorSpaces.contains(.appleLog)
                        && supportsFPS($0)
                }
                if let candidate {
                    if device.activeFormat != candidate { device.activeFormat = candidate }
                    device.activeColorSpace = .appleLog
                    appleLogActive = true
                }
            }
            if !appleLogActive, device.activeColorSpace != .sRGB, device.activeFormat.supportedColorSpaces.contains(.sRGB) {
                device.activeColorSpace = .sRGB
            }

            if wantsFPS, supportsFPS(device.activeFormat) {
                let duration = CMTime(value: 1, timescale: CMTimeScale(config.format.fps))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            } else if !wantsFPS {
                device.activeVideoMinFrameDuration = .invalid
                device.activeVideoMaxFrameDuration = .invalid
            }

            device.videoZoomFactor = clampedZoom(zoomFactor(lens: config.lens, digital: config.digitalZoom), for: device)
            let bias = min(max(Float(config.exposureBias), device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureTargetBias(bias)
        } catch {
            // The device keeps its previous configuration.
        }
        return appleLogActive
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
            guard let device = self.videoInput?.device else { return }
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
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = lockAfter ? .autoExpose : .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: Photo

    func capturePhoto(flash: FlashMode, wantsRAW: Bool, completion: @escaping @Sendable (PhotoOutcome) -> Void) {
        sessionQueue.async {
            let codec: AVVideoCodecType = self.photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
            let settings: AVCapturePhotoSettings
            let rawTypes = self.photoOutput.availableRawPhotoPixelFormatTypes
            // ProRAW carries Apple's own tone mapping, so it develops much closer to the camera's look than Bayer RAW.
            let rawType = rawTypes.first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
                ?? rawTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
            if wantsRAW, flash == .off, let rawType {
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

            if let connection = self.photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

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

    func startRecording(url: URL, fps: Int, onStart: @escaping @Sendable () -> Void, onFail: @escaping @Sendable (Error) -> Void) {
        let audioSettings = audioInput == nil ? nil : audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]
        hub.startRecording(url: url, fps: fps, audioSettings: audioSettings, onStart: onStart, onFail: onFail)
    }

    func stopRecording(completion: @escaping @Sendable (URL?, Error?) -> Void) {
        hub.stopRecording(completion: completion)
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var raw: Data?
    private var processed: Data?
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
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(.init(raw: raw, processed: processed, error: error ?? failure))
    }
}
