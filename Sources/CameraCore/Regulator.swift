import Foundation

/// One manual regulator in `LookAdjustments`, with its range and the title the editor shows.
/// The list drives the editor, so every regulator in the model has exactly one row.
public enum Regulator: String, CaseIterable, Sendable {
    case postExposure
    case contrast
    case dynamicRange
    case saturation
    case temp
    case tint
    case hue
    case highlights
    case midpoint
    case shadows
    case fade
    case mute
    case filmStrength
    case grainSize
    case sharpness
    case chromaticAberration
    case bloom

    public var title: String {
        switch self {
        case .postExposure: "Brightness"
        case .contrast: "Contrast"
        case .dynamicRange: "Dynamic range"
        case .saturation: "Saturation"
        case .temp: "Temperature"
        case .tint: "Tint"
        case .hue: "Hue"
        case .highlights: "Highlights"
        case .midpoint: "Midtones"
        case .shadows: "Shadows"
        case .fade: "Fade"
        case .mute: "Mute"
        case .filmStrength: "Film strength"
        case .grainSize: "Grain size"
        case .sharpness: "Sharpness"
        case .chromaticAberration: "Fringing"
        case .bloom: "Bloom"
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .postExposure: -1 ... 1
        case .contrast: 0.5 ... 1.5
        case .dynamicRange: 0 ... 1.5
        case .saturation: 0 ... 2
        case .temp, .tint, .highlights, .midpoint, .shadows: -1 ... 1
        case .hue: -30 ... 30
        case .fade, .mute, .filmStrength, .bloom: 0 ... 1
        case .grainSize: 1 ... 4
        case .sharpness: -0.5 ... 0.5
        case .chromaticAberration: 0 ... 4
        }
    }

    public var keyPath: WritableKeyPath<LookAdjustments, Double> {
        switch self {
        case .postExposure: \.postExposure
        case .contrast: \.contrast
        case .dynamicRange: \.dynamicRange
        case .saturation: \.saturation
        case .temp: \.temp
        case .tint: \.tint
        case .hue: \.hue
        case .highlights: \.highlights
        case .midpoint: \.midpoint
        case .shadows: \.shadows
        case .fade: \.fade
        case .mute: \.mute
        case .filmStrength: \.filmStrength
        case .grainSize: \.grainSize
        case .sharpness: \.sharpness
        case .chromaticAberration: \.chromaticAberration
        case .bloom: \.bloom
        }
    }

    /// The value a regulator has when nothing is changed.
    public var neutral: Double {
        LookAdjustments.neutral[keyPath: keyPath]
    }

    /// Text for the value next to the slider.
    public func format(_ value: Double) -> String {
        switch self {
        case .contrast, .saturation, .filmStrength, .dynamicRange:
            String(format: "%.2f×", value)
        case .postExposure:
            String(format: "%+.2f EV", value)
        case .grainSize:
            String(format: "%.0f", value)
        case .hue:
            String(format: "%+.0f°", value)
        case .chromaticAberration:
            String(format: "%.1f", value)
        default:
            String(format: "%+.2f", value)
        }
    }
}
