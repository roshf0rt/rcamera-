import Foundation

/// Hue, saturation and light per colour band, applied after the LUT. Eight bands around the colour wheel, as in
/// photo editors; between them the corrections blend smoothly by the pixel's hue (`hslCurve` in the shader
/// spec). Slider values are -1...1; neutral everywhere changes nothing.
public struct ColorMix: Codable, Equatable, Hashable, Sendable {
    public enum Band: Int, CaseIterable, Sendable {
        case red, orange, yellow, green, aqua, blue, purple, magenta

        public var title: String {
            switch self {
            case .red: "Red"
            case .orange: "Orange"
            case .yellow: "Yellow"
            case .green: "Green"
            case .aqua: "Aqua"
            case .blue: "Blue"
            case .purple: "Purple"
            case .magenta: "Magenta"
            }
        }

        /// Where the band sits on the colour wheel, in turns (0 red, 1/3 green, 2/3 blue).
        public var wheelPosition: Double { ColorMixMath.bandHues[rawValue] }
    }

    public static let bandCount = Band.allCases.count

    /// -1...1, ±30° at the ends.
    public var hue: [Double]
    /// -1 takes the colour out, +1 doubles its saturation.
    public var saturation: [Double]
    /// Darker (−) or brighter (+); greys are left alone.
    public var light: [Double]

    public init() {
        hue = Array(repeating: 0, count: Self.bandCount)
        saturation = Array(repeating: 0, count: Self.bandCount)
        light = Array(repeating: 0, count: Self.bandCount)
    }

    public static let neutral = ColorMix()

    public var isNeutral: Bool { self == .neutral }

    public subscript(hue band: Band) -> Double {
        get { hue[band.rawValue] }
        set { hue[band.rawValue] = newValue }
    }

    public subscript(saturation band: Band) -> Double {
        get { saturation[band.rawValue] }
        set { saturation[band.rawValue] = newValue }
    }

    public subscript(light band: Band) -> Double {
        get { light[band.rawValue] }
        set { light[band.rawValue] = newValue }
    }

    /// Eight values per curve, each in -1...1.
    public mutating func clamp() {
        func fixed(_ values: [Double]) -> [Double] {
            (0 ..< Self.bandCount).map { index in
                index < values.count ? LookAdjustments.clamp(values[index], -1, 1) : 0
            }
        }
        hue = fixed(hue)
        saturation = fixed(saturation)
        light = fixed(light)
    }

    enum CodingKeys: String, CodingKey { case hue, saturation, light }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hue = (try? c.decodeIfPresent([Double].self, forKey: .hue)) ?? hue
        saturation = (try? c.decodeIfPresent([Double].self, forKey: .saturation)) ?? saturation
        light = (try? c.decodeIfPresent([Double].self, forKey: .light)) ?? light
        clamp()
    }

    /// The 24 numbers the grade kernel reads (`colorMix` buffer in Grade.metal): hue offsets in turns, then
    /// saturation offsets, then light offsets, eight each, in band order.
    public var shaderValues: [Float] {
        hue.map { Float($0 * ColorMixMath.hueLimit) }
            + saturation.map { Float($0) }
            + light.map { Float($0 * ColorMixMath.lightScale) }
    }
}

/// The colour mixer, vibrance and highlight roll-off, after the LUT. Mirrors `colorMixer`, `vibrance` and
/// `rollOff` in Grade.metal, so the shader's behaviour can be tested here.
public enum ColorMixMath {
    /// Band positions in turns: red, orange, yellow, green, aqua, blue, purple, magenta.
    public static let bandHues: [Double] = [0, 30, 60, 120, 180, 240, 270, 300].map { $0 / 360 }
    /// The largest hue shift, in turns (30°).
    public static let hueLimit = 1.0 / 12
    /// Light slider at ±1 asks for this much brighter or darker value.
    public static let lightScale = 0.5
    static let eps = 1.000000013351432e-10

    /// Hue, saturation and value (HSV: value is the largest channel).
    public static func hsv(_ c: SIMD3<Double>) -> (h: Double, s: Double, v: Double) {
        let third = 1.0 / 3, twoThirds = 2.0 / 3
        let p: SIMD4<Double> = c.y >= c.z ? SIMD4(c.y, c.z, 0, -third) : SIMD4(c.z, c.y, -1, twoThirds)
        let q: SIMD4<Double> = c.x >= p.x ? SIMD4(c.x, p.y, p.z, p.x) : SIMD4(p.x, p.y, p.w, c.x)
        let delta = q.x - min(q.w, q.y)
        let h = abs(q.z + (q.w - q.y) / (6 * delta + eps))
        return (h, delta / (q.x + eps), q.x)
    }

    /// The value of a per-band curve at hue `h` (turns): smoothstep between neighbouring bands, wrapping from
    /// magenta back to red.
    public static func curve(_ values: [Double], at h: Double) -> Double {
        let hues = bandHues
        for index in 0 ..< hues.count - 1 where h >= hues[index] && h <= hues[index + 1] {
            return blend(values[index], values[index + 1], (h - hues[index]) / (hues[index + 1] - hues[index]))
        }
        let first = hues[0], last = hues[hues.count - 1]
        let wrapped = h < first ? h + 1 : h
        return blend(values[hues.count - 1], values[0], (wrapped - last) / (first + 1 - last))
    }

    private static func blend(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let s = t * t * (3 - 2 * t)
        return a + (b - a) * s
    }

    /// Hue, then light, then saturation, each by the pixel's own hue.
    public static func mix(_ input: SIMD3<Double>, _ mix: ColorMix) -> SIMD3<Double> {
        guard !mix.isNeutral else { return input }
        let values = mix.shaderValues.map { Double($0) }
        let n = ColorMix.bandCount
        var c = simd_clamp01(input)
        let (h0, s0, v0) = hsv(c)
        let h = curve(Array(values[0 ..< n]), at: h0)
        let s = curve(Array(values[n ..< 2 * n]), at: h0)
        let l = curve(Array(values[2 * n ..< 3 * n]), at: h0)

        if h != 0 {
            var shifted = h0 + min(max(h, -hueLimit), hueLimit)
            if shifted < 0 { shifted += 1 } else if shifted > 1 { shifted -= 1 }
            let k = SIMD3(1.0, 2.0 / 3, 1.0 / 3)
            let wheel = SIMD3(fract(shifted + k.x), fract(shifted + k.y), fract(shifted + k.z))
            let p = simd_clamp01(SIMD3(abs(wheel.x * 6 - 3) - 1, abs(wheel.y * 6 - 3) - 1, abs(wheel.z * 6 - 3) - 1))
            c = v0 * (SIMD3(repeating: 1) + (p - SIMD3(repeating: 1)) * s0)
        }

        let v1 = min(max((1 + s0 * l) * v0, -1), 1)
        let ql = v0 == 0 ? v1 : (v1 - v0) / v0
        if ql != 0 {
            let z = 1.0449999570846558 * ql
            let exponent = z >= 0 ? 1 + abs(z) : 1 / (1 + abs(z))
            func lit(_ x: Double) -> Double { abs(1 - x) < 9.999999747378752e-6 ? 1 : 1 - pow(max(1 - x, 0), exponent) }
            c = SIMD3(lit(c.x), lit(c.y), lit(c.z))
        }

        let s1 = min(max(s0 * (1 + s), -1), 1)
        let qs = s0 == 0 ? s1 : (s1 - s0) / s0
        if qs > 0 {
            let luma = c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722
            let k = 1 + (1 - c.max() + c.min()) * qs
            c = SIMD3(repeating: luma) + (c - SIMD3(repeating: luma)) * k
        } else if qs < 0 {
            let t = min(max(-qs, 0), 1).squareRoot()
            let luma = c.x * 0.299 + c.y * 0.587 + c.z * 0.114
            c = c + (SIMD3(repeating: luma) - c) * t
        }
        return c
    }

    /// Pushes muted colours more than saturated ones; 0 changes nothing, negative mutes.
    public static func vibrance(_ c: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        guard amount != 0 else { return c }
        let luma = c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722
        let t = 1 + (1 - c.max() + c.min()) * amount
        return SIMD3(repeating: luma) + (c - SIMD3(repeating: luma)) * t
    }

    /// Where the roll-off starts for a slider value 0...1; nil when it is off.
    public static func rollOffThreshold(_ strength: Double) -> Double? {
        strength > 0 ? 1 - 0.6 * min(strength, 1) : nil
    }

    /// Soft shoulder above `threshold` that keeps the ratio between channels, after pulling negative channels
    /// towards the pixel's luminance.
    public static func rollOff(_ input: SIMD3<Double>, threshold: Double) -> SIMD3<Double> {
        var c = input
        let lowest = c.min()
        if lowest < 0 {
            let luma = max(c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722, 0)
            let denominator = luma - lowest
            let scale = denominator > 0 ? luma / denominator : 0
            c = simd_max(SIMD3(repeating: luma) + (c - SIMD3(repeating: luma)) * scale, SIMD3(repeating: 0))
        }
        let top = c.max()
        guard top > threshold else { return c }
        let headroom = 1 - threshold, over = top - threshold
        let compressed = threshold + over * headroom / (over + headroom)
        return simd_clamp01(c * (compressed / top))
    }

    /// Everything after the LUT, in the shader's order: colour mixer, vibrance, roll-off, then clamped to 0...1.
    public static func apply(_ c: SIMD3<Double>, look: LookAdjustments) -> SIMD3<Double> {
        var out = mix(c, look.colorMix)
        out = vibrance(out, look.vibrance)
        if let threshold = rollOffThreshold(look.highlightRolloff) { out = rollOff(out, threshold: threshold) }
        if look.colorMix.isNeutral, look.vibrance == 0, look.highlightRolloff == 0 { return c }
        return simd_clamp01(out)
    }

    private static func fract(_ x: Double) -> Double { x - x.rounded(.down) }

    private static func simd_clamp01(_ c: SIMD3<Double>) -> SIMD3<Double> {
        simd_min(simd_max(c, SIMD3(repeating: 0)), SIMD3(repeating: 1))
    }

    private static func simd_max(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
    }

    private static func simd_min(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
    }
}
