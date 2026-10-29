import Foundation

/// The lens picker's previews: a night scene of out-of-focus lights. Each light is drawn with the lens's own
/// sample pattern (`LensKernel`), the one the portrait blur gathers with, so a preview shows the shape a photo
/// gets. The same lights for every lens, so the previews differ only by lens. The app draws the bytes.
public enum LensPreviewScene {
    public struct Light: Equatable, Sendable {
        /// Centre in 0...1 of the preview, y down.
        public var x: Double
        public var y: Double
        /// Radius as a fraction of the preview's side.
        public var radius: Double
        public var red: Double
        public var green: Double
        public var blue: Double
        public var brightness: Double
    }

    /// Warm street lights, a few cool ones and some magenta, like a city at night.
    static let palette: [(Double, Double, Double)] = [
        (1.00, 0.55, 0.16), (1.00, 0.70, 0.28), (1.00, 0.86, 0.45), (1.00, 0.26, 0.16),
        (0.22, 0.34, 1.00), (0.52, 0.26, 1.00), (1.00, 0.30, 0.58), (0.26, 0.85, 0.70),
        (1.00, 0.93, 0.80),
    ]

    public static func lights(count: Int = 34, seed: UInt64 = 11) -> [Light] {
        var state = seed
        func next() -> Double {
            // SplitMix64, enough for a stable layout.
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        return (0 ..< count).map { _ in
            let color = palette[Int(next() * Double(palette.count)) % palette.count]
            return Light(
                x: -0.05 + 1.1 * next(),
                y: -0.05 + 1.1 * next(),
                radius: 0.045 + 0.085 * next(),
                red: color.0,
                green: color.1,
                blue: color.2,
                brightness: 0.3 + 0.7 * pow(next(), 1.4)
            )
        }
    }

    /// RGBA bytes, `size` × `size`. A few milliseconds per lens; call off the main thread.
    public static func render(lens: LensStyle, size: Int) -> [UInt8] {
        guard size > 0 else { return [] }
        let side = Double(size)
        var red = [Double](repeating: 0, count: size * size)
        var green = red, blue = red
        // Chromatic fringing: red from a little further out, blue from a little further in, as the photo's bokeh.
        let fringe = 0.12 * lens.fringing

        for light in lights() {
            let spot = LensKernel.spot(uv: SIMD2(Float(light.x), Float(light.y)), aspect: 1)
            let radius = light.radius * side
            // Each sample lays down a small soft dot; neighbouring samples overlap into one filled shape.
            let footprint = max(1.0, radius * 0.22)
            let cx = light.x * side, cy = light.y * side
            for index in 0 ..< LensKernel.sampleCount {
                guard let tap = LensKernel.tap(index: index, rotation: 0, lens: lens, spot: spot) else { continue }
                let weight = Double(tap.weight) * light.brightness * 0.4
                let channels: [(Int, Double)] = [(0, 1 + fringe), (1, 1), (2, 1 - fringe)]
                for (channel, scale) in channels {
                    let x = cx + Double(tap.offset.x) * radius * scale
                    let y = cy + Double(tap.offset.y) * radius * scale
                    let x0 = max(0, Int((x - footprint).rounded(.down))), x1 = min(size - 1, Int((x + footprint).rounded(.up)))
                    let y0 = max(0, Int((y - footprint).rounded(.down))), y1 = min(size - 1, Int((y + footprint).rounded(.up)))
                    guard x0 <= x1, y0 <= y1 else { continue }
                    for py in y0 ... y1 {
                        for px in x0 ... x1 {
                            let dx = (Double(px) + 0.5 - x) / footprint, dy = (Double(py) + 0.5 - y) / footprint
                            let falloff = max(0, 1 - (dx * dx + dy * dy))
                            guard falloff > 0 else { continue }
                            let index = py * size + px
                            let value = weight * falloff
                            switch channel {
                            case 0: red[index] += value * light.red
                            case 1: green[index] += value * light.green
                            default: blue[index] += value * light.blue
                            }
                        }
                    }
                }
            }
        }

        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for py in 0 ..< size {
            for px in 0 ..< size {
                let nx = (Double(px) + 0.5) / side - 0.5, ny = (Double(py) + 0.5) / side - 0.5
                let r2 = (nx * nx + ny * ny) / 0.5
                let vignette = 1 - lens.vignette * pow(r2, 1.2)
                // A deep blue-black night behind the lights.
                let base = (0.004 + 0.008 * (1 - r2), 0.004 + 0.007 * (1 - r2), 0.010 + 0.014 * (1 - r2))
                let index = py * size + px
                let rgb = [red[index] + base.0, green[index] + base.1, blue[index] + base.2].map { value -> UInt8 in
                    // Soft clip, so stacked lights glow instead of going flat white.
                    let mapped = (1 - exp(-1.6 * value * vignette)) / (1 - exp(-1.6))
                    return UInt8(min(max(pow(mapped, 1.15) * 255, 0), 255))
                }
                pixels[index * 4] = rgb[0]
                pixels[index * 4 + 1] = rgb[1]
                pixels[index * 4 + 2] = rgb[2]
            }
        }
        return pixels
    }
}
