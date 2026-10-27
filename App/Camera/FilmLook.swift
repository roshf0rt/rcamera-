import CameraCore
import CoreImage
import CoreImage.CIFilterBuiltins

/// A preset resolved into Core Image work: an optional LUT followed by film grain.
final class FilmLook: @unchecked Sendable {
    static let cubeColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    let hasLUT: Bool
    let grain: Double

    private let cube: CIFilter?
    private let lock = NSLock()

    init(lut: LUT3D?, grain: Double) {
        self.grain = grain
        if let lut, let filter = CIFilter(name: "CIColorCubeWithColorSpace") {
            filter.setValue(lut.size, forKey: "inputCubeDimension")
            filter.setValue(lut.float32Data, forKey: "inputCubeData")
            filter.setValue(Self.cubeColorSpace, forKey: "inputColorSpace")
            cube = filter
            hasLUT = true
        } else {
            cube = nil
            hasLUT = false
        }
    }

    static let identity = FilmLook(lut: nil, grain: 0)

    var isIdentity: Bool { !hasLUT && grain <= 0.001 }

    func apply(to image: CIImage) -> CIImage {
        if isIdentity { return image }
        lock.lock()
        defer { lock.unlock() }

        var result = image
        if let cube {
            cube.setValue(result, forKey: kCIInputImageKey)
            result = cube.outputImage ?? result
        }
        if grain > 0.001 {
            result = addGrain(to: result)
        }
        return result
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
