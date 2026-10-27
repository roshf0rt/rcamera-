import AVFoundation
import CameraCore
import CoreImage

/// Receives raw camera frames on the capture queue, crops them to the chosen aspect, applies the
/// preset look, then shows the result and (when recording) writes it to disk.
final class FrameHub: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Geometry {
        var source: CGSize
        var crop: CropRect
    }

    private struct PendingRecording {
        var url: URL
        var fps: Int
        var audioSettings: [String: Any]?
        var onStart: () -> Void
        var onFail: (Error) -> Void
    }

    let displayLayer = AVSampleBufferDisplayLayer()

    private let queue: DispatchQueue
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()

    private var look = FilmLook.identity
    private var aspect: AspectOption?
    private var mirror = false
    private var geometry: Geometry?
    private var pending: PendingRecording?
    private var recorder: VideoRecorder?

    private var pool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        displayLayer.videoGravity = .resizeAspectFill
    }

    func configure(look: FilmLook, aspect: AspectOption?, mirror: Bool) {
        lock.lock()
        self.look = look
        self.aspect = aspect
        self.mirror = mirror
        lock.unlock()
    }

    var currentGeometry: Geometry? {
        lock.lock()
        defer { lock.unlock() }
        return geometry
    }

    // MARK: Recording

    func startRecording(url: URL, fps: Int, audioSettings: [String: Any]?, onStart: @escaping () -> Void, onFail: @escaping (Error) -> Void) {
        lock.lock()
        pending = PendingRecording(url: url, fps: fps, audioSettings: audioSettings, onStart: onStart, onFail: onFail)
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
        let look = look, aspect = aspect, mirror = mirror
        lock.unlock()

        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let crop = aspect?.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
            ?? CropRect(x: 0, y: 0, width: sourceWidth & ~1, height: sourceHeight & ~1)

        // Core Image's origin is bottom-left.
        let rect = CGRect(x: crop.x, y: sourceHeight - crop.y - crop.height, width: crop.width, height: crop.height)
        var image = CIImage(cvPixelBuffer: source)
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        image = look.apply(to: image)
        if mirror {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -CGFloat(crop.width), y: 0))
        }

        guard let output = makeBuffer(width: crop.width, height: crop.height) else { return }
        ciContext.render(image, to: output)

        lock.lock()
        geometry = Geometry(source: CGSize(width: sourceWidth, height: sourceHeight), crop: crop)
        lock.unlock()

        display(output, at: time)
        record(output, at: time, width: crop.width, height: crop.height)
    }

    private func record(_ buffer: CVPixelBuffer, at time: CMTime, width: Int, height: Int) {
        lock.lock()
        var recorder = recorder
        let pending = pending
        lock.unlock()

        if recorder == nil, let pending {
            do {
                recorder = try VideoRecorder(url: pending.url, width: width, height: height, fps: pending.fps, audioSettings: pending.audioSettings)
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
            lock.unlock()
        }

        if let recorder, recorder.appendVideo(buffer, at: time), let pending {
            pending.onStart()
        }
    }

    // MARK: Output helpers

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolWidth != width || poolHeight != height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool)
            pool = newPool
            poolWidth = width
            poolHeight = height
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

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
