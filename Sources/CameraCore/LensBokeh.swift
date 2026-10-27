import Foundation

/// The lens picker's preview: a night scene of out-of-focus lights drawn the way each lens renders them.
/// This file holds the layout and the shape maths; the app draws it with Core Graphics.
///
/// mood.camera ships a photo per lens for this. RCamera draws its own from the lens parameters, so the
/// previews follow the numbers the photo pipeline uses.
public enum LensBokeh {
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

    /// How one light is bent by the lens at its place in the frame.
    public struct Shape: Equatable, Sendable {
        /// Scale along the line from the centre to the light.
        public var radialScale: Double
        /// Scale across that line.
        public var tangentialScale: Double
        /// Rotation of the shape, radians; the radial axis points along this angle.
        public var angle: Double
        /// How far the cat's-eye cut sits from the light's centre, in radii; nil when there is no cut.
        public var catsEyeCut: Double?
    }

    /// Warm street lights, a few cool ones and some magenta, like a city at night.
    static let palette: [(Double, Double, Double)] = [
        (1.00, 0.55, 0.16), (1.00, 0.70, 0.28), (1.00, 0.86, 0.45), (1.00, 0.26, 0.16),
        (0.22, 0.34, 1.00), (0.52, 0.26, 1.00), (1.00, 0.30, 0.58), (0.26, 0.85, 0.70),
        (1.00, 0.93, 0.80),
    ]

    /// The same lights for every lens, so the previews differ only by lens. Deterministic.
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

    /// Cat's eye squeezes lights towards the edges radially, swirl stretches them around the centre,
    /// ovality makes them taller or wider everywhere.
    public static func shape(of light: Light, lens: LensStyle) -> Shape {
        let dx = light.x - 0.5, dy = light.y - 0.5
        let distance = min(1, (dx * dx + dy * dy).squareRoot() / 0.7071)
        let angle = distance > 0.0001 ? atan2(dy, dx) : 0
        var radial = 1 - 0.45 * lens.catsEye * distance * distance
        var tangential = 1 + 0.6 * lens.swirl * distance
        // Ovality acts on the frame's vertical axis; split it into the radial and tangential parts.
        let vertical = 1 + 0.6 * lens.ovality
        let sinA = abs(sin(angle)), cosA = abs(cos(angle))
        radial *= vertical * sinA + cosA
        tangential *= vertical * cosA + sinA
        let cut = lens.catsEye * distance > 0.12 ? 1.6 - 0.9 * lens.catsEye * distance : nil
        return Shape(radialScale: max(0.3, radial), tangentialScale: max(0.3, tangential), angle: angle, catsEyeCut: cut)
    }

    /// Opacity of a light at a fraction `t` of its radius (0 centre, 1 edge): a bright rim and a hollow
    /// centre for ring lenses, a soft fade for negative rims, an even disc in between.
    public static func profile(_ t: Double, lens: LensStyle) -> Double {
        let t = min(max(t, 0), 1)
        if lens.rim < 0 {
            let softness = -lens.rim
            let edge = 1 - softness * 0.85
            guard t > edge else { return 1 }
            let u = (t - edge) / (1 - edge)
            return pow(1 - u, 1.5)
        }
        let rimStart = 1 - lens.rimWidth
        let body = 1 - 0.75 * lens.rim
        let rimLevel = min(1, body + 0.5 * lens.rim + 0.15)
        return t < rimStart ? body : rimLevel
    }
}

extension LensBokeh {
    /// Renders the preview as RGBA bytes, `size` × `size`. A few milliseconds per lens; call off the main thread.
    public static func render(lens: LensStyle, size: Int) -> [UInt8] {
        let side = Double(size)
        var red = [Double](repeating: 0, count: size * size)
        var green = red, blue = red
        // Fringing splits each light's red and blue rims apart along its radial axis.
        let fringe = 0.08 * lens.fringing
        let blades = lens.bladeCount

        for light in lights() {
            let shape = shape(of: light, lens: lens)
            let radius = light.radius * side
            let reach = radius * max(shape.radialScale, shape.tangentialScale) * (1 + fringe) + 2
            let cx = light.x * side, cy = light.y * side
            let cosA = cos(shape.angle), sinA = sin(shape.angle)
            let x0 = max(0, Int(cx - reach)), x1 = min(size - 1, Int(cx + reach))
            let y0 = max(0, Int(cy - reach)), y1 = min(size - 1, Int(cy + reach))
            guard x0 <= x1, y0 <= y1 else { continue }

            for py in y0 ... y1 {
                for px in x0 ... x1 {
                    let dx = Double(px) + 0.5 - cx, dy = Double(py) + 0.5 - cy
                    // Into the light's frame: u along the radial axis, v across it, in radii.
                    let u = (dx * cosA + dy * sinA) / (radius * shape.radialScale)
                    let v = (-dx * sinA + dy * cosA) / (radius * shape.tangentialScale)
                    if let cut = shape.catsEyeCut {
                        let offset = 2 - cut
                        if (u + offset) * (u + offset) + v * v > 1 { continue }
                    }
                    let channels = [(u - fringe, 0), (u, 1), (u + fringe, 2)]
                    for (shiftedU, channel) in channels {
                        let t = distance(u: shiftedU, v: v, blades: blades)
                        guard t < 1 else { continue }
                        // A slightly soft edge, as a real out-of-focus light has.
                        let edge = min(1, (1 - t) * max(1, radius * 0.08) * 1.4)
                        let value = profile(t, lens: lens) * edge * light.brightness * 0.9
                        let index = py * size + px
                        switch channel {
                        case 0: red[index] += value * light.red
                        case 1: green[index] += value * light.green
                        default: blue[index] += value * light.blue
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

    /// 0 at the centre, 1 at the edge: a circle, or a polygon with that many blades.
    static func distance(u: Double, v: Double, blades: Int) -> Double {
        let r = (u * u + v * v).squareRoot()
        guard blades >= 3 else { return r }
        let sector = 2 * Double.pi / Double(blades)
        let angle = atan2(v, u)
        let local = angle - sector * (angle / sector).rounded(.down) - sector / 2
        return r * cos(local) / cos(sector / 2)
    }
}
