import Foundation

/// What the app needs to know about one `AVCaptureDevice.Format`, without AVFoundation, so the choice
/// can be tested anywhere.
public struct FormatDescriptor: Equatable, Sendable {
    /// Position in `device.formats`.
    public var index: Int
    /// Landscape stream size.
    public var width: Int
    public var height: Int
    public var maxFPS: Double
    public var supportsAppleLog: Bool
    /// 8-bit 4:2:0 full range ('420f'), the usual SDR stream.
    public var isFullRange8Bit: Bool
    /// Pixel count of the largest photo the format can take.
    public var maxPhotoPixels: Int

    public init(index: Int, width: Int, height: Int, maxFPS: Double, supportsAppleLog: Bool = false, isFullRange8Bit: Bool = true, maxPhotoPixels: Int = 0) {
        self.index = index
        self.width = width
        self.height = height
        self.maxFPS = maxFPS
        self.supportsAppleLog = supportsAppleLog
        self.isFullRange8Bit = isFullRange8Bit
        self.maxPhotoPixels = maxPhotoPixels
    }

    var isFourByThree: Bool { abs(width * 3 - height * 4) <= 8 }
    var isSixteenByNine: Bool { abs(width * 9 - height * 16) <= 16 }
}

public struct VideoFormatChoice: Equatable, Sendable {
    public var format: FormatDescriptor
    /// The photo format serves video too: switching modes needs no reconfiguration, video is cropped to 16:9.
    public var sharedWithPhoto: Bool
    public var appleLog: Bool
}

/// Picks device formats the way Lampa's capture graph does: a 4:3 stream around 1920 wide for photos,
/// which also serves 1080p SDR video (cropped to 16:9), so switching photo and video costs nothing.
/// Only 4K, frame rates the photo format lacks, and Apple Log need their own 16:9 format.
public enum FormatChooser {
    /// About 12 MP. Bigger photos are slow to capture and process, so they are not preferred.
    public static let preferredPhotoPixels = 12_200_000

    public static func photoFormat(_ formats: [FormatDescriptor]) -> FormatDescriptor? {
        let candidates = formats.filter { $0.isFourByThree && (1440 ... 2112).contains($0.width) && $0.maxFPS >= 30 }
        return candidates.max { photoScore($0).lexicographicallyPrecedes(photoScore($1)) }
    }

    private static func photoScore(_ format: FormatDescriptor) -> [Int] {
        [
            format.width == 1920 ? 1 : 0,
            min(format.maxPhotoPixels, preferredPhotoPixels),
            format.isFullRange8Bit ? 1 : 0,
            Int(format.maxFPS),
            -format.index,
        ]
    }

    public static func videoFormat(
        _ formats: [FormatDescriptor],
        width: Int,
        fps: Int,
        appleLog: Bool,
        photo: FormatDescriptor?
    ) -> VideoFormatChoice? {
        if appleLog, let log = sixteenByNine(formats, width: width, fps: fps, appleLog: true) {
            return VideoFormatChoice(format: log, sharedWithPhoto: false, appleLog: true)
        }
        if width <= 1920, let photo, photo.width >= 1920, photo.maxFPS >= Double(fps) {
            return VideoFormatChoice(format: photo, sharedWithPhoto: true, appleLog: false)
        }
        if let format = sixteenByNine(formats, width: width, fps: fps, appleLog: false) {
            return VideoFormatChoice(format: format, sharedWithPhoto: false, appleLog: false)
        }
        return nil
    }

    /// Above this many frames per second the back camera runs alone, without the multi-camera device.
    public static let highFrameRate = 60

    /// The next lighter video format when the camera says a configuration is over its hardware budget
    /// (`AVCaptureSession.hardwareCost` above 1), as Kino falls back: the frame rate steps down to 60, then
    /// 30, and only then 4K drops to 1080p. Nil when there is nothing lighter to try.
    public static func lighter(than format: VideoFormat) -> VideoFormat? {
        if format.fps > 60 { return VideoFormat(width: format.width, height: format.height, fps: 60) }
        if format.fps > 30 { return VideoFormat(width: format.width, height: format.height, fps: 30) }
        if format.width > 1920 { return VideoFormat(width: 1920, height: 1080, fps: format.fps) }
        return nil
    }

    /// Frame rates offered for a video width: the standard ones some 16:9 format (or, for 1080p, the
    /// photo format) can run. 120 and 240 show up only on cameras that have them (4K120 on recent Pro
    /// iPhones, 1080p240 on most).
    public static func frameRates(_ formats: [FormatDescriptor], width: Int, candidates: [Int] = [24, 30, 60, 120, 240]) -> [Int] {
        let photo = photoFormat(formats)
        return candidates.filter { fps in
            if width <= 1920, let photo, photo.width >= 1920, photo.maxFPS >= Double(fps) { return true }
            return formats.contains { $0.isSixteenByNine && $0.width == width && $0.maxFPS >= Double(fps) }
        }
    }

    private static func sixteenByNine(_ formats: [FormatDescriptor], width: Int, fps: Int, appleLog: Bool) -> FormatDescriptor? {
        let candidates = formats.filter {
            $0.isSixteenByNine && $0.width == width && $0.maxFPS >= Double(fps) && (!appleLog || $0.supportsAppleLog)
        }
        return candidates.max { videoScore($0, appleLog: appleLog).lexicographicallyPrecedes(videoScore($1, appleLog: appleLog)) }
    }

    private static func videoScore(_ format: FormatDescriptor, appleLog: Bool) -> [Int] {
        [
            appleLog || format.isFullRange8Bit ? 1 : 0,
            // Formats built for high frame rates are often binned, so prefer the lowest one that suffices.
            -Int(format.maxFPS),
            -format.index,
        ]
    }
}
