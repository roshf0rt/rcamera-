import AVFoundation
import CameraCore
import CoreImage
import CoreVideo
import ImageIO

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
    /// How the clip asks to be shown (its track's transform): a custom compositor gets the frames as they were
    /// written, so a clip filmed with the phone held sideways has to be turned here.
    let orientation: CGImagePropertyOrientation

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, look: FilmLook, orientation: CGImagePropertyOrientation) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.look = look
        self.orientation = orientation
    }
}

/// Hands the player every Log frame already graded, so the clip plays the way Render will write it. It is
/// the grader the viewfinder and the photos use, on its own queue for this player.
final class LogGradeCompositor: NSObject, AVVideoCompositing {
    private let queue = DispatchQueue(label: "rcamera.log-grade.player")
    private var grader: MetalGrader?
    /// Turns graded frames to the way the clip is shown, when it is not shown as written.
    private let turner = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private var scratchPool: CVPixelBufferPool?
    private var scratchSize = (width: 0, height: 0)

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
            let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
            let crop = CropRect(x: 0, y: 0, width: width, height: height)
            guard let grader = self.grader else {
                request.finish(with: LogGradePreviewError.grading)
                return
            }
            if instruction.orientation == .up {
                guard grader.grade(source: source, crop: crop, mirror: false, look: instruction.look, into: target) else {
                    request.finish(with: LogGradePreviewError.grading)
                    return
                }
                request.finish(withComposedVideoFrame: target)
                return
            }
            // Grade the frame as written, then turn it into the buffer the player shows.
            guard let scratch = self.scratchBuffer(width: width, height: height),
                  grader.grade(source: source, crop: crop, mirror: false, look: instruction.look, into: scratch)
            else {
                request.finish(with: LogGradePreviewError.grading)
                return
            }
            var turned = CIImage(cvPixelBuffer: scratch, options: [.colorSpace: NSNull()]).oriented(instruction.orientation)
            turned = turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX, y: -turned.extent.minY))
            let bounds = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(target), height: CVPixelBufferGetHeight(target))
            self.turner.render(turned, to: target, bounds: bounds, colorSpace: nil)
            request.finish(withComposedVideoFrame: target)
        }
    }

    /// A reusable buffer the size of the clip's own frames, for grading before the turn.
    private func scratchBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if scratchPool == nil || scratchSize != (width, height) {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            scratchPool = pool
            scratchSize = (width, height)
        }
        guard let scratchPool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, scratchPool, &buffer)
        return buffer
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

enum LogGradePreview {
    /// The turn a track's transform stands for. The recorder writes portrait frames and a quarter turn for a phone
    /// held sideways, so that is what turns up.
    static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (Int(transform.a.rounded()), Int(transform.b.rounded()), Int(transform.c.rounded()), Int(transform.d.rounded())) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }

    /// A player item for the clip, graded with `look` frame by frame.
    static func playerItem(url: URL, look: FilmLook) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw LogGradePreviewError.noVideo }
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let rate = try await track.load(.nominalFrameRate)
        let turn = Self.orientation(of: try await track.load(.preferredTransform))

        let instruction = LogGradeInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            trackID: track.trackID,
            look: look,
            orientation: turn
        )
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = LogGradeCompositor.self
        // A quarter turn swaps the sides: the player shows the clip as it will be seen.
        composition.renderSize = turn == .left || turn == .right ? CGSize(width: size.height, height: size.width) : size
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(rate, 1).rounded()))
        composition.instructions = [instruction]

        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        return item
    }
}
