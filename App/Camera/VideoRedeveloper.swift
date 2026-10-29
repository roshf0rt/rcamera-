import AVFoundation
import CameraCore
import CoreVideo

/// Grades a recorded Apple Log video frame by frame with a look, as the viewfinder grades live frames, and
/// writes the result as a new file. The sound is copied across as it is. Runs in the background; the
/// grader is the app's own, so it does not share state with the viewfinder.
enum VideoRedeveloper {
    enum Failure: LocalizedError {
        case noVideo
        case cannotRead
        case cannotWrite
        case grading

        var errorDescription: String? {
            switch self {
            case .noVideo: "The video has no picture track."
            case .cannotRead: "The recorded video could not be read."
            case .cannotWrite: "The developed video could not be written."
            case .grading: "The video could not be graded on this device."
            }
        }
    }

    /// `progress` gets 0 to 1 as frames are written.
    static func develop(source: URL, output: URL, look: FilmLook, progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: output)
        guard let grader = MetalGrader.makeForBackground() else { throw Failure.grading }

        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let width = Int(size.width), height = Int(size.height)

        let reader = try AVAssetReader(asset: asset)
        // Log frames come out as 10-bit 4:2:0, the format the grader reads.
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw Failure.cannotRead }
        reader.add(videoOutput)
        var audioOutput: AVAssetReaderTrackOutput?
        if let audio {
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(6_000_000, width * height * 30 * 12 / 100)],
        ])
        videoInput.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(videoInput) else { throw Failure.cannotWrite }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000,
            ])
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else { throw Failure.cannotRead }
        // The file's timeline starts where its first picture does.
        guard let first = videoOutput.copyNextSampleBuffer() else { throw Failure.cannotRead }
        let start = CMSampleBufferGetPresentationTimeStamp(first)
        guard writer.startWriting() else { throw Failure.cannotWrite }
        writer.startSession(atSourceTime: start)

        let queue = DispatchQueue(label: "rcamera.redevelop.video")
        let group = DispatchGroup()
        let grading = Grading(first: first)

        group.enter()
        videoInput.requestMediaDataWhenReady(on: queue) {
            while videoInput.isReadyForMoreMediaData {
                guard let sample = grading.next(from: videoOutput) else {
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                guard let source = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool else { continue }
                var target: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target)
                guard let target, grader.grade(
                    source: source,
                    crop: CropRect(x: 0, y: 0, width: width, height: height),
                    mirror: false,
                    look: look,
                    into: target
                ) else {
                    grading.failed = true
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                adaptor.append(target, withPresentationTime: time)
                if duration > 0 { progress(min(1, max(0, (time.seconds) / duration))) }
            }
        }

        if let audioOutput, let audioInput {
            group.enter()
            audioInput.requestMediaDataWhenReady(on: queue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), start) >= 0 {
                        audioInput.append(sample)
                    }
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: queue) {
                writer.finishWriting { continuation.resume() }
            }
        }

        if grading.failed { throw Failure.grading }
        guard reader.status != .failed else { throw Failure.cannotRead }
        guard writer.status == .completed else { throw Failure.cannotWrite }
        progress(1)
    }

    /// The reader's first picture is taken before writing starts, so it is handed out first.
    private final class Grading: @unchecked Sendable {
        private var pending: CMSampleBuffer?
        var failed = false

        init(first: CMSampleBuffer) {
            pending = first
        }

        func next(from output: AVAssetReaderTrackOutput) -> CMSampleBuffer? {
            if let pending {
                self.pending = nil
                return pending
            }
            return output.copyNextSampleBuffer()
        }
    }
}
