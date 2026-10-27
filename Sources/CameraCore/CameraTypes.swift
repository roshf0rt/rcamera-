public enum CaptureMode: Equatable, Sendable {
    case photo
    case video
}

public enum LensID: Hashable, Sendable {
    case wide
    case ultraWide
    case telephoto
    case front
}

public struct VideoFormat: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var fps: Int

    public init(width: Int, height: Int, fps: Int) {
        self.width = width
        self.height = height
        self.fps = fps
    }

    public static let hd1080p30 = VideoFormat(width: 1920, height: 1080, fps: 30)
}

/// Settings that survive phase changes. The phase says what the session is doing;
/// the configuration says what it is set to.
public struct CameraConfiguration: Equatable, Sendable {
    public var mode: CaptureMode
    public var format: VideoFormat
    public var lens: LensID

    public init(mode: CaptureMode, format: VideoFormat, lens: LensID) {
        self.mode = mode
        self.format = format
        self.lens = lens
    }
}
