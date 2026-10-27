import Foundation

/// Manual regulators on top of a preset's LUT: exposure, white balance, tone, colour, fade and the
/// film-speed values that set grain size, sharpness and colour fringing. Neutral values change nothing.
/// The regulators follow mood.camera 2.4.0 (docs/research/mood-2.4.0/DATA_MODEL.md).
public struct LookAdjustments: Codable, Equatable, Sendable {
    /// Exposure after the tone curve, in stops.
    public var postExposure: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    /// Blue (−) to amber (+).
    public var temp: Double = 0
    /// Green (−) to magenta (+).
    public var tint: Double = 0
    /// Hue rotation in degrees.
    public var hue: Double = 0
    /// Shadows, midtones and highlights, −1...1.
    public var shadows: Double = 0
    public var midpoint: Double = 0
    public var highlights: Double = 0
    /// Lifts blacks towards grey.
    public var fade: Double = 0
    /// Pulls colours towards grey.
    public var mute: Double = 0
    /// How much of the emulation shows over the original image.
    public var filmStrength: Double = 1
    /// Above 1 keeps highlights open, below 1 rolls them off earlier.
    public var dynamicRange: Double = 1
    /// Grain size, 1...4.
    public var grainSize: Double = 1
    /// Negative softens, positive sharpens.
    public var sharpness: Double = 0
    /// Colour fringing at the frame edges, 0...4.
    public var chromaticAberration: Double = 0
    /// Glow around bright areas, 0...1.
    public var bloom: Double = 0
    /// The contrast curve last applied, if any. Only used to show its name.
    public var curve: ContrastCurve?

    public init() {}

    public static let neutral = LookAdjustments()

    /// True when every regulator is at its neutral value.
    public var isNeutral: Bool { self == .neutral }

    /// Pulls every value into its range. Used after editing and after decoding.
    public mutating func clamp() {
        postExposure = Self.clamp(postExposure, -1, 1)
        contrast = Self.clamp(contrast, 0.5, 1.5)
        saturation = Self.clamp(saturation, 0, 2)
        temp = Self.clamp(temp, -1, 1)
        tint = Self.clamp(tint, -1, 1)
        hue = Self.clamp(hue, -30, 30)
        shadows = Self.clamp(shadows, -1, 1)
        midpoint = Self.clamp(midpoint, -1, 1)
        highlights = Self.clamp(highlights, -1, 1)
        fade = Self.clamp(fade, 0, 1)
        mute = Self.clamp(mute, 0, 1)
        filmStrength = Self.clamp(filmStrength, 0, 1)
        dynamicRange = Self.clamp(dynamicRange, 0, 1.5)
        grainSize = Self.clamp(grainSize, 1, 4)
        sharpness = Self.clamp(sharpness, -0.5, 0.5)
        chromaticAberration = Self.clamp(chromaticAberration, 0, 4)
        bloom = Self.clamp(bloom, 0, 1)
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value.isFinite ? value : 0, low), high)
    }

    enum CodingKeys: String, CodingKey {
        case postExposure, contrast, saturation, temp, tint, hue, shadows, midpoint, highlights
        case fade, mute, filmStrength, dynamicRange, grainSize, sharpness, chromaticAberration, bloom, curve
    }

    /// Missing keys keep their neutral values, so files written before a regulator existed still load.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, _ fallback: Double) -> Double {
            (try? c.decodeIfPresent(Double.self, forKey: key)) ?? fallback
        }
        postExposure = value(.postExposure, postExposure)
        contrast = value(.contrast, contrast)
        saturation = value(.saturation, saturation)
        temp = value(.temp, temp)
        tint = value(.tint, tint)
        hue = value(.hue, hue)
        shadows = value(.shadows, shadows)
        midpoint = value(.midpoint, midpoint)
        highlights = value(.highlights, highlights)
        fade = value(.fade, fade)
        mute = value(.mute, mute)
        filmStrength = value(.filmStrength, filmStrength)
        dynamicRange = value(.dynamicRange, dynamicRange)
        grainSize = value(.grainSize, grainSize)
        sharpness = value(.sharpness, sharpness)
        chromaticAberration = value(.chromaticAberration, chromaticAberration)
        bloom = value(.bloom, bloom)
        curve = try? c.decodeIfPresent(ContrastCurve.self, forKey: .curve)
        clamp()
    }
}
