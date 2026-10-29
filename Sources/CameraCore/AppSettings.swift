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

/// The GRAIN switch on the camera screen steps through these. The preset's grain is scaled by `multiplier`.
/// How strong a camera-screen effect is, as a share of the preset's own amount. Used by grain and halation.
public typealias EffectLevel = GrainLevel

public enum GrainLevel: String, CaseIterable, Codable, Sendable {
    case off
    case low
    case medium
    case high

    public var multiplier: Double {
        switch self {
        case .off: 0
        case .low: 0.5
        case .medium: 1
        case .high: 1.7
        }
    }

    public var label: String {
        switch self {
        case .off: "OFF"
        case .low: "LOW"
        case .medium: "MED"
        case .high: "HIGH"
        }
    }

    public var next: GrainLevel {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Which RAW the camera keeps. ProRAW is Apple's merged, tone-mapped DNG; Bayer is the single sensor frame,
/// flatter and noisier, closer to a classic camera RAW.
public enum RAWFormat: String, CaseIterable, Codable, Sendable {
    case proRAW
    case bayer

    public var label: String {
        switch self {
        case .proRAW: "ProRAW"
        case .bayer: "Bayer RAW"
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
    /// Photos are developed from this RAW when one is captured (flash off, not portrait).
    public var rawFormat: RAWFormat = .proRAW
    public var savesLocation = true
    public var digitalZoomStop: DigitalZoomStop = .none
    /// Quick toggles on the camera screen. The amounts come from the selected preset.
    public var grainLevel: GrainLevel = .medium
    /// Grain on at any level. Setting it on restores the preset's own amount.
    public var grainEnabled: Bool {
        get { grainLevel != .off }
        set { grainLevel = newValue ? (grainLevel == .off ? .medium : grainLevel) : .off }
    }
    public var halationLevel: EffectLevel = .medium
    /// Halation on at any level.
    public var halationEnabled: Bool {
        get { halationLevel != .off }
        set { halationLevel = newValue ? (halationLevel == .off ? .medium : halationLevel) : .off }
    }
    /// Photo border with the preset name. Off by default.
    public var frame: FrameStyle = .off
    /// Volume buttons take a photo while the camera is on screen. Off by default.
    public var volumeShutter = false
    /// Portrait photos: blur the background from the depth map. Photo mode only.
    public var portrait = false
    /// The f-number the portrait blur is set to.
    public var portraitFNumber = PortraitAperture.standard
    /// The lens look applied to portrait photos.
    public var lensStyle: LensStyle = .solis
    /// The photo size. 12 MP by default.
    public var photoResolution: PhotoResolution = .mp12

    public var videoResolution: VideoResolution = .hd1080
    public var videoFPS = 30
    public var videoStabilization: VideoStabilization = .standard
    public var appleLogVideo = true
    /// With Apple Log on: the look goes into the recording as it is shot. Off, the Log frames are recorded flat,
    /// the Log file is saved to Photos, and the preset is applied later in the gallery's Redevelop.
    public var instantGrade = true
    /// Video only: exposure held on the 180° shutter with ISO doing the work, handing over to the camera's
    /// own auto exposure when the light is out of reach (see `MotionExposure`). On by default.
    public var autoMotion = true

    // Pro tools, under PRO in the options shade. Drawn on the viewfinder only.
    public var zebra = false
    public var focusPeaking = false
    public var falseColor = false
    public var waveform = false
    /// Video: exposure and white balance stay as they were when recording started.
    public var lockExposureWhileRecording = false
    public var lockWhiteBalanceWhileRecording = false
    /// White balance held at this colour temperature; nil lets the camera pick it.
    public var whiteBalanceKelvin: Int?
    /// Green (negative) to magenta (positive), with a fixed colour temperature.
    public var whiteBalanceTint = 0
    /// Bumped when defaults change; older files adopt the new defaults once.
    public var revision = AppSettings.currentRevision

    public static let currentRevision = 2

    public init() {}

    public var videoFormat: VideoFormat {
        let size = videoResolution.size
        return VideoFormat(width: size.width, height: size.height, fps: videoFPS)
    }

    enum CodingKeys: String, CodingKey {
        case selectedPresetID, lastCaptureMode, aspect, flash, timer
        case isGridEnabled, isLevelEnabled, mirrorFrontCamera, capturesRAW, rawFormat, savesLocation, digitalZoomStop
        case grainLevel, halationLevel, frame, volumeShutter, portrait, portraitFNumber, lensStyle, photoResolution
        case videoResolution, videoFPS, videoStabilization, appleLogVideo, instantGrade, autoMotion, revision
        case zebra, focusPeaking, falseColor, waveform, lockExposureWhileRecording, lockWhiteBalanceWhileRecording
        case whiteBalanceKelvin, whiteBalanceTint
    }

    /// Keys older settings files used.
    enum LegacyKeys: String, CodingKey {
        case grainEnabled, halationEnabled
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
        rawFormat = (try? c.decode(RAWFormat.self, forKey: .rawFormat)) ?? rawFormat
        savesLocation = (try? c.decode(Bool.self, forKey: .savesLocation)) ?? savesLocation
        digitalZoomStop = (try? c.decode(DigitalZoomStop.self, forKey: .digitalZoomStop)) ?? digitalZoomStop
        if let level = try? c.decode(GrainLevel.self, forKey: .grainLevel) {
            grainLevel = level
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self).decode(Bool.self, forKey: .grainEnabled) {
            grainLevel = legacy ? .medium : .off
        }
        if let level = try? c.decode(EffectLevel.self, forKey: .halationLevel) {
            halationLevel = level
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self).decode(Bool.self, forKey: .halationEnabled) {
            halationLevel = legacy ? .medium : .off
        }
        frame = (try? c.decode(FrameStyle.self, forKey: .frame)) ?? frame
        volumeShutter = (try? c.decode(Bool.self, forKey: .volumeShutter)) ?? volumeShutter
        portrait = (try? c.decode(Bool.self, forKey: .portrait)) ?? portrait
        portraitFNumber = PortraitAperture.nearest(to: (try? c.decode(Double.self, forKey: .portraitFNumber)) ?? portraitFNumber)
        lensStyle = (try? c.decode(LensStyle.self, forKey: .lensStyle)) ?? lensStyle
        // 48 MP was taken out of the camera screen; a stored choice falls back to 12 MP.
        photoResolution = .mp12
        videoResolution = (try? c.decode(VideoResolution.self, forKey: .videoResolution)) ?? videoResolution
        videoFPS = (try? c.decode(Int.self, forKey: .videoFPS)) ?? videoFPS
        appleLogVideo = (try? c.decode(Bool.self, forKey: .appleLogVideo)) ?? appleLogVideo
        instantGrade = (try? c.decode(Bool.self, forKey: .instantGrade)) ?? instantGrade
        // The earlier cine exposure switch is not carried over: AutoMotion replaces it and starts on.
        autoMotion = (try? c.decode(Bool.self, forKey: .autoMotion)) ?? autoMotion
        zebra = (try? c.decode(Bool.self, forKey: .zebra)) ?? zebra
        focusPeaking = (try? c.decode(Bool.self, forKey: .focusPeaking)) ?? focusPeaking
        falseColor = (try? c.decode(Bool.self, forKey: .falseColor)) ?? falseColor
        waveform = (try? c.decode(Bool.self, forKey: .waveform)) ?? waveform
        lockExposureWhileRecording = (try? c.decode(Bool.self, forKey: .lockExposureWhileRecording)) ?? lockExposureWhileRecording
        lockWhiteBalanceWhileRecording = (try? c.decode(Bool.self, forKey: .lockWhiteBalanceWhileRecording)) ?? lockWhiteBalanceWhileRecording
        whiteBalanceKelvin = (try? c.decode(Int?.self, forKey: .whiteBalanceKelvin)) ?? nil
        whiteBalanceTint = (try? c.decode(Int.self, forKey: .whiteBalanceTint)) ?? whiteBalanceTint
        revision = (try? c.decode(Int.self, forKey: .revision)) ?? 0
        if let stabilization = try? c.decode(VideoStabilization.self, forKey: .videoStabilization) {
            videoStabilization = stabilization
        } else if let legacy = try? c.decode(Bool.self, forKey: .videoStabilization) {
            videoStabilization = legacy ? .standard : .off
        }
        if revision < 2 {
            // Apple Log became the default for video in revision 2.
            appleLogVideo = true
        }
        revision = Self.currentRevision
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
