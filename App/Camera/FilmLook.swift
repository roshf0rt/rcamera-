import CameraCore
import CoreImage
import CoreImage.CIFilterBuiltins

/// A preset resolved into Core Image work: an optional LUT, then halation, then film grain.
///
/// Two ways to apply the LUT, because the inputs differ:
/// - `raw: true` is for video frames. The numbers in the buffer go straight into the LUT with no color
///   management. This matters for Apple Log, where Core Image would otherwise read the buffer's color tags
///   and decode the log curve before the LUT sees it.
/// - `raw: false` is for photos in a color-managed context. The cube converts to sRGB first, then back.
final class FilmLook: @unchecked Sendable {
    static let cubeColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    let hasLUT: Bool
    let grain: Double
    let halation: Double

    private let lut: LUT3D?
    private let lock = NSLock()
    private var rawCube: CIFilter?
    private var managedCube: CIFilter?

    init(lut: LUT3D?, grain: Double, halation: Double = 0) {
        self.lut = lut
        self.hasLUT = lut != nil
        self.grain = grain
        self.halation = halation
    }

    static let identity = FilmLook(lut: nil, grain: 0)

    var isIdentity: Bool { !hasLUT && grain <= 0.001 && halation <= 0.001 }

    func apply(to image: CIImage, raw: Bool) -> CIImage {
        if isIdentity { return image }
        lock.lock()
        defer { lock.unlock() }

        var result = image
        if let cube = cubeFilter(raw: raw) {
            cube.setValue(result, forKey: kCIInputImageKey)
            result = cube.outputImage ?? result
        }
        if halation > 0.001 { result = addHalation(to: result) }
        if grain > 0.001 { result = addGrain(to: result) }
        return result
    }

    private func cubeFilter(raw: Bool) -> CIFilter? {
        guard let lut else { return nil }
        if raw {
            if rawCube == nil, let filter = CIFilter(name: "CIColorCube") {
                filter.setValue(lut.size, forKey: "inputCubeDimension")
                filter.setValue(lut.float32Data, forKey: "inputCubeData")
                rawCube = filter
            }
            return rawCube
        }
        if managedCube == nil, let filter = CIFilter(name: "CIColorCubeWithColorSpace") {
            filter.setValue(lut.size, forKey: "inputCubeDimension")
            filter.setValue(lut.float32Data, forKey: "inputCubeData")
            filter.setValue(Self.cubeColorSpace, forKey: "inputColorSpace")
            managedCube = filter
        }
        return managedCube
    }

    /// A soft red-orange glow around bright areas, as light scatters in film.
    private func addHalation(to image: CIImage) -> CIImage {
        let extent = image.extent
        let scale = max(1.0, extent.width / 1080.0)
        let amount = CGFloat(halation)

        let highlights = image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 3.5, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 3.5, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 3.5, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: -2.5, y: -2.5, z: -2.5, w: 0),
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ])

        // Blur at a quarter of the size: the glow is soft anyway and this is much cheaper.
        let down: CGFloat = 0.25
        let glow = highlights
            .transformed(by: CGAffineTransform(scaleX: down, y: down))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(16 * scale * down))
            .transformed(by: CGAffineTransform(scaleX: 1 / down, y: 1 / down))
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amount * 0.35, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amount * 0.12, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])

        return glow
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    private func addGrain(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }

        // Keep grain size roughly constant relative to the frame, whatever the resolution.
        let scale = max(1.0, extent.width / 1080.0)
        let strength = CGFloat(grain) * 0.35
        let bias = 0.5 - 1.5 * strength
        let shifted = noise
            .transformed(by: CGAffineTransform(translationX: .random(in: 0 ... 512), y: .random(in: 0 ... 512)))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let gray = shifted
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: strength, y: strength, z: strength, w: 0),
                "inputGVector": CIVector(x: strength, y: strength, z: strength, w: 0),
                "inputBVector": CIVector(x: strength, y: strength, z: strength, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
            ])
            .cropped(to: extent)

        return gray
            .applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }
}
