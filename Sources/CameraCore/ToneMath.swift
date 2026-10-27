import Foundation

/// CPU copy of the regulator maths in `App/Camera/Grade.metal`. The shader runs in the app; this copy
/// is tested here, so the formulas stay in range and neutral values stay an identity.
/// Order: exposure, white balance, shadows/midtones/highlights, contrast, fade, dynamic range,
/// saturation and mute, hue. The LUT comes after this.
///
/// Photos are graded in half float, so a developed RAW can arrive with highlights above 1. Dynamic range
/// decides what happens to them: HIGH (1) leaves the picture as it is and clips above white; EXT+ (1.5)
/// lifts the shadows and rolls everything above a knee, headroom included, softly under white, which is
/// the flat, wide "RAW" look; MED, LOW and ZERO bend an S-curve that crushes shadows and highlights.
public enum ToneMath {
    /// Same luma weights as the Lampa-style grader in the shader.
    static let luma = SIMD3<Double>(0.299, 0.587, 0.114)

    public static func regulate(_ color: SIMD3<Double>, _ look: LookAdjustments) -> SIMD3<Double> {
        var c = color * pow(2, look.postExposure)

        c.x += 0.06 * look.temp + 0.02 * look.tint
        c.y -= 0.04 * look.tint
        c.z += -0.06 * look.temp + 0.02 * look.tint

        c = SIMD3(tone(c.x, look), tone(c.y, look), tone(c.z, look))
        c = (c - 0.5) * look.contrast + 0.5
        c = c * (1 - 0.25 * look.fade) + 0.12 * look.fade
        let range = DynamicRangeCurve(look.dynamicRange)
        c = SIMD3(range.apply(c.x), range.apply(c.y), range.apply(c.z))

        let y = c.x * luma.x + c.y * luma.y + c.z * luma.z
        c = SIMD3(y, y, y) + (c - SIMD3(y, y, y)) * (look.saturation * (1 - 0.6 * look.mute))

        if look.hue != 0 {
            c = rotateHue(c, degrees: look.hue)
        }
        return SIMD3(clamp01(c.x), clamp01(c.y), clamp01(c.z))
    }

    /// Shadows lift towards the middle, highlights push away from it, midtones bend the middle.
    static func tone(_ x: Double, _ look: LookAdjustments) -> Double {
        let inverse = 1 - x
        let shadowWeight = inverse * inverse
        let midWeight = 4 * x * inverse
        let highlightWeight = x * x
        return x + 0.15 * (look.shadows * shadowWeight + look.midpoint * midWeight + look.highlights * highlightWeight)
    }

    /// Rotates chroma in YIQ space, which keeps luma unchanged.
    static func rotateHue(_ c: SIMD3<Double>, degrees: Double) -> SIMD3<Double> {
        let y = 0.299 * c.x + 0.587 * c.y + 0.114 * c.z
        let i = 0.596 * c.x - 0.274 * c.y - 0.322 * c.z
        let q = 0.211 * c.x - 0.523 * c.y + 0.312 * c.z
        let angle = degrees * Double.pi / 180
        let rotatedI = i * cos(angle) - q * sin(angle)
        let rotatedQ = i * sin(angle) + q * cos(angle)
        return SIMD3(
            y + 0.956 * rotatedI + 0.621 * rotatedQ,
            y - 0.272 * rotatedI - 0.647 * rotatedQ,
            y - 1.106 * rotatedI + 1.703 * rotatedQ
        )
    }

    static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// The dynamic-range regulator as three numbers the shader also reads. 1 is neutral.
public struct DynamicRangeCurve: Equatable, Sendable {
    /// Where the highlight roll-off starts; 1 means no roll-off.
    public var knee: Double
    /// How much the shadows are lifted, 0 for none.
    public var shadowLift: Double
    /// How far the tone bends towards an S-curve, 0 for none.
    public var crush: Double

    public init(_ dynamicRange: Double) {
        let wide = max(0, min(dynamicRange, 1.5) - 1) * 2
        let narrow = max(0, 1 - max(dynamicRange, 0))
        knee = 1 - 0.3 * wide
        shadowLift = 0.5 * wide
        crush = 0.6 * narrow
    }

    public func apply(_ x: Double) -> Double {
        var value = x
        let t = min(max(value, 0), 1)
        value += shadowLift * t * (1 - t) * (1 - t) * (1 - t)
        if knee < 1, value > knee {
            let span = 1 - knee
            value = knee + span * (1 - exp(-(value - knee) / span))
        }
        if crush > 0 {
            let u = min(max(value, 0), 1)
            value += crush * (u * u * (3 - 2 * u) - value)
        }
        return value
    }
}

/// The values the shader reads for one look, derived once on the CPU. The mapping lives here, next to
/// the tests, so the shader only ever sees final numbers.
public struct RegulatorUniforms: Equatable, Sendable {
    public var exposure: Double
    public var temp: Double
    public var tint: Double
    public var contrast: Double
    public var shadows: Double
    public var midpoint: Double
    public var highlights: Double
    public var fade: Double
    /// Roll-off knee, 1 when there is no roll-off.
    public var shoulderKnee: Double
    public var shadowLift: Double
    public var crush: Double
    /// Saturation with mute already folded in.
    public var saturation: Double
    public var hueCos: Double
    public var hueSin: Double
    public var hasHue: Bool
    public var filmStrength: Double
    public var bloom: Double
    public var sharpness: Double
    /// Edge colour fringing, in units the shader scales by frame position.
    public var fringe: Double
    /// Multiplier on the grain texture scale. 1 at grain size 1.
    public var grainSizeScale: Double

    public init(_ look: LookAdjustments) {
        exposure = pow(2, look.postExposure)
        temp = look.temp
        tint = look.tint
        contrast = look.contrast
        shadows = look.shadows
        midpoint = look.midpoint
        highlights = look.highlights
        fade = look.fade
        let range = DynamicRangeCurve(look.dynamicRange)
        shoulderKnee = range.knee
        shadowLift = range.shadowLift
        crush = range.crush
        saturation = look.saturation * (1 - 0.6 * look.mute)
        let angle = look.hue * Double.pi / 180
        hueCos = cos(angle)
        hueSin = sin(angle)
        hasHue = look.hue != 0
        filmStrength = look.filmStrength
        bloom = look.bloom
        sharpness = look.sharpness
        fringe = look.chromaticAberration
        grainSizeScale = 1 + 0.67 * (look.grainSize - 1)
    }
}
