import Foundation

/// The tonal settings one contrast curve writes into a look. Ranges match `LookAdjustments`.
public struct ToneSettings: Equatable, Sendable {
    public var contrast: Double
    public var postExposure: Double
    public var shadows: Double
    public var midpoint: Double
    public var highlights: Double
    public var fade: Double
    public var mute: Double
    public var saturation: Double
    public var filmStrength: Double
}

/// The ten contrast curves of mood.camera. A curve is a set of tonal settings applied on top of the
/// emulation; the user can still move each regulator afterwards.
/// Values are from mood.camera 2.4.0 (docs/research/mood-2.4.0/DATA_MODEL.md).
public enum ContrastCurve: String, CaseIterable, Codable, Sendable {
    case neutral
    case softer
    case refined
    case pro
    case dynamic
    case bright
    case faded
    case ultra
    case crush
    case expired

    public var label: String {
        switch self {
        case .neutral: "Neutral"
        case .softer: "Softer"
        case .refined: "Refined"
        case .pro: "Pro"
        case .dynamic: "Dynamic"
        case .bright: "Bright"
        case .faded: "Faded"
        case .ultra: "Ultra"
        case .crush: "Crush"
        case .expired: "Expired"
        }
    }

    public var settings: ToneSettings {
        switch self {
        case .neutral:
            ToneSettings(contrast: 1, postExposure: 0, shadows: 0, midpoint: -0.05, highlights: 0, fade: 0.03, mute: 0.03, saturation: 1, filmStrength: 1)
        case .softer:
            ToneSettings(contrast: 1, postExposure: 0, shadows: 0, midpoint: 0, highlights: 0, fade: 0.08, mute: 0.08, saturation: 1.15, filmStrength: 1)
        case .refined:
            ToneSettings(contrast: 1, postExposure: -0.1, shadows: 0, midpoint: 0, highlights: 0, fade: 0.03, mute: 0.03, saturation: 1.075, filmStrength: 0.66)
        case .pro:
            ToneSettings(contrast: 1.1, postExposure: -0.05, shadows: 0, midpoint: 0, highlights: -0.1, fade: 0, mute: 0, saturation: 1.15, filmStrength: 0.66)
        case .dynamic:
            ToneSettings(contrast: 1.1, postExposure: 0.05, shadows: 0, midpoint: 0, highlights: -0.05, fade: 0.03, mute: 0.03, saturation: 1, filmStrength: 1)
        case .bright:
            ToneSettings(contrast: 0.85, postExposure: 0.3, shadows: -0.05, midpoint: -0.05, highlights: -0.15, fade: 0.015, mute: 0.015, saturation: 1.075, filmStrength: 1)
        case .faded:
            ToneSettings(contrast: 1.1, postExposure: 0, shadows: 0, midpoint: -0.05, highlights: 0, fade: 0.15, mute: 0.15, saturation: 0.85, filmStrength: 1)
        case .ultra:
            ToneSettings(contrast: 1.2, postExposure: 0, shadows: 0, midpoint: -0.05, highlights: -0.05, fade: 0.06, mute: 0.06, saturation: 1.075, filmStrength: 1)
        case .crush:
            ToneSettings(contrast: 1.3, postExposure: -0.1, shadows: -0.05, midpoint: 0.05, highlights: 0, fade: 0, mute: 0, saturation: 1, filmStrength: 1)
        case .expired:
            ToneSettings(contrast: 0.9, postExposure: -0.05, shadows: 0, midpoint: 0, highlights: -0.05, fade: 0.23, mute: 0.08, saturation: 0.85, filmStrength: 1)
        }
    }

    /// Writes this curve's tonal settings into a look. Speed and sharpness are left alone.
    public func apply(to adjustments: inout LookAdjustments) {
        let tone = settings
        adjustments.contrast = tone.contrast
        adjustments.postExposure = tone.postExposure
        adjustments.shadows = tone.shadows
        adjustments.midpoint = tone.midpoint
        adjustments.highlights = tone.highlights
        adjustments.fade = tone.fade
        adjustments.mute = tone.mute
        adjustments.saturation = tone.saturation
        adjustments.filmStrength = tone.filmStrength
        adjustments.curve = self
    }
}
