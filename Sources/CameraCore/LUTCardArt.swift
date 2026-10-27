import Foundation

/// Picture for a preset card: a soft, abstract landscape (sky, low sun, horizon, foliage, a warm skin-toned
/// patch, deep shadows) run through the preset's LUT. Every card shows the same scene, so the differences
/// between cards are exactly what each LUT does to sky, sunlight, greens, skin and shadows.
public enum LUTCardArt {
    /// RGBA8, row-major, top row first, sRGB-encoded values. Without a LUT the scene is returned as is.
    public static func render(lut: LUT3D?, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let u = (Float(x) + 0.5) / Float(width)
                let v = (Float(y) + 0.5) / Float(height)
                var color = scene(u: u, v: v)
                if let lut {
                    let out = lut.apply(r: color.r, g: color.g, b: color.b)
                    color = RGBColor(r: out.r, g: out.g, b: out.b)
                }
                let index = (y * width + x) * 4
                pixels[index] = byte(color.r)
                pixels[index + 1] = byte(color.g)
                pixels[index + 2] = byte(color.b)
            }
        }
        return pixels
    }

    /// The scene at (u, v), both 0...1 from the top-left. Smooth everywhere, like a defocused photo.
    public static func scene(u: Float, v: Float) -> RGBColor {
        let skyTop = RGBColor(r: 0.26, g: 0.42, b: 0.74)
        let horizon = RGBColor(r: 0.88, g: 0.80, b: 0.70)
        var sky = mix(skyTop, horizon, pow(smoothstep(0, 0.62, v), 1.2))

        // Low sun to the right: a warm highlight bloom.
        let dx = (u - 0.74) * 1.6, dy = v - 0.5
        let glow = exp(-(dx * dx + dy * dy) / (0.2 * 0.2))
        sky = mix(sky, RGBColor(r: 1.0, g: 0.80, b: 0.50), glow * 0.85)

        // Rolling horizon, then ground getting darker towards the bottom.
        let line = 0.58 + 0.05 * sin(u * 5 + 0.6)
        let groundAmount = smoothstep(line - 0.02, line + 0.03, v)
        let depth = smoothstep(line, 1, v)
        let green = mix(RGBColor(r: 0.36, g: 0.50, b: 0.25), RGBColor(r: 0.07, g: 0.10, b: 0.06), depth)
        let skin = mix(RGBColor(r: 0.82, g: 0.62, b: 0.50), RGBColor(r: 0.30, g: 0.20, b: 0.16), pow(depth, 0.9))
        let warmPatch = smoothstep(0.42, 0.18, u + (v - 0.6) * 0.35)
        let ground = mix(green, skin, warmPatch)

        return mix(sky, ground, groundAmount)
    }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: RGBColor, _ b: RGBColor, _ t: Float) -> RGBColor {
        RGBColor(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }

    private static func byte(_ value: Float) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}
