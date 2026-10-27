import CameraCore
import Metal

/// A preset resolved for rendering: an optional LUT, a halation amount and a grain amount, all 0...1.
/// `MetalGrader` turns it into pixels; the LUT is uploaded to the GPU once and kept here.
final class FilmLook: @unchecked Sendable {
    let lut: LUT3D?
    let grain: Double
    let halation: Double

    /// Shared between a look and its toggled variants, so the LUT is uploaded once.
    private let upload: Upload

    private final class Upload: @unchecked Sendable {
        let lock = NSLock()
        var texture: MTLTexture?
    }

    init(lut: LUT3D?, grain: Double, halation: Double = 0) {
        self.lut = lut
        self.grain = grain
        self.halation = halation
        upload = Upload()
    }

    private init(lut: LUT3D?, grain: Double, halation: Double, upload: Upload) {
        self.lut = lut
        self.grain = grain
        self.halation = halation
        self.upload = upload
    }

    static let identity = FilmLook(lut: nil, grain: 0)

    var hasLUT: Bool { lut != nil }

    /// The same look with grain or halation switched off by the camera-screen toggles.
    func with(grain grainOn: Bool, halation halationOn: Bool) -> FilmLook {
        if grainOn, halationOn { return self }
        return FilmLook(lut: lut, grain: grainOn ? grain : 0, halation: halationOn ? halation : 0, upload: upload)
    }

    /// The LUT as a 3D half-float texture, red along x. Created on first use.
    func texture(on device: MTLDevice) -> MTLTexture? {
        guard let lut else { return nil }
        upload.lock.lock()
        defer { upload.lock.unlock() }
        if let existing = upload.texture { return existing }

        let size = lut.size
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let halves = lut.rgba.map { Float16($0) }
        halves.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, size, size, size),
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: size * 8,
                bytesPerImage: size * size * 8
            )
        }
        upload.texture = texture
        return texture
    }
}
