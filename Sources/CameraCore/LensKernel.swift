import Foundation

/// How a lens draws one out-of-focus point: where the samples of a bokeh gather fall and how much each
/// counts. The portrait blur gathers 96 of them around every background pixel, so the shape of the aperture
/// (blades, rim, cat's eye, ovality, swirl) is the shape of the blur. Grade.metal (`lensBokeh`) runs the
/// same steps on the GPU, live and for saved photos; this file is the tested copy of them.
public enum LensKernel {
    public static let sampleCount = 96
    static let goldenAngle: Float = 2.399_963_2

    /// One sample of the gather: an offset in units of the blur radius (x across, y down, both in the same
    /// pixel scale) and its weight.
    public struct Tap: Equatable, Sendable {
        public var offset: SIMD2<Float>
        public var weight: Float
    }

    /// Where in the frame the pixel being blurred is.
    public struct Spot: Equatable, Sendable {
        /// 0 at the centre, 1 at 0.55 of the frame's height from it and beyond.
        public var edge: Float
        /// Unit vector from the centre outwards, in a space where both axes have the same scale.
        public var radial: SIMD2<Float>

        public static let centre = Spot(edge: 0, radial: SIMD2(0, 1))
    }

    /// The spot for a point `uv` (0...1 across and down) of a frame `aspect` wide for its height.
    public static func spot(uv: SIMD2<Float>, aspect: Float) -> Spot {
        let centred = SIMD2((uv.x - 0.5) * aspect, uv.y - 0.5)
        let distance = (centred.x * centred.x + centred.y * centred.y).squareRoot()
        let radial = distance > 0.0001 ? centred / distance : SIMD2<Float>(0, 1)
        return Spot(edge: min(max(distance / 0.55, 0), 1), radial: radial)
    }

    /// Wider lenses with field curvature blur more towards the corners.
    public static func radiusScale(lens: LensStyle, spot: Spot) -> Float {
        1 + 0.45 * Float(lens.swirl) * spot.edge * spot.edge
    }

    /// The angle the background is twisted by at `radius` from the centre (in frame heights): the swirl.
    public static func twirlAngle(lens: LensStyle, radius: Float) -> Float {
        Float(lens.swirl) * 1.2 * radius * radius
    }

    /// Weight of a sample at `rho` of the radius (0 centre, 1 edge). A bright thin rim with a hollow centre
    /// for ring lenses; a fade to nothing at the edge for soft ones.
    public static func ringWeight(rho: Float, lens: LensStyle) -> Float {
        let rim = Float(lens.rim)
        if rim >= 0 {
            let width = Float(lens.rimWidth)
            let t = min(max((rho - (1 - width)) / max(width, 0.0001), 0), 1)
            let rimEdge = t * t * (3 - 2 * t)
            return 1 + (0.25 + 3 * rimEdge - 1) * rim
        }
        return 1 + (exp(-2.5 * rho * rho) - 1) * -rim
    }

    /// The scale that turns a disc into a polygon of `blades` sides with the same area, at angle `angle`.
    public static func polygonScale(angle: Float, blades: Int) -> Float {
        let sector = 2 * Float.pi / Float(blades)
        let local = angle - sector * (angle / sector).rounded(.down) - sector / 2
        return cos(sector / 2) / cos(local)
    }

    public static func polygonFill(blades: Int) -> Float {
        let n = Float(blades)
        let area = n / 2 * sin(2 * Float.pi / n)
        return (Float.pi / area).squareRoot()
    }

    /// Sample `index` of the gather, turned by `rotation` (a different one per pixel hides the pattern).
    /// Nil when the lens cuts the sample off, as the barrel does to the bokeh near the edges (cat's eye).
    public static func tap(index: Int, rotation: Float, lens: LensStyle, spot: Spot) -> Tap? {
        let rho = ((Float(index) + 0.5) / Float(sampleCount)).squareRoot()
        let theta = Float(index) * goldenAngle + rotation
        var u = SIMD2(cos(theta), sin(theta)) * rho
        var weight = ringWeight(rho: rho, lens: lens)

        if lens.bladeCount >= 3 {
            let scale = polygonScale(angle: atan2(u.y, u.x), blades: lens.bladeCount)
            u *= scale * polygonFill(blades: lens.bladeCount)
            weight *= scale * scale
        }

        let shift = Float(lens.catsEye) * pow(spot.edge, 1.5) * 0.9
        if shift > 0.01 {
            let half = spot.radial * (shift * 0.5)
            if length(u - half) > 1 || length(u + half) > 1 { return nil }
        }

        // Swirl pulls the bokeh out along the way round the centre.
        let stretch = 1 + 0.7 * Float(lens.swirl) * spot.edge
        if stretch != 1 {
            let tangent = SIMD2(-spot.radial.y, spot.radial.x)
            u = spot.radial * dot(u, spot.radial) + tangent * (dot(u, tangent) * stretch)
        }

        // Ovality: positive is taller, negative wider, the area kept.
        let oval = max(0.3, 1 + 0.9 * Float(lens.ovality))
        u = SIMD2(u.x / oval.squareRoot(), u.y * oval.squareRoot())
        return Tap(offset: u, weight: weight)
    }

    private static func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.x + a.y * b.y }
    private static func length(_ a: SIMD2<Float>) -> Float { dot(a, a).squareRoot() }

    /// What the sample pattern of a lens looks like, to compare lenses: how far it reaches across and down,
    /// how much of the weight sits on the rim and how many samples the cat's eye cuts at the edge.
    public struct Signature: Equatable, Sendable {
        public var width: Float
        public var height: Float
        public var rimShare: Float
        public var cutShare: Float
        public var cornerness: Float
    }

    public static func signature(of lens: LensStyle) -> Signature {
        let edge = Spot(edge: 1, radial: SIMD2(1, 0))
        var maxX: Float = 0, maxY: Float = 0
        var rim: Float = 0, total: Float = 0, cut = 0
        var corner: Float = 0
        for index in 0 ..< sampleCount {
            guard let sample = tap(index: index, rotation: 0, lens: lens, spot: .centre) else { continue }
            maxX = max(maxX, abs(sample.offset.x))
            maxY = max(maxY, abs(sample.offset.y))
            total += sample.weight
            let rho = ((Float(index) + 0.5) / Float(sampleCount)).squareRoot()
            if rho > 0.8 { rim += sample.weight }
            corner = max(corner, length(sample.offset))
            if tap(index: index, rotation: 0, lens: lens, spot: edge) == nil { cut += 1 }
        }
        return Signature(width: maxX, height: maxY, rimShare: total > 0 ? rim / total : 0,
                         cutShare: Float(cut) / Float(sampleCount), cornerness: corner)
    }
}
