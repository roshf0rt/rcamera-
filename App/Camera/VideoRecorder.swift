import AVFoundation

enum RecorderError: Error {
    case cannotAddInput
    case noFrames
}

/// Writes already-processed frames and microphone audio into a .mov file.
/// All calls must come from the capture queue.
final class VideoRecorder {
    let url: URL

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var startTime = CMTime.invalid

    init(url: URL, width: Int, height: Int, fps: Int, audioSettings: [String: Any]?) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let bitrate = max(6_000_000, Int(Double(width * height * fps) * 0.12))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(videoInput) else { throw RecorderError.cannotAddInput }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if let audioSettings {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        self.url = url
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioInput = audioInput
    }

    /// Returns true when this frame started the recording session.
    func appendVideo(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard writer.status != .failed, writer.status != .cancelled else { return false }
        var started = false
        if !sessionStarted {
            guard writer.startWriting() else { return false }
            writer.startSession(atSourceTime: time)
            startTime = time
            sessionStarted = true
            started = true
        }
        if videoInput.isReadyForMoreMediaData {
            adaptor.append(buffer, withPresentationTime: time)
        }
        return started
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted, writer.status == .writing,
              let audioInput, audioInput.isReadyForMoreMediaData,
              CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= startTime
        else { return }
        audioInput.append(sampleBuffer)
    }

    func finish(_ completion: @escaping (URL?, Error?) -> Void) {
        guard sessionStarted else {
            writer.cancelWriting()
            completion(nil, RecorderError.noFrames)
            return
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        let writer = writer
        let url = url
        writer.finishWriting {
            completion(writer.status == .completed ? url : nil, writer.error)
        }
    }
}
