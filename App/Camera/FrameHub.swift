import AVFoundation
import CameraCore
import CoreImage
import QuartzCore

/// Receives camera frames on the capture queue, crops them to the chosen aspect, grades them on the GPU,
/// then shows the result and (when recording) writes it to disk.
///
/// With two video outputs (iOS 16+ on most devices) the viewfinder stream is unstabilized, so it has no
/// delay, and a second stream carries stabilized frames for the recording only. Lampa does the same
/// ("stream stabilization" and "recorder stabilization"). With one output, that output does both.
final class FrameHub: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    /// How the selected lens draws the live portrait background. Nil when portrait mode is off.
    struct PortraitLook: Equatable {
        var strength: Float
        var lens: LensStyle
    }

    struct Geometry {
        var source: CGSize
        var crop: CropRect
    }

    private struct PendingRecording {
        var url: URL
        var fps: Int
        /// The phone held sideways: the file says to show the frames turned.
        var quarterTurns: Int
        var audioSettings: [String: Any]?
        /// Frames captured before the button press are dropped. Stabilization delays frames, so some arrive late.
        var requestTime: CMTime
        var onStart: () -> Void
        var onFail: (Error) -> Void
    }

    let displayLayer = AVSampleBufferDisplayLayer()

    private let queue: DispatchQueue
    private let grader = MetalGrader.shared
    /// Used only if Metal is unavailable: crops without the look.
    private let fallbackContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
    private let lock = NSLock()

    private var look = FilmLook.identity
    private var fade: Fade?
    private static let fadeDuration: CFTimeInterval = 0.3

    /// The looks being faded out, and when the fade began.
    private struct Fade {
        var look: FilmLook
        var logLook: FilmLook?
        var start: CFTimeInterval
    }
    private var logLook: FilmLook?
    private var portraitLook: PortraitLook?
    /// The newest disparity map, with the subject's disparity from its middle.
    private var depth: (map: CVPixelBuffer, focus: Float)?
    private var depthRotated = false
    private var aspect: AspectOption = .ratio4x3
    private var mirror = false
    private weak var recordOutput: AVCaptureOutput?
    private var geometry: Geometry?
    private var pending: PendingRecording?
    private var recorder: VideoRecorder?
    private var startNotification: (() -> Void)?
    private var deliveredFrames = 0

    private let previewPool = PixelBufferPool()
    private let recordPool = PixelBufferPool()

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        displayLayer.videoGravity = .resizeAspectFill
    }

    /// `logLook` grades 10-bit Apple Log frames; everything else uses `look`.
    /// A change of LUT crossfades over `fadeDuration`, so switching presets feels smooth rather than abrupt.
    func configure(look: FilmLook, logLook: FilmLook?, aspect: AspectOption, mirror: Bool) {
        lock.lock()
        let lutChanged = look.lutIdentity != self.look.lutIdentity
            || logLook?.lutIdentity != self.logLook?.lutIdentity
        if lutChanged, deliveredFrames > 0 {
            fade = Fade(look: self.look, logLook: self.logLook, start: CACurrentMediaTime())
        }
        self.look = look
        self.logLook = logLook
        self.aspect = aspect
        self.mirror = mirror
        lock.unlock()
    }

    /// Turns the live portrait background on (with the lens's look) or off.
    func setPortrait(_ look: PortraitLook?) {
        lock.lock()
        portraitLook = look
        if look == nil { depth = nil }
        lock.unlock()
    }

    /// Clears the last depth map when depth stops coming, so an old map is never used.
    func setPortraitDepthAvailable(_ available: Bool) {
        guard !available else { return }
        lock.lock()
        depth = nil
        lock.unlock()
    }

    /// Whether the depth connection was turned to portrait like the video ones.
    func setDepthRotated(_ rotated: Bool) {
        lock.lock()
        depthRotated = rotated
        lock.unlock()
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        let disparity = depthData.depthDataType == kCVPixelFormatType_DisparityFloat16
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat16)
        let map = disparity.depthDataMap
        guard let focus = Self.middleDisparity(map) else { return }
        lock.lock()
        // Smooth the focus a little so the edge of the blur does not shimmer.
        let previous = depth?.focus ?? focus
        depth = (map, previous * 0.7 + focus * 0.3)
        lock.unlock()
    }

    /// Mean disparity over the middle fifth of the map, where the portrait subject usually is.
    private static func middleDisparity(_ map: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var sum: Float = 0
        var count = 0
        for y in stride(from: height * 2 / 5, to: height * 3 / 5, by: 2) {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float16.self)
            for x in stride(from: width * 2 / 5, to: width * 3 / 5, by: 2) {
                let value = Float(row[x])
                if value.isFinite, value > 0 {
                    sum += value
                    count += 1
                }
            }
        }
        return count > 0 ? sum / Float(count) : nil
    }

    /// The output whose frames are only recorded. Nil when the viewfinder stream is recorded too.
    func setRecordOutput(_ output: AVCaptureOutput?) {
        lock.lock()
        recordOutput = output
        lock.unlock()
    }

    var currentGeometry: Geometry? {
        lock.lock()
        defer { lock.unlock() }
        return geometry
    }

    /// Viewfinder frames shown so far. Used to keep the switch blur up until fresh frames arrive.
    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return deliveredFrames
    }

    // MARK: Recording

    func startRecording(url: URL, fps: Int, quarterTurns: Int = 0, audioSettings: [String: Any]?, onStart: @escaping () -> Void, onFail: @escaping (Error) -> Void) {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        lock.lock()
        pending = PendingRecording(url: url, fps: fps, quarterTurns: quarterTurns, audioSettings: audioSettings, requestTime: now, onStart: onStart, onFail: onFail)
        lock.unlock()
    }

    func stopRecording(completion: @escaping (URL?, Error?) -> Void) {
        lock.lock()
        let recorder = recorder
        let hadPending = pending != nil
        self.recorder = nil
        pending = nil
        lock.unlock()

        guard let recorder else {
            completion(nil, hadPending ? RecorderError.noFrames : nil)
            return
        }
        // Appends happen on this queue, so finishing here cannot race with them.
        queue.async { recorder.finish(completion) }
    }

    // MARK: Sample buffers

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            lock.lock()
            let recorder = recorder
            lock.unlock()
            recorder?.appendAudio(sampleBuffer)
            return
        }
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        let isLog = Self.isTenBit(source)
        let look = isLog ? (logLook ?? look) : look
        var previous: FilmLook?
        var previousMix: Float = 0
        if let fade {
            let progress = (CACurrentMediaTime() - fade.start) / Self.fadeDuration
            if progress >= 1 {
                self.fade = nil
            } else {
                previous = isLog ? (fade.logLook ?? fade.look) : fade.look
                // Ease out: quick start, gentle landing.
                let remaining = Float(1 - progress)
                previousMix = remaining * remaining
            }
        }
        let aspect = aspect, mirror = mirror
        let portrait: PortraitPass? = {
            guard let portraitLook, let depth else { return nil }
            return PortraitPass(depth: depth.map, depthRotated: depthRotated, focus: depth.focus,
                                strength: portraitLook.strength, lens: portraitLook.lens)
        }()
        let separateRecordStream = recordOutput != nil
        let isRecordStream = separateRecordStream && output === recordOutput
        let wantsRecording = recorder != nil || pending != nil
        lock.unlock()

        if isRecordStream {
            guard wantsRecording,
                  let rendered = render(source, pool: recordPool, look: look, previous: previous, previousMix: previousMix, aspect: aspect, mirror: mirror)
            else { return }
            record(rendered.buffer, at: time, width: rendered.crop.width, height: rendered.crop.height)
            return
        }

        guard let rendered = render(source, pool: previewPool, look: look, previous: previous, previousMix: previousMix, aspect: aspect, mirror: mirror, portrait: portrait) else { return }
        let buffer = rendered.buffer, crop = rendered.crop
        lock.lock()
        geometry = Geometry(source: CGSize(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source)), crop: crop)
        deliveredFrames += 1
        lock.unlock()

        display(buffer, at: time)
        if !separateRecordStream, wantsRecording {
            record(buffer, at: time, width: crop.width, height: crop.height)
        }
    }

    private static func isTenBit(_ buffer: CVPixelBuffer) -> Bool {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        return format == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    }

    private func render(
        _ source: CVPixelBuffer,
        pool: PixelBufferPool,
        look: FilmLook,
        previous: FilmLook?,
        previousMix: Float,
        aspect: AspectOption,
        mirror: Bool,
        portrait: PortraitPass? = nil
    ) -> (buffer: CVPixelBuffer, crop: CropRect)? {
        let crop = aspect.cropRect(sourceWidth: CVPixelBufferGetWidth(source), sourceHeight: CVPixelBufferGetHeight(source))
        guard let output = pool.buffer(width: crop.width, height: crop.height) else { return nil }
        if let grader, grader.grade(source: source, crop: crop, mirror: mirror, look: look, into: output, previous: previous, previousMix: previousMix, portrait: portrait) {
            return (output, crop)
        }

        // Core Image's origin is bottom-left.
        let sourceHeight = CVPixelBufferGetHeight(source)
        let rect = CGRect(x: crop.x, y: sourceHeight - crop.y - crop.height, width: crop.width, height: crop.height)
        var image = CIImage(cvPixelBuffer: source, options: [.colorSpace: NSNull()])
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        if mirror {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -CGFloat(crop.width), y: 0))
        }
        fallbackContext.render(image, to: output)
        return (output, crop)
    }

    private func record(_ buffer: CVPixelBuffer, at time: CMTime, width: Int, height: Int) {
        lock.lock()
        var recorder = recorder
        let pending = pending
        lock.unlock()

        if recorder == nil, let pending {
            if CMTimeCompare(time, pending.requestTime) < 0 { return }
            do {
                recorder = try VideoRecorder(url: pending.url, width: width, height: height, fps: pending.fps, quarterTurns: pending.quarterTurns, audioSettings: pending.audioSettings)
            } catch {
                lock.lock()
                self.pending = nil
                lock.unlock()
                pending.onFail(error)
                return
            }
            lock.lock()
            self.recorder = recorder
            self.pending = nil
            startNotification = pending.onStart
            lock.unlock()
        }

        if let recorder, recorder.appendVideo(buffer, at: time) {
            lock.lock()
            let notify = startNotification
            startNotification = nil
            lock.unlock()
            notify?()
        }
    }

    // MARK: Display

    private func display(_ buffer: CVPixelBuffer, at time: CMTime) {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: buffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sampleBuffer)
    }
}

/// BGRA buffers the GPU can write into, recreated when the size changes.
final class PixelBufferPool {
    private var pool: CVPixelBufferPool?
    private var width = 0
    private var height = 0

    func buffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || self.width != width || self.height != height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool)
            pool = newPool
            self.width = width
            self.height = height
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
