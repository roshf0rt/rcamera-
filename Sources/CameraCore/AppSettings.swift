import Foundation

public enum VideoResolution: String, CaseIterable, Codable, Sendable {
    case hd1080
    case uhd4K

    public var label: String {
        switch self {
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }

    public var size: (width: Int, height: Int) {
        switch self {
        case .hd1080: (1920, 1080)
        case .uhd4K: (3840, 2160)
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedPresetID: String = "preset-1"
    public var lastCaptureMode: CaptureMode = .photo
    public var aspect: AspectOption = .ratio4x3
    public var flash: FlashMode = .off
    public var timer: TimerOption = .off

    public var isGridEnabled = true
    public var isLevelEnabled = false
    public var mirrorFrontCamera = true
    public var capturesRAW = true
    public var savesLocation = true

    public var videoResolution: VideoResolution = .hd1080
    public var videoFPS = 30
    public var videoStabilization = true

    public init() {}

    public var videoFormat: VideoFormat {
        let size = videoResolution.size
        return VideoFormat(width: size.width, height: size.height, fps: videoFPS)
    }
}

public final class SettingsStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: url, options: .atomic)
    }
}
