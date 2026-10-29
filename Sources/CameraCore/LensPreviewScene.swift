import Foundation

/// The lens picker's previews: a city at night thrown out of focus, as mood shows its lenses. Every lens
/// gets the same scene, so the previews differ only by how the lens draws a light: round or six-bladed,
/// a hollow ring or a soft disc, squeezed into a cat's eye or stretched round the centre, with coloured
/// rims. The shapes come from the lens's parameters, the ones the portrait blur uses. The app draws the bytes.
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

    /// How one light is bent by the lens at its place in the frame.
    public struct Shape: Equatable, Sendable {
        /// Scale along the line from the centre to the light.
        public var radialScale: Double
        /// Scale across that line.
        public var tangentialScale: Double
        /// Rotation of the shape, radians; the radial axis points along this angle.
        public var angle: Double
        /// How deep the cat's eye cuts into the light's outer edge, in radii; nil when it does not.
        public var catsEyeCut: Double?
    }

    /// Red signs, violet-blue neon, sodium amber, now and then a warm white window: a street at night.
    static let palette: [(Double, Double, Double)] = [
        (1.00, 0.10, 0.08), (1.00, 0.22, 0.12), (0.95, 0.16, 0.20),
        (0.36, 0.22, 1.00), (0.28, 0.26, 1.00), (0.50, 0.24, 0.95),
        (1.00, 0.58, 0.08), (1.00, 0.70, 0.18), (0.95, 0.48, 0.10),
        (1.00, 0.86, 0.70), (1.00, 0.34, 0.50),
    ]

    private struct Random {
        var state: UInt64
        /// SplitMix64, enough for a stable layout.
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    /// The scene's lights, the same for every lens: many small dim ones far away, fewer big bright ones
    /// near, over the whole frame. Deterministic.
    public static func lights(far: Int = 80, near: Int = 38, seed: UInt64 = 7) -> [Light] {
        var random = Random(state: seed)
        func light(radius: ClosedRange<Double>, brightness: ClosedRange<Double>) -> Light {
            let color = palette[Int(random.next() * Double(palette.count)) % palette.count]
            return Light(
                x: -0.06 + 1.12 * random.next(),
                y: -0.06 + 1.12 * random.next(),
                radius: radius.lowerBound + (radius.upperBound - radius.lowerBound) * random.next(),
                red: color.0,
                green: color.1,
                blue: color.2,
                brightness: brightness.lowerBound + (brightness.upperBound - brightness.lowerBound) * pow(random.next(), 1.5)
            )
        }
        let back = (0 ..< far).map { _ in light(radius: 0.03 ... 0.06, brightness: 0.15 ... 0.6) }
        let front = (0 ..< near).map { _ in light(radius: 0.06 ... 0.12, brightness: 0.25 ... 1.0) }
        return back + front
    }

    /// Big, faint, out-of-focus shapes behind the lights, so the night is not flat black.
    static func haze(seed: UInt64 = 3) -> [Light] {
        var random = Random(state: seed)
        let tones: [(Double, Double, Double)] = [(0.5, 0.18, 0.1), (0.18, 0.16, 0.45), (0.45, 0.3, 0.12), (0.12, 0.2, 0.22)]
        return (0 ..< 7).map { index in
            let tone = tones[index % tones.count]
            return Light(
                x: random.next(),
                y: random.next(),
                radius: 0.22 + 0.2 * random.next(),
                red: tone.0,
                green: tone.1,
                blue: tone.2,
                brightness: 0.05 + 0.07 * random.next()
            )
        }
    }

    /// Cat's eye squeezes lights towards the edges radially, swirl stretches them around the centre,
    /// ovality makes them taller or wider everywhere.
    public static func shape(of light: Light, lens: LensStyle) -> Shape {
        let dx = light.x - 0.5, dy = light.y - 0.5
        let distance = min(1, (dx * dx + dy * dy).squareRoot() / 0.7071)
        let angle = distance > 0.0001 ? atan2(dy, dx) : 0
        var radial = 1 - 0.2 * lens.catsEye * distance * distance
        var tangential = 1 + 0.7 * lens.swirl * distance * distance
        // Ovality acts on the frame's vertical axis; split it into the radial and tangential parts.
        let vertical = 1 + 0.6 * lens.ovality
        let sinA = abs(sin(angle)), cosA = abs(cos(angle))
        radial *= vertical * sinA + cosA
        tangential *= vertical * cosA + sinA
        let depth = 0.6 * lens.catsEye * distance * distance
        let cut = depth > 0.02 ? depth : nil
        return Shape(radialScale: max(0.3, radial), tangentialScale: max(0.3, tangential), angle: angle, catsEyeCut: cut)
    }

    /// Opacity of a light at a fraction `t` of its radius (0 centre, 1 edge): a bright rim and a darker
    /// centre for ring lenses, a long fade for negative rims, a nearly even disc in between.
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
        let body = 1 - 0.5 * lens.rim
        guard t > rimStart else { return body * (0.92 + 0.08 * t) }
        // The rim swells towards the edge instead of stepping up.
        let u = (t - rimStart) / max(lens.rimWidth, 0.01)
        let rimLevel = min(1.25, body + 0.6 * lens.rim + 0.12)
        return body + (rimLevel - body) * u * u
    }

    /// 0 at the centre, 1 at the edge: a circle, or a polygon with that many blades.
    static func distance(u: Double, v: Double, blades: Int) -> Double {
        let r = (u * u + v * v).squareRoot()
        guard blades >= 3 else { return r }
        let sector = 2 * Double.pi / Double(blades)
        let angle = atan2(v, u) + sector / 4
        let local = angle - sector * (angle / sector).rounded(.down) - sector / 2
        return r * cos(local) / cos(sector / 2)
    }

    /// RGBA bytes, `size` × `size`. Some tens of milliseconds per lens at 256; call off the main thread.
    public static func render(lens: LensStyle, size: Int) -> [UInt8] {
        guard size > 0 else { return [] }
        let side = Double(size)
        var red = [Double](repeating: 0, count: size * size)
        var green = red, blue = red

        // The haze: wide soft blobs, the same for every lens.
        for blob in haze() {
            let cx = blob.x * side, cy = blob.y * side, radius = blob.radius * side
            let x0 = max(0, Int(cx - radius)), x1 = min(size - 1, Int(cx + radius))
            let y0 = max(0, Int(cy - radius)), y1 = min(size - 1, Int(cy + radius))
            guard x0 <= x1, y0 <= y1 else { continue }
            for py in y0 ... y1 {
                for px in x0 ... x1 {
                    let dx = (Double(px) + 0.5 - cx) / radius, dy = (Double(py) + 0.5 - cy) / radius
                    let d2 = dx * dx + dy * dy
                    guard d2 < 1 else { continue }
                    let value = blob.brightness * (1 - d2) * (1 - d2)
                    let index = py * size + px
                    red[index] += value * blob.red
                    green[index] += value * blob.green
                    blue[index] += value * blob.blue
                }
            }
        }

        // Fringing splits each light's red and blue rims apart along its radial axis.
        let fringe = 0.09 * lens.fringing
        let blades = lens.bladeCount
        // How much of the radius the edge takes to fade: a real out-of-focus light is never cut sharp.
        let softEdge = 0.16

        for light in lights() {
            let shape = shape(of: light, lens: lens)
            let radius = light.radius * side
            let reach = radius * max(shape.radialScale, shape.tangentialScale) * (1 + fringe) + 2
            let cx = light.x * side, cy = light.y * side
            let cosA = cos(shape.angle), sinA = sin(shape.angle)
            let x0 = max(0, Int(cx - reach)), x1 = min(size - 1, Int(cx + reach))
            let y0 = max(0, Int(cy - reach)), y1 = min(size - 1, Int(cy + reach))
            guard x0 <= x1, y0 <= y1 else { continue }
            let channels: [(shift: Double, tint: Double)] = [(-fringe, light.red), (0, light.green), (fringe, light.blue)]

            for py in y0 ... y1 {
                for px in x0 ... x1 {
                    let dx = Double(px) + 0.5 - cx, dy = Double(py) + 0.5 - cy
                    // Into the light's frame: u along the radial axis, v across it, in radii.
                    let u = (dx * cosA + dy * sinA) / (radius * shape.radialScale)
                    let v = (-dx * sinA + dy * cosA) / (radius * shape.tangentialScale)
                    var cut = 1.0
                    if let depth = shape.catsEyeCut {
                        // The cat's eye: the light seen through a second, wider opening set towards the
                        // centre of the frame, which clips the outer edge.
                        let opening = 1.6
                        let offset = opening - 1 + depth
                        let d = ((u + offset) * (u + offset) + v * v).squareRoot() / opening
                        cut = min(1, max(0, (1 - d) * opening / softEdge))
                        if cut <= 0 { continue }
                    }
                    let index = py * size + px
                    for (channel, (shift, tint)) in channels.enumerated() {
                        let t = distance(u: u - shift, v: v, blades: blades)
                        guard t < 1 else { continue }
                        let edge = min(1, (1 - t) / softEdge)
                        let value = profile(t, lens: lens) * edge * cut * light.brightness * 0.6 * tint
                        switch channel {
                        case 0: red[index] += value
                        case 1: green[index] += value
                        default: blue[index] += value
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
                let vignette = max(0, 1 - (0.25 + lens.vignette * 0.6) * pow(r2, 1.3))
                let index = py * size + px
                // A deep warm-black night behind everything.
                let base = (0.012, 0.008, 0.012)
                let rgb = [red[index] + base.0, green[index] + base.1, blue[index] + base.2].map { value -> UInt8 in
                    // Soft clip, so stacked lights glow instead of going flat white.
                    let mapped = (1 - exp(-1.6 * value * vignette)) / (1 - exp(-1.6))
                    return UInt8(min(max(pow(mapped, 1.35) * 255, 0), 255))
                }
                pixels[index * 4] = rgb[0]
                pixels[index * 4 + 1] = rgb[1]
                pixels[index * 4 + 2] = rgb[2]
            }
        }
        return pixels
    }
}
