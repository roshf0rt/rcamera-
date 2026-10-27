import Foundation

/// Film speed as mood.camera offers it: how much grain, how coarse it is, how soft the image gets
/// and how much colour fringing appears at the edges. Each step sets the same four values.
/// The numbers come from mood.camera 2.4.0 (docs/research/mood-2.4.0/DATA_MODEL.md).
public enum FilmSpeed: String, CaseIterable, Codable, Sendable {
    case digi
    case iso100
    case iso200
    case iso400
    case iso800
    case iso1600
    case iso3200

    public var label: String {
        switch self {
        case .digi: "DIGI"
        case .iso100: "100"
        case .iso200: "200"
        case .iso400: "400"
        case .iso800: "800"
        case .iso1600: "1600"
        case .iso3200: "3200"
        }
    }

    /// Grain amount, 0...1. `LookAdjustments.grain` is the amount the preset actually uses.
    public var grain: Double {
        switch self {
        case .digi: 0
        case .iso100: 0.2
        case .iso200, .iso400: 0.3
        case .iso800, .iso1600: 0.5
        case .iso3200: 0.7
        }
    }

    /// Grain size, 1...4. Larger grain takes more pixels per speck.
    public var grainSize: Double {
        switch self {
        case .digi, .iso100: 1
        case .iso200: 2
        case .iso400, .iso800: 3
        case .iso1600, .iso3200: 4
        }
    }

    /// Sharpness, −0.3...0. Negative values soften the image.
    public var sharpness: Double {
        switch self {
        case .digi, .iso100, .iso200: 0
        case .iso400: -0.05
        case .iso800: -0.1
        case .iso1600: -0.2
        case .iso3200: -0.3
        }
    }

    /// Lateral colour fringing at the frame edges, 0...4.
    public var chromaticAberration: Double {
        switch self {
        case .digi, .iso100: 0
        case .iso200: 0.5
        case .iso400: 1
        case .iso800, .iso1600: 2
        case .iso3200: 4
        }
    }

    /// Writes this speed's values into a preset's grain and look. Each value stays editable afterwards.
    public func apply(grain: inout Double, to adjustments: inout LookAdjustments) {
        grain = self.grain
        adjustments.grainSize = grainSize
        adjustments.sharpness = sharpness
        adjustments.chromaticAberration = chromaticAberration
    }
}
