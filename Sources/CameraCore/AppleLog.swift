import Foundation

/// Apple Log, as published in Apple's "Apple Log Profile" white paper, and a neutral conversion to Rec.709.
///
/// The camera can stay in Apple Log for every preset: a preset with its own Apple Log LUT uses it, any other
/// preset gets `neutralRec709LUT()` followed by its normal LUT. Lampa ships the same idea as
/// `neutral_appleLog`; this one is computed from the published curve.
public enum AppleLog {
    static let r0: Float = -0.05641088
    static let rt: Float = 0.01
    static let c: Float = 47.28711236
    static let beta: Float = 0.00964052
    static let gamma: Float = 0.08550479
    static let delta: Float = 0.69336945
    /// Encoded value at `rt`, where the curve changes from the parabola to the log segment.
    static let pt: Float = c * (rt - r0) * (rt - r0)

    /// Scene-linear reflectance to Apple Log.
    public static func encode(_ r: Float) -> Float {
        if r >= rt { return gamma * log2(r + beta) + delta }
        if r >= r0 { return c * (r - r0) * (r - r0) }
        return 0
    }

    /// Apple Log to scene-linear reflectance.
    public static func decode(_ p: Float) -> Float {
        if p >= pt { return pow(2, (p - delta) / gamma) - beta }
        if p > 0 { return (p / c).squareRoot() + r0 }
        return r0
    }

    /// Linear Rec.2020 to linear Rec.709 primaries.
    static let rec2020To709: [[Float]] = [
        [1.6605, -0.5876, -0.0728],
        [-0.1246, 1.1329, -0.0083],
        [-0.0182, -0.1006, 1.1187],
    ]

    /// Linear up to 0.6, then a smooth shoulder towards 1, so highlights roll off instead of clipping.
    static func toneMap(_ x: Float) -> Float {
        let knee: Float = 0.6
        guard x > knee else { return max(x, 0) }
        return knee + (1 - knee) * (1 - exp(-(x - knee) / (1 - knee)))
    }

    /// Rec.709 OETF.
    static func rec709(_ l: Float) -> Float {
        l < 0.018 ? 4.5 * l : 1.099 * pow(l, 0.45) - 0.099
    }

    /// Apple Log R'G'B' (Rec.2020) to display Rec.709, neutral: 18% grey lands at about 0.41.
    public static func toRec709(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        let linear = [decode(r), decode(g), decode(b)]
        let m = rec2020To709
        let out = (0 ..< 3).map { row in
            let value = m[row][0] * linear[0] + m[row][1] * linear[1] + m[row][2] * linear[2]
            return min(max(rec709(toneMap(value)), 0), 1)
        }
        return (out[0], out[1], out[2])
    }

    public static func neutralRec709LUT(size: Int = 33) -> LUT3D {
        var values: [Float] = []
        values.reserveCapacity(size * size * size * 4)
        let scale = Float(size - 1)
        for b in 0 ..< size {
            for g in 0 ..< size {
                for r in 0 ..< size {
                    let out = toRec709(r: Float(r) / scale, g: Float(g) / scale, b: Float(b) / scale)
                    values += [out.0, out.1, out.2, 1]
                }
            }
        }
        // The size is in range and the count matches, so this cannot fail.
        return try! LUT3D(size: size, rgba: values)
    }
}

extension LUT3D {
    /// This LUT followed by `next`, baked into one LUT of this LUT's size.
    public func followed(by next: LUT3D) -> LUT3D {
        var values = rgba
        for index in stride(from: 0, to: values.count, by: 4) {
            let out = next.apply(r: values[index], g: values[index + 1], b: values[index + 2])
            values[index] = out.r
            values[index + 1] = out.g
            values[index + 2] = out.b
        }
        return try! LUT3D(size: size, rgba: values)
    }
}
