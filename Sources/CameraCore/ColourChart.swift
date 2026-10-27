import Foundation

/// Shows what a look does to known colours, for the preset editor's colour chart. It runs the same steps
/// as the shader on the CPU: regulators, then the LUT blended by film strength.
public enum ColourChart {
    /// Rows of patches, top to bottom: a grey ramp, four hue families at four brightnesses, six named tones.
    public static var patches: [[SIMD3<Double>]] {
        let greys = (0 ..< 16).map { step -> SIMD3<Double> in
            let value = Double(step) / 15
            return SIMD3(value, value, value)
        }
        let families: [SIMD3<Double>] = [
            SIMD3(0.8, 0.2, 0.2), SIMD3(0.2, 0.7, 0.3), SIMD3(0.2, 0.4, 0.9), SIMD3(0.95, 0.8, 0.2),
        ]
        let levels = [0.35, 0.6, 0.8, 1.0]
        let hues = levels.map { level in families.map { $0 * level } }
        let named: [SIMD3<Double>] = [
            SIMD3(0.93, 0.75, 0.62), SIMD3(0.55, 0.75, 0.95), SIMD3(0.35, 0.5, 0.2),
            SIMD3(0.6, 0.3, 0.2), SIMD3(0.2, 0.35, 0.4), SIMD3(0.7, 0.55, 0.8),
        ]
        return [greys] + hues + [named]
    }

    /// One patch after the look. Without a LUT only the regulators apply.
    public static func grade(_ color: SIMD3<Double>, look: LookAdjustments, lut: LUT3D?) -> SIMD3<Double> {
        let regulated = ToneMath.regulate(color, look)
        guard let lut else { return regulated }
        let mapped = lut.apply(r: Float(regulated.x), g: Float(regulated.y), b: Float(regulated.z))
        let graded = SIMD3(Double(mapped.r), Double(mapped.g), Double(mapped.b))
        return regulated + (graded - regulated) * look.filmStrength
    }
}
