import Foundation

/// The ARRI preset: a pair of LUTs that expect ARRI LogC3 (EI 800) in ARRI Wide Gamut, and one slider that
/// mixes them.
///
/// Found by taking apart the yCam app these LUTs came from:
/// - the two files are a mirrored pair: `a` (`LogC3_AWG_to_sRGB`) has warm highlights and cool deep shadows,
///   `b` (`reverseCrossover`) the other way round. Their average is close to neutral;
/// - `Crossover` is a manual slider from -1 to 1, not something chosen from the picture's colour temperature;
/// - the mix weight of `a` is `(value + 1) / 2`, clamped to 0...1: +1 is only `a`, -1 only `b`, 0 half each.
///
/// The camera does not deliver LogC, so each kind of input is first turned into LogC3 AWG the way a colourist
/// would (to scene-linear, to ARRI Wide Gamut, LogC3 encode), and that is baked into both LUTs. The mix is then
/// a plain average of the two baked LUTs, cheap enough to redo on every slider step.
public enum ArriLook {
    public static let presetID = "preset-11"

    /// The slider's range; its middle is the neutral mix.
    public static let crossoverRange: ClosedRange<Double> = -1 ... 1

    /// Weight of the first LUT for a slider value, as yCam derives it.
    public static func weight(forCrossover value: Double) -> Float {
        Float(min(max((value + 1) / 2, 0), 1))
    }

    // MARK: ARRI LogC3 (EI 800) and ARRI Wide Gamut

    /// Scene-linear to LogC3, EI 800. May leave 0...1 for very dark or very bright values; the LUT clamps.
    public static func logC3(_ x: Float) -> Float {
        let cut: Float = 0.010591, a: Float = 5.555556, b: Float = 0.052272, c: Float = 0.247190
        let d: Float = 0.385537, e: Float = 5.367655, f: Float = 0.092809
        return x > cut ? c * log10(a * x + b) + d : e * x + f
    }

    /// ARRI Wide Gamut (D65 white) to XYZ.
    static let awgToXYZ: [[Float]] = [
        [0.638008, 0.214704, 0.097744],
        [0.291954, 0.823841, -0.115795],
        [0.002798, -0.067034, 1.153294],
    ]
    /// Linear Rec.709 / sRGB primaries to XYZ (D65).
    static let rec709ToXYZ: [[Float]] = [
        [0.4123908, 0.3575843, 0.1804808],
        [0.2126390, 0.7151687, 0.0721923],
        [0.0193308, 0.1191948, 0.9505322],
    ]
    /// Linear Rec.2020 (Apple Log's gamut) to XYZ (D65).
    static let rec2020ToXYZ: [[Float]] = [
        [0.6369580, 0.1446169, 0.1688810],
        [0.2627002, 0.6779981, 0.0593017],
        [0.0000000, 0.0280727, 1.0609851],
    ]

    static func multiply(_ a: [[Float]], _ b: [[Float]]) -> [[Float]] {
        (0 ..< 3).map { row in (0 ..< 3).map { col in (0 ..< 3).reduce(0) { $0 + a[row][$1] * b[$1][col] } } }
    }

    static func inverse(_ m: [[Float]]) -> [[Float]] {
        let a = m[0][0], b = m[0][1], c = m[0][2]
        let d = m[1][0], e = m[1][1], f = m[1][2]
        let g = m[2][0], h = m[2][1], i = m[2][2]
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        let k = 1 / det
        return [
            [(e * i - f * h) * k, (c * h - b * i) * k, (b * f - c * e) * k],
            [(f * g - d * i) * k, (a * i - c * g) * k, (c * d - a * f) * k],
            [(d * h - e * g) * k, (b * g - a * h) * k, (a * e - b * d) * k],
        ]
    }

    static let xyzToAWG = inverse(awgToXYZ)
    static let rec709ToAWG = multiply(xyzToAWG, rec709ToXYZ)
    static let rec2020ToAWG = multiply(xyzToAWG, rec2020ToXYZ)

    static func apply(_ m: [[Float]], _ v: [Float]) -> [Float] {
        (0 ..< 3).map { m[$0][0] * v[0] + m[$0][1] * v[1] + m[$0][2] * v[2] }
    }

    // MARK: Input transforms

    static func srgbToLinear(_ x: Float) -> Float {
        x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    static func rec709ToLinear(_ x: Float) -> Float {
        x < 0.081 ? x / 4.5 : pow((x + 0.099) / 1.099, 1 / 0.45)
    }

    /// The LogC3 AWG code values (0...1) an input pixel of the given kind stands for.
    /// Photos are taken as sRGB, standard video as Rec.709, and Apple Log through its published curve.
    /// Display-referred input keeps its middle grey: 18% grey lands at LogC 0.39, like ARRI's own workflow.
    public static func logCCode(for slot: LUTSlot, r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        let linear: [Float]
        let matrix: [[Float]]
        switch slot {
        case .photo:
            linear = [srgbToLinear(r), srgbToLinear(g), srgbToLinear(b)]
            matrix = rec709ToAWG
        case .video:
            linear = [rec709ToLinear(r), rec709ToLinear(g), rec709ToLinear(b)]
            matrix = rec709ToAWG
        case .appleLog:
            linear = [AppleLog.decode(r), AppleLog.decode(g), AppleLog.decode(b)]
            matrix = rec2020ToAWG
        }
        let awg = apply(matrix, linear)
        return (logC3(awg[0]), logC3(awg[1]), logC3(awg[2]))
    }

    /// `lut` seen through the input transform of `slot`: a LUT that takes that kind of input directly.
    public static func baked(_ lut: LUT3D, for slot: LUTSlot, size: Int = 65) -> LUT3D {
        bakedAll([lut], for: slot, size: size)[0]
    }

    /// Scene-linear value of each lattice step of a `size` cube, for one kind of input. The input curve is per
    /// channel, so it is worked out once per step instead of once per lattice point.
    static func linearSteps(for slot: LUTSlot, size: Int) -> [Float] {
        let scale = Float(size - 1)
        return (0 ..< size).map { step in
            let x = Float(step) / scale
            switch slot {
            case .photo: return srgbToLinear(x)
            case .video: return rec709ToLinear(x)
            case .appleLog: return AppleLog.decode(x)
            }
        }
    }

    /// Several LUTs baked through one input transform in a single pass: the LogC code of each lattice point is
    /// computed once and looked up in every LUT.
    static func bakedAll(_ luts: [LUT3D], for slot: LUTSlot, size: Int) -> [LUT3D] {
        let steps = linearSteps(for: slot, size: size)
        let m = slot == .appleLog ? rec2020ToAWG : rec709ToAWG
        let (m00, m10, m20) = (m[0][0], m[1][0], m[2][0])
        let count = size * size * size * 4
        var outputs = [[Float]](repeating: [Float](repeating: 1, count: count), count: luts.count)
        var index = 0
        for b in 0 ..< size {
            let lb = steps[b]
            for g in 0 ..< size {
                let lg = steps[g]
                // The green and blue parts of the matrix product are the same along the whole red row.
                let partR = m[0][1] * lg + m[0][2] * lb
                let partG = m[1][1] * lg + m[1][2] * lb
                let partB = m[2][1] * lg + m[2][2] * lb
                for r in 0 ..< size {
                    let lr = steps[r]
                    let cr = logC3(m00 * lr + partR)
                    let cg = logC3(m10 * lr + partG)
                    let cb = logC3(m20 * lr + partB)
                    for which in luts.indices {
                        let out = luts[which].apply(r: cr, g: cg, b: cb)
                        outputs[which][index] = out.r
                        outputs[which][index + 1] = out.g
                        outputs[which][index + 2] = out.b
                    }
                    index += 4
                }
            }
        }
        // The size is in range and the counts match, so this cannot fail.
        return outputs.map { try! LUT3D(size: size, rgba: $0) }
    }

    /// Both LUTs baked for one kind of input, ready to be mixed.
    public struct Pair: Sendable {
        public let a: LUT3D
        public let b: LUT3D

        public init(a: LUT3D, b: LUT3D, slot: LUTSlot, size: Int = 65) {
            let baked = ArriLook.bakedAll([a, b], for: slot, size: size)
            self.a = baked[0]
            self.b = baked[1]
        }

        /// The mix for a slider value. Mixing baked LUTs equals baking the mix, because the input transform comes first.
        public func mixed(crossover: Double) -> LUT3D {
            let wa = ArriLook.weight(forCrossover: crossover)
            if wa >= 1 { return a }
            if wa <= 0 { return b }
            var values = a.rgba
            b.rgba.withUnsafeBufferPointer { other in
                values.withUnsafeMutableBufferPointer { out in
                    // b + (a - b) * wa: one multiply per value.
                    for index in out.indices { out[index] = other[index] + (out[index] - other[index]) * wa }
                }
            }
            return try! LUT3D(size: a.size, rgba: values)
        }
    }
}
