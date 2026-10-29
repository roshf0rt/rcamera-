import AVFoundation
import CameraCore
import CoreVideo

enum LogGradePreviewError: Error {
    case noVideo
    case noFrame
    case grading
}

/// The look a clip plays with, as an instruction the compositor reads.
final class LogGradeInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let look: FilmLook

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, look: FilmLook) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.look = look
    }
}

/// Hands the player every Log frame already graded, so the clip plays the way Render will write it. It is
/// the grader the viewfinder and the photos use, on its own queue for this player.
final class LogGradeCompositor: NSObject, AVVideoCompositing {
    private let queue = DispatchQueue(label: "rcamera.log-grade.player")
    private var grader: MetalGrader?

    var sourcePixelBufferAttributes: [String: Any]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? LogGradeInstruction,
              let trackID = instruction.requiredSourceTrackIDs?.first as? NSNumber,
              let source = request.sourceFrame(byTrackID: trackID.int32Value),
              let target = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: LogGradePreviewError.noFrame)
            return
        }
        queue.async {
            if self.grader == nil { self.grader = MetalGrader.makeForBackground() }
            let crop = CropRect(x: 0, y: 0, width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source))
            guard let grader = self.grader,
                  grader.grade(source: source, crop: crop, mirror: false, look: instruction.look, into: target)
            else {
                request.finish(with: LogGradePreviewError.grading)
                return
            }
            request.finish(withComposedVideoFrame: target)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

enum LogGradePreview {
    /// A player item for the clip, graded with `look` frame by frame.
    static func playerItem(url: URL, look: FilmLook) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw LogGradePreviewError.noVideo }
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let rate = try await track.load(.nominalFrameRate)

        let instruction = LogGradeInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            trackID: track.trackID,
            look: look
        )
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = LogGradeCompositor.self
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(rate, 1).rounded()))
        composition.instructions = [instruction]

        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        return item
    }
}
