import Foundation

/// The seven lens looks of mood.camera, for portrait photos. Each one sets vignetting, the glow of
/// highlights, the lateral colour fringing and the bokeh character. Parameters are from mood.camera 2.4.0
/// (docs/research/mood-2.4.0/DATA_MODEL.md). The app draws the portrait blur with Core Image's depth blur, so
/// the bokeh shape (blades, cat's eye, swirl) is approximated by the glow and vignetting only.
public enum LensStyle: String, CaseIterable, Codable, Sendable {
    case solis
    case lumar
    case trinity
    case helion
    case petzval
    case animor
    case hexon

    /// Short name on the camera's pill. Matches mood.camera's display names.
    public var label: String {
        switch self {
        case .solis: "SOLI"
        case .lumar: "LUMA"
        case .trinity: "TRIO"
        case .helion: "HELI"
        case .petzval: "PETZ"
        case .animor: "ANIM"
        case .hexon: "HEXA"
        }
    }

    /// Order in the picker, as in mood.camera.
    public var order: Int {
        switch self {
        case .solis: 0
        case .lumar: 1
        case .trinity: 2
        case .helion: 3
        case .petzval: 4
        case .animor: 6
        case .hexon: 7
        }
    }

    /// Edge darkening, 0...1.
    public var vignette: Double {
        switch self {
        case .solis: 0.10
        case .lumar: 0.12
        case .trinity: 0.35
        case .helion: 0.50
        case .petzval: 0.61
        case .animor: 0.09
        case .hexon: 0.22
        }
    }

    /// Glow of the bright points in the background, 0...1.
    public var ring: Double {
        switch self {
        case .solis: 0.05
        case .lumar: 0.0
        case .trinity: 0.91
        case .helion: 0.27
        case .petzval: 0.60
        case .animor: 0.20
        case .hexon: 0.03
        }
    }

    /// How far the highlight glow spreads, 0...1.
    public var highlightSpread: Double {
        switch self {
        case .solis: 0.05
        case .lumar: 0.30
        case .trinity: 0.20
        case .helion: 0.11
        case .petzval: 0.20
        case .animor: 0.20
        case .hexon: 0.30
        }
    }

    /// Lateral colour fringing, 0...1. `apply(to:)` turns it into the look's aberration.
    public var fringing: Double {
        switch self {
        case .solis: 0.15
        case .lumar: 0.60
        case .trinity: 0.50
        case .helion: 0.30
        case .petzval: 0.75
        case .animor: 0.80
        case .hexon: 0.30
        }
    }

    /// Writes this lens's fringing into a look, so the photo's own colour fringing follows the lens.
    public func apply(to adjustments: inout LookAdjustments) {
        adjustments.chromaticAberration = LookAdjustments.clamp(fringing * 2, 0, 4)
        adjustments.bloom = LookAdjustments.clamp(max(adjustments.bloom, highlightSpread), 0, 1)
    }

    /// The next lens in the picker's order, wrapping around.
    public var next: LensStyle {
        let all = LensStyle.allCases.sorted { $0.order < $1.order }
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
