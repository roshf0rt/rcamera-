import Foundation

/// What a LUT does to a picture, measured by running reference colors through it.
///
/// - `tones`: neutral greys from deep shadow to highlight. Shows contrast, black lift and split toning.
/// - memory colors (skin, foliage, sky, warm light): the colors people judge a look by.
/// - metrics and `tags`: the same in words, for the preset card ("Warm · Faded · Soft").
public struct LUTProfile: Codable, Equatable, Sendable {
    public var tones: [RGBColor]
    public var skin: RGBColor
    public var foliage: RGBColor
    public var sky: RGBColor
    public var warmLight: RGBColor

    /// Output luma of pure black. Above ~0.06 the blacks look lifted ("faded").
    public var blackLevel: Float
    /// Output luma of pure white. Below ~0.9 the highlights look rolled off.
    public var whiteLevel: Float
    /// Midtone slope: luma change between 25% and 75% grey, relative to the input change. 1 is neutral.
    public var contrast: Float
    /// Average chroma of the memory colors after the LUT, relative to before. 1 is neutral.
    public var saturation: Float
    /// Red minus blue of the grey ramp. Positive is warm.
    public var warmth: Float
    /// Green minus magenta of the grey ramp. Positive is green.
    public var tint: Float
    /// Warmth of shadows and of highlights separately, for split toning.
    public var shadowWarmth: Float
    public var highlightWarmth: Float
    /// Hue shifts in degrees (positive goes red → yellow → green → cyan → blue).
    public var skinHueShift: Float
    public var foliageHueShift: Float
    public var skyHueShift: Float

    public var tags: [String]

    /// Input greys for `tones`.
    public static let toneInputs: [Float] = [0.04, 0.22, 0.45, 0.7, 0.94]
    public static let skinInput = RGBColor(r: 0.80, g: 0.58, b: 0.47)
    public static let foliageInput = RGBColor(r: 0.34, g: 0.50, b: 0.26)
    public static let skyInput = RGBColor(r: 0.46, g: 0.64, b: 0.88)
    public static let warmLightInput = RGBColor(r: 0.95, g: 0.70, b: 0.38)

    public init(lut: LUT3D) {
        func run(_ color: RGBColor) -> RGBColor {
            let out = lut.apply(r: color.r, g: color.g, b: color.b)
            return RGBColor(r: out.r, g: out.g, b: out.b)
        }
        func grey(_ value: Float) -> RGBColor { run(RGBColor(r: value, g: value, b: value)) }
        func luma(_ c: RGBColor) -> Float { FilmMath.luma(c.r, c.g, c.b) }
        func chroma(_ c: RGBColor) -> Float { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
        func warmthOf(_ c: RGBColor) -> Float { c.r - c.b }
        func tintOf(_ c: RGBColor) -> Float { c.g - (c.r + c.b) / 2 }

        tones = Self.toneInputs.map(grey)
        skin = run(Self.skinInput)
        foliage = run(Self.foliageInput)
        sky = run(Self.skyInput)
        warmLight = run(Self.warmLightInput)

        blackLevel = luma(grey(0))
        whiteLevel = luma(grey(1))
        contrast = (luma(grey(0.75)) - luma(grey(0.25))) / 0.5

        let inputs = [Self.skinInput, Self.foliageInput, Self.skyInput, Self.warmLightInput]
        let outputs = [skin, foliage, sky, warmLight]
        let before = inputs.map(chroma).reduce(0, +)
        let after = outputs.map(chroma).reduce(0, +)
        saturation = before > 0 ? after / before : 1

        let ramp = [0.15, 0.3, 0.5, 0.7, 0.85].map { grey(Float($0)) }
        warmth = ramp.map(warmthOf).reduce(0, +) / Float(ramp.count)
        tint = ramp.map(tintOf).reduce(0, +) / Float(ramp.count)
        shadowWarmth = warmthOf(grey(0.15))
        highlightWarmth = warmthOf(grey(0.85))
        skinHueShift = Self.hueShift(from: Self.skinInput, to: skin)
        foliageHueShift = Self.hueShift(from: Self.foliageInput, to: foliage)
        skyHueShift = Self.hueShift(from: Self.skyInput, to: sky)

        tags = []
        tags = Self.describe(self)
    }

    /// Hue in degrees, 0 red, 120 green, 240 blue. Nil for greys.
    static func hue(_ c: RGBColor) -> Float? {
        let high = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b)
        let delta = high - low
        guard delta > 0.02 else { return nil }
        var h: Float
        if high == c.r {
            h = (c.g - c.b) / delta
        } else if high == c.g {
            h = 2 + (c.b - c.r) / delta
        } else {
            h = 4 + (c.r - c.g) / delta
        }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    static func hueShift(from input: RGBColor, to output: RGBColor) -> Float {
        guard let a = hue(input), let b = hue(output) else { return 0 }
        var d = b - a
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Up to three words for the look, strongest first. "Natural" when nothing stands out.
    /// Each candidate is scored by how far past its threshold it is.
    static func describe(_ p: LUTProfile) -> [String] {
        var candidates: [(String, Float)] = []
        let mono = p.saturation < 0.15
        if mono {
            candidates.append(("Black & White", 10))
        }

        let split = p.highlightWarmth - p.shadowWarmth
        if !mono {
            if split > 0.08, p.shadowWarmth < -0.015, p.highlightWarmth > 0.015 {
                candidates.append(("Teal & Orange", split / 0.08))
            } else {
                if p.warmth > 0.025 { candidates.append(("Warm", p.warmth / 0.025)) }
                if p.warmth < -0.025 { candidates.append(("Cool", -p.warmth / 0.025)) }
                if p.shadowWarmth > 0.04 { candidates.append(("Warm shadows", p.shadowWarmth / 0.04)) }
                if p.shadowWarmth < -0.04 { candidates.append(("Cool shadows", -p.shadowWarmth / 0.04)) }
                if p.highlightWarmth > 0.04 { candidates.append(("Warm highlights", p.highlightWarmth / 0.04)) }
                if p.highlightWarmth < -0.04 { candidates.append(("Cool highlights", -p.highlightWarmth / 0.04)) }
            }
            if p.tint > 0.02 { candidates.append(("Green tint", p.tint / 0.02)) }
            if p.tint < -0.02 { candidates.append(("Magenta tint", -p.tint / 0.02)) }

            if p.saturation < 0.82 {
                candidates.append(("Muted", (1 - p.saturation) / 0.18))
            } else if p.saturation > 1.15 {
                candidates.append(("Vivid", (p.saturation - 1) / 0.15))
            } else if p.saturation > 1.06 {
                candidates.append(("Rich color", (p.saturation - 1) / 0.08))
            }

            if p.foliageHueShift > 12 { candidates.append(("Teal greens", p.foliageHueShift / 12)) }
            if p.foliageHueShift < -12 { candidates.append(("Olive greens", -p.foliageHueShift / 12)) }
            if p.skyHueShift < -12 { candidates.append(("Cyan skies", -p.skyHueShift / 12)) }
            if p.skyHueShift > 12 { candidates.append(("Deep blues", p.skyHueShift / 12)) }
            if p.skinHueShift > 4 { candidates.append(("Golden skin", p.skinHueShift / 4)) }
            if p.skinHueShift < -4 { candidates.append(("Rosy skin", -p.skinHueShift / 4)) }
        }

        if p.blackLevel > 0.06 { candidates.append(("Faded", p.blackLevel / 0.06)) }
        if p.contrast > 1.12 {
            candidates.append(("Punchy", (p.contrast - 1) / 0.12))
        } else if p.contrast > 1.06 {
            candidates.append(("Crisp", (p.contrast - 1) / 0.08))
        } else if p.contrast < 0.9 {
            candidates.append(("Soft", (1 - p.contrast) / 0.1))
        }
        if p.whiteLevel < 0.88 { candidates.append(("Matte", (1 - p.whiteLevel) / 0.12)) }

        let words = candidates.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        return words.isEmpty ? ["Natural"] : Array(words)
    }
}
