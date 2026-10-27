import AVFoundation
import CameraCore
import UIKit

/// Everything that touches AVCaptureSession. Work runs on a private serial queue, so this class is
/// deliberately not main-actor isolated.
final class CaptureSessionController: NSObject, @unchecked Sendable {
    struct Config: Sendable {
        var lens: LensID
        var mode: CaptureMode
        var format: VideoFormat
        var stabilization: Bool
        var digitalZoom: Double
        var exposureBias: Double
    }

    struct DeviceInfo: Sendable {
        var focalLengths: [LensID: Double]
        var rawAvailable: Bool
        var hasMicrophone: Bool
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
    private var currentLens: LensID?
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

    private func device(for lens: LensID) -> AVCaptureDevice? {
        switch lens {
        case .front: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        case .wide: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .ultraWide: AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .telephoto: AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        }
    }

    private func applyOnQueue(_ config: Config) -> DeviceInfo {
        session.beginConfiguration()

        installOutputsIfNeeded()

        // A lens that does not exist on this phone falls back to the main camera.
        let lens = device(for: config.lens) != nil ? config.lens : .wide
        if lens != currentLens || videoInput == nil, let device = device(for: lens),
           let input = try? AVCaptureDeviceInput(device: device) {
            if let old = videoInput { session.removeInput(old) }
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
                currentLens = lens
            }
        }

        let preset: AVCaptureSession.Preset = config.mode == .photo
            ? .photo
            : (config.format.width >= 3840 ? .hd4K3840x2160 : .hd1920x1080)
        if session.canSetSessionPreset(preset) { session.sessionPreset = preset }

        updateAudio(enabled: config.mode == .video)
        session.commitConfiguration()

        configureConnections(config)
        configureDevice(config)

        if !session.isRunning { session.startRunning() }

        return DeviceInfo(
            focalLengths: focalLengths(),
            rawAvailable: photoOutput.availableRawPhotoPixelFormatTypes.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) },
            hasMicrophone: audioInput != nil
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

    private func updateAudio(enabled: Bool) {
        let allowed = enabled && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if allowed {
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
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = (config.stabilization && config.mode == .video) ? .auto : .off
            }
        }
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
        }
    }

    private func configureDevice(_ config: Config) {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if config.mode == .video, config.format.fps > 0 {
                let fps = Double(config.format.fps)
                let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= fps && fps <= $0.maxFrameRate
                }
                if supported {
                    let duration = CMTime(value: 1, timescale: CMTimeScale(config.format.fps))
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                }
            } else {
                device.activeVideoMinFrameDuration = .invalid
                device.activeVideoMaxFrameDuration = .invalid
            }

            device.videoZoomFactor = clampedZoom(config.digitalZoom, for: device)
            let bias = min(max(Float(config.exposureBias), device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureTargetBias(bias)
        } catch {
            // The device keeps its previous configuration.
        }
    }

    private func clampedZoom(_ zoom: Double, for device: AVCaptureDevice) -> CGFloat {
        let upper = min(device.maxAvailableVideoZoomFactor, 15)
        return CGFloat(min(max(zoom, Double(device.minAvailableVideoZoomFactor)), Double(upper)))
    }

    /// 35 mm equivalent focal lengths derived from each lens's field of view, anchored to 24 mm for the main lens.
    private func focalLengths() -> [LensID: Double] {
        func halfTangent(_ device: AVCaptureDevice) -> Double {
            tan(Double(device.activeFormat.videoFieldOfView) * .pi / 360)
        }
        guard let wide = device(for: .wide) else { return ZoomStop.defaultFocalLengths }
        let reference = halfTangent(wide)
        var result: [LensID: Double] = [.wide: 24]
        for lens in [LensID.ultraWide, .telephoto] {
            if let device = device(for: lens) {
                result[lens] = 24 * reference / halfTangent(device)
            }
        }
        return result
    }

    // MARK: Live adjustments

    func setZoom(_ zoom: Double) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            try? device.lockForConfiguration()
            device.videoZoomFactor = self.clampedZoom(zoom, for: device)
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
            if wantsRAW, flash == .off,
               let rawType = self.photoOutput.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) {
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
