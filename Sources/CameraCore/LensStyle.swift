import Foundation

/// The seven lens looks of mood.camera, for portrait photos. Each one sets vignetting, the glow of
/// highlights, the lateral colour fringing and the bokeh character. Parameters are from mood.camera 2.4.0
/// (docs/research/mood-2.4.0/DATA_MODEL.md). `LensKernel` turns the bokeh parameters (blades, rim, cat's eye,
/// ovality, swirl) into the sample pattern of the portrait blur, so each lens blurs in its own shape.
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

    /// One line about the bokeh, for the lens picker.
    public var summary: String {
        switch self {
        case .solis: "Clean, round, modern"
        case .lumar: "Soft, dreamy, no edges"
        case .trinity: "Soap bubbles with bright rims"
        case .helion: "Round with edge swirl"
        case .petzval: "Heavy swirl and fringing"
        case .animor: "Tall anamorphic ovals"
        case .hexon: "Six-bladed hexagons"
        }
    }

    /// Aperture blades, 0 for a round opening.
    public var bladeCount: Int {
        self == .hexon ? 6 : 0
    }

    /// How much the bokeh is clipped into a cat's eye towards the frame edges, 0...1.
    public var catsEye: Double {
        switch self {
        case .solis: 0.30
        case .lumar: 0.20
        case .trinity: 0.30
        case .helion: 0.69
        case .petzval: 0.79
        case .animor: 0.70
        case .hexon: 0.16
        }
    }

    /// Stretch of the bokeh: positive is taller, negative wider.
    public var ovality: Double {
        switch self {
        case .lumar: 0.07
        case .petzval: -0.2
        case .animor: 1.0
        default: 0
        }
    }

    /// Bokeh rim: positive is a bright ring with a hollow centre, negative a soft edge.
    public var rim: Double {
        switch self {
        case .solis: 0.05
        case .lumar: -0.95
        case .trinity: 0.91
        case .helion: 0.27
        case .petzval: 0.60
        case .animor: 0.20
        case .hexon: 0.03
        }
    }

    /// Width of that rim, 0...1 of the radius.
    public var rimWidth: Double {
        switch self {
        case .solis: 0.55
        case .lumar: 0.90
        case .trinity: 0.16
        case .helion: 0.24
        case .petzval: 0.57
        case .animor: 0.20
        case .hexon: 0.45
        }
    }

    /// Swirl of the background around the centre, 0...1.
    public var swirl: Double {
        switch self {
        case .solis: 0
        case .lumar: 0.15
        case .trinity: 0.06
        case .helion: 0.77
        case .petzval: 1.0
        case .animor: 0
        case .hexon: 0.06
        }
    }

    /// How much the bright points swell into bokeh balls: more for ringed lenses and for glowing ones.
    public var highlightBoost: Double {
        0.25 + 0.6 * max(0, rim) + 0.5 * highlightSpread
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
