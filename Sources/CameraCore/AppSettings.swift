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

public enum VideoStabilization: String, CaseIterable, Codable, Sendable {
    case off
    /// Light correction with little delay in the viewfinder.
    case standard
    /// Strongest correction. The camera buffers frames, so the viewfinder lags a little.
    case cinematic

    public var label: String {
        switch self {
        case .off: "OFF"
        case .standard: "STANDARD"
        case .cinematic: "CINEMATIC"
        }
    }

    public var next: VideoStabilization {
        let all = VideoStabilization.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// An optional crop-based stop shown next to the real lenses.
public enum DigitalZoomStop: String, CaseIterable, Codable, Sendable {
    case none
    case x1_5
    case x2

    public var factor: Double? {
        switch self {
        case .none: nil
        case .x1_5: 1.5
        case .x2: 2.0
        }
    }

    public var label: String {
        switch self {
        case .none: "Off"
        case .x1_5: "1.5×"
        case .x2: "2×"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedPresetID = "preset-1"
    public var lastCaptureMode: CaptureMode = .photo
    public var aspect: AspectOption = .ratio4x3
    public var flash: FlashMode = .off
    public var timer: TimerOption = .off

    public var isGridEnabled = true
    public var isLevelEnabled = false
    public var mirrorFrontCamera = true
    public var capturesRAW = true
    public var savesLocation = true
    public var digitalZoomStop: DigitalZoomStop = .none

    public var videoResolution: VideoResolution = .hd1080
    public var videoFPS = 30
    public var videoStabilization: VideoStabilization = .standard
    public var appleLogVideo = false

    public init() {}

    public var videoFormat: VideoFormat {
        let size = videoResolution.size
        return VideoFormat(width: size.width, height: size.height, fps: videoFPS)
    }

    enum CodingKeys: String, CodingKey {
        case selectedPresetID, lastCaptureMode, aspect, flash, timer
        case isGridEnabled, isLevelEnabled, mirrorFrontCamera, capturesRAW, savesLocation, digitalZoomStop
        case videoResolution, videoFPS, videoStabilization, appleLogVideo
    }

    /// Missing or unreadable keys keep their defaults, so older settings files keep working.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedPresetID = (try? c.decode(String.self, forKey: .selectedPresetID)) ?? selectedPresetID
        lastCaptureMode = (try? c.decode(CaptureMode.self, forKey: .lastCaptureMode)) ?? lastCaptureMode
        aspect = (try? c.decode(AspectOption.self, forKey: .aspect)) ?? aspect
        flash = (try? c.decode(FlashMode.self, forKey: .flash)) ?? flash
        timer = (try? c.decode(TimerOption.self, forKey: .timer)) ?? timer
        isGridEnabled = (try? c.decode(Bool.self, forKey: .isGridEnabled)) ?? isGridEnabled
        isLevelEnabled = (try? c.decode(Bool.self, forKey: .isLevelEnabled)) ?? isLevelEnabled
        mirrorFrontCamera = (try? c.decode(Bool.self, forKey: .mirrorFrontCamera)) ?? mirrorFrontCamera
        capturesRAW = (try? c.decode(Bool.self, forKey: .capturesRAW)) ?? capturesRAW
        savesLocation = (try? c.decode(Bool.self, forKey: .savesLocation)) ?? savesLocation
        digitalZoomStop = (try? c.decode(DigitalZoomStop.self, forKey: .digitalZoomStop)) ?? digitalZoomStop
        videoResolution = (try? c.decode(VideoResolution.self, forKey: .videoResolution)) ?? videoResolution
        videoFPS = (try? c.decode(Int.self, forKey: .videoFPS)) ?? videoFPS
        appleLogVideo = (try? c.decode(Bool.self, forKey: .appleLogVideo)) ?? appleLogVideo
        if let stabilization = try? c.decode(VideoStabilization.self, forKey: .videoStabilization) {
            videoStabilization = stabilization
        } else if let legacy = try? c.decode(Bool.self, forKey: .videoStabilization) {
            videoStabilization = legacy ? .standard : .off
        }
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
