import Foundation

/// The film effects as plain math. The Metal shaders in the app implement exactly these formulas;
/// this copy exists so the numbers can be tested and so the grain texture can be generated on the CPU.
///
/// The formulas follow Lampa 2.1.5 (`Ironstone/default.metallib`: `filmGrain`, `halation`,
/// `buildHalationMask8Bit420Full601`, `onePassGrade8Bit420YUVFull`), decoded from the shipped bitcode.
public enum FilmMath {
    /// BT.601 luma weights, as Lampa uses for its grain and halation masks.
    public static let lumaWeights: (r: Float, g: Float, b: Float) = (0.299, 0.587, 0.114)

    public static func luma(_ r: Float, _ g: Float, _ b: Float) -> Float {
        lumaWeights.r * r + lumaWeights.g * g + lumaWeights.b * b
    }

    // MARK: Halation

    /// Color the glow mixes toward: orange-red. Lampa multiplies (1, 0.39, 0.1) by the strength.
    public static let halationTint: (r: Float, g: Float, b: Float) = (1, 0.39, 0.1)

    /// Highlight mask, computed on the graded color: zero below luma 0.55, a smooth ramp above it.
    public static func halationMask(luma y: Float) -> Float {
        let t = clamp((y - 0.55) / 0.45)
        let k = clamp(7.5 * t)
        return k * k * (3 - 2 * k) * t * t
    }

    /// Adds the blurred mask `glow` to a pixel. The glow only lands on areas darker than luma 0.77,
    /// so highlights keep their color and the red fringe appears around them.
    public static func applyHalation(r: Float, g: Float, b: Float, glow: Float, strength: Float) -> (Float, Float, Float) {
        let w = clamp(0.77 - luma(r, g, b))
        let amount = strength * w * glow
        return (
            clamp(r * (1 - amount) + amount * halationTint.r),
            clamp(g * (1 - amount) + amount * halationTint.g),
            clamp(b * (1 - amount) + amount * halationTint.b)
        )
    }

    /// Preset value 0...1 to shader strength. 1 is Lampa's video strength (4.5); its photo path uses 2.8.
    public static func halationStrength(_ amount: Double) -> Float {
        // Presets go up to 1; the camera screen's HIGH level pushes past it.
        Float(min(max(amount, 0), 2)) * 4.5
    }

    // MARK: Grain

    /// How much grain a pixel of this luma gets: most in the midtones, little in deep shadows and highlights.
    public static func grainWeight(luma y: Float) -> Float {
        y > 0.5 ? 1.12 - y : y + 0.18
    }

    /// Preset value 0...1 to the shader's grain intensity.
    public static func grainIntensity(_ amount: Double) -> Float {
        Float(min(max(amount, 0), 1)) * 0.4
    }

    /// `noise` is a grain texture sample in 0...1, centered on 0.5.
    public static func applyGrain(_ value: Float, luma y: Float, noise: Float, intensity: Float) -> Float {
        clamp(value + intensity * grainWeight(luma: y) * (noise - 0.5))
    }

    /// Standard deviation of grain texture values around 0.5.
    public static let grainDeviation: Float = 0.16

    /// A tileable square of film grain: Gaussian noise softened by a small blur so single pixels do not
    /// sparkle, rescaled to `grainDeviation` and stored as 0...1 around 0.5. Row-major, `size * size` values.
    public static func grainTexture(size: Int, seed: UInt64) -> [Float] {
        precondition(size >= 4)
        var rng = SplitMix64(seed: seed)
        var noise = [Float](repeating: 0, count: size * size)
        var index = 0
        while index < noise.count {
            // Box-Muller gives two normal values per pair of uniforms.
            let u1 = max(rng.nextUnit(), 1e-7)
            let u2 = rng.nextUnit()
            let radius = (-2 * log(u1)).squareRoot()
            noise[index] = Float(radius * cos(2 * .pi * u2))
            if index + 1 < noise.count { noise[index + 1] = Float(radius * sin(2 * .pi * u2)) }
            index += 2
        }

        // Separable [1 2 1] / 4 blur that wraps around, so the texture still tiles.
        func blurPass(_ input: [Float], horizontal: Bool) -> [Float] {
            var output = input
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let (a, b): (Int, Int) = horizontal
                        ? (y * size + (x + size - 1) % size, y * size + (x + 1) % size)
                        : (((y + size - 1) % size) * size + x, ((y + 1) % size) * size + x)
                    output[y * size + x] = 0.25 * input[a] + 0.5 * input[y * size + x] + 0.25 * input[b]
                }
            }
            return output
        }
        let blurred = blurPass(blurPass(noise, horizontal: true), horizontal: false)

        let count = Float(blurred.count)
        let mean = blurred.reduce(0, +) / count
        let variance = blurred.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
        let scale = grainDeviation / max(variance.squareRoot(), 1e-6)
        return blurred.map { clamp(0.5 + ($0 - mean) * scale) }
    }

    // MARK: Apple Log input

    /// Converts one 10-bit video-range BT.2020 sample (as the camera delivers Apple Log) to R'G'B'.
    /// The codes are 10-bit values: luma 64...940, chroma 64...960 around 512.
    public static func appleLogRGB(y: Float, cb: Float, cr: Float) -> (Float, Float, Float) {
        let luma = (y - 64) / 876
        let blue = (cb - 512) / 896
        let red = (cr - 512) / 896
        return (
            clamp(luma + 1.4746 * red),
            clamp(luma - 0.16455 * blue - 0.57135 * red),
            clamp(luma + 1.8814 * blue)
        )
    }

    static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

/// Small deterministic generator so grain textures are the same on every launch.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
