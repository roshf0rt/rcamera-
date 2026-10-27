import CameraCore
import CoreImage
import CoreVideo
import Metal
import MetalPerformanceShaders

/// Mirrors `GradeParams` in Grade.metal. Scalars only, so Swift and Metal agree on the layout.
private struct GradeParams {
    var originX: Int32 = 0
    var originY: Int32 = 0
    var width: Int32 = 0
    var height: Int32 = 0
    var mirror: Int32 = 0
    var inputKind: Int32 = 0
    var chromaShiftX: Int32 = 0
    var chromaShiftY: Int32 = 0
    var hasLUT: Int32 = 0
    var lutScale: Float = 1
    var lutOffset: Float = 0
    var grain: Float = 0
    var grainOffsetX: Float = 0
    var grainOffsetY: Float = 0
    var grainScale: Float = 1
    var halation: Float = 0
}

/// Applies a `FilmLook` on the GPU in one pass, like Lampa's Ironstone: camera pixel, LUT, halation, grain.
///
/// Live frames, recorded video and saved photos all go through `grade`, so they look the same.
/// Halation needs a highlight mask: it is built at a quarter of the size, blurred with MPS, then sampled.
final class MetalGrader: @unchecked Sendable {
    static let shared = MetalGrader()

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let gradeState: MTLComputePipelineState
    private let maskState: MTLComputePipelineState
    private let textureCache: CVMetalTextureCache
    private let grainTextures: [MTLTexture]
    private let emptyLUT: MTLTexture
    private let emptyMask: MTLTexture

    private let lock = NSLock()
    private var maskCache: [Int: (raw: MTLTexture, blurred: MTLTexture)] = [:]
    private var blurCache: [Int: MPSImageGaussianBlur] = [:]

    static let grainTextureSize = 512
    private static let maskDownscale = 4

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let gradeFunction = library.makeFunction(name: "grade"),
              let maskFunction = library.makeFunction(name: "halationMask"),
              let gradeState = try? device.makeComputePipelineState(function: gradeFunction),
              let maskState = try? device.makeComputePipelineState(function: maskFunction)
        else { return nil }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard let cache else { return nil }

        var grains: [MTLTexture] = []
        for seed in 1 ... 4 {
            let values = FilmMath.grainTexture(size: Self.grainTextureSize, seed: UInt64(seed) &* 0x5DEECE66D)
            guard let texture = Self.makeTexture2D(device: device, values: values, size: Self.grainTextureSize) else { return nil }
            grains.append(texture)
        }

        guard let emptyLUT = Self.makeEmptyLUT(device: device),
              let emptyMask = Self.makeTexture2D(device: device, values: [0], size: 1)
        else { return nil }

        self.device = device
        self.queue = queue
        self.gradeState = gradeState
        self.maskState = maskState
        self.textureCache = cache
        self.grainTextures = grains
        self.emptyLUT = emptyLUT
        self.emptyMask = emptyMask
    }

    // MARK: Grading

    /// Renders `crop` of `source` with `look` into `output`, whose size must match the crop.
    /// `source` may be BGRA or 10-bit bi-planar Y'CbCr (the camera's Apple Log stream).
    /// `cachedMasks` reuses mask textures between calls; only the capture queue should pass true.
    @discardableResult
    func grade(source: CVPixelBuffer, crop: CropRect, mirror: Bool, look: FilmLook, into output: CVPixelBuffer, cachedMasks: Bool = true) -> Bool {
        var params = GradeParams()
        var holders: [CVMetalTexture] = []

        let luma: MTLTexture
        let chroma: MTLTexture
        switch CVPixelBufferGetPixelFormatType(source) {
        case kCVPixelFormatType_32BGRA:
            guard let texture = texture(from: source, plane: nil, format: .bgra8Unorm, holders: &holders) else { return false }
            luma = texture
            chroma = texture
        case kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            guard let y = texture(from: source, plane: 0, format: .r16Unorm, holders: &holders),
                  let c = texture(from: source, plane: 1, format: .rg16Unorm, holders: &holders)
            else { return false }
            luma = y
            chroma = c
            params.inputKind = 1
            params.chromaShiftX = 1
            params.chromaShiftY = CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? 1 : 0
        default:
            return false
        }
        guard let destination = texture(from: output, plane: nil, format: .bgra8Unorm, holders: &holders),
              destination.width == crop.width, destination.height == crop.height
        else { return false }

        params.originX = Int32(crop.x)
        params.originY = Int32(crop.y)
        params.width = Int32(crop.width)
        params.height = Int32(crop.height)
        params.mirror = mirror ? 1 : 0

        let lut = look.texture(on: device)
        if let lut {
            let size = Float(lut.width)
            params.hasLUT = 1
            params.lutScale = (size - 1) / size
            params.lutOffset = 0.5 / size
        }

        params.grain = FilmMath.grainIntensity(look.grain)
        // One grain texel per output pixel at 1080 across, scaled up for bigger frames, so the grain
        // looks the same in the viewfinder, in 4K and in a 12 MP photo.
        params.grainScale = max(1, Float(min(crop.width, crop.height)) / 1080)
        let grainSpan = Float(Self.grainTextureSize) * params.grainScale
        params.grainOffsetX = Float.random(in: 0 ..< grainSpan)
        params.grainOffsetY = Float.random(in: 0 ..< grainSpan)
        let grain = grainTextures.randomElement() ?? emptyMask

        params.halation = FilmMath.halationStrength(look.halation)

        guard let commandBuffer = queue.makeCommandBuffer() else { return false }

        var glow = emptyMask
        if params.halation > 0,
           let masks = masks(width: crop.width, height: crop.height, cached: cachedMasks),
           let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(maskState)
            encoder.setTexture(luma, index: 0)
            encoder.setTexture(chroma, index: 1)
            encoder.setTexture(lut ?? emptyLUT, index: 2)
            encoder.setTexture(masks.raw, index: 3)
            encoder.setBytes(&params, length: MemoryLayout<GradeParams>.stride, index: 0)
            dispatch(encoder, state: maskState, width: masks.raw.width, height: masks.raw.height)
            encoder.endEncoding()

            blur(for: masks.raw).encode(commandBuffer: commandBuffer, sourceTexture: masks.raw, destinationTexture: masks.blurred)
            glow = masks.blurred
        } else {
            params.halation = 0
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(gradeState)
        encoder.setTexture(luma, index: 0)
        encoder.setTexture(chroma, index: 1)
        encoder.setTexture(lut ?? emptyLUT, index: 2)
        encoder.setTexture(glow, index: 3)
        encoder.setTexture(grain, index: 4)
        encoder.setTexture(destination, index: 5)
        encoder.setBytes(&params, length: MemoryLayout<GradeParams>.stride, index: 0)
        dispatch(encoder, state: gradeState, width: crop.width, height: crop.height)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        withExtendedLifetime(holders) {}
        return commandBuffer.status == .completed
    }

    /// Grades a still image. The image is rendered to sRGB first, the space the LUTs expect.
    func grade(image: CIImage, look: FilmLook, context: CIContext) -> CIImage? {
        let extent = image.extent.integral
        let width = Int(extent.width) & ~1
        let height = Int(extent.height) & ~1
        guard width > 0, height > 0,
              let input = Self.makePixelBuffer(width: width, height: height),
              let output = Self.makePixelBuffer(width: width, height: height),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        let placed = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        context.render(placed, to: input, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: sRGB)
        let crop = CropRect(x: 0, y: 0, width: width, height: height)
        guard grade(source: input, crop: crop, mirror: false, look: look, into: output, cachedMasks: false) else { return nil }
        return CIImage(cvPixelBuffer: output, options: [.colorSpace: sRGB])
    }

    // MARK: Helpers

    static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        return buffer
    }

    private func texture(from buffer: CVPixelBuffer, plane: Int?, format: MTLPixelFormat, holders: inout [CVMetalTexture]) -> MTLTexture? {
        let width = plane.map { CVPixelBufferGetWidthOfPlane(buffer, $0) } ?? CVPixelBufferGetWidth(buffer)
        let height = plane.map { CVPixelBufferGetHeightOfPlane(buffer, $0) } ?? CVPixelBufferGetHeight(buffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil, format, width, height, plane ?? 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        holders.append(cvTexture)
        return texture
    }

    private func masks(width: Int, height: Int, cached: Bool) -> (raw: MTLTexture, blurred: MTLTexture)? {
        let maskWidth = max(8, width / Self.maskDownscale)
        let maskHeight = max(8, height / Self.maskDownscale)
        let key = maskWidth << 16 | maskHeight
        if cached {
            lock.lock()
            defer { lock.unlock() }
            if let existing = maskCache[key] { return existing }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: maskWidth, height: maskHeight, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let raw = device.makeTexture(descriptor: descriptor),
              let blurred = device.makeTexture(descriptor: descriptor)
        else { return nil }
        if cached {
            lock.lock()
            maskCache[key] = (raw, blurred)
            lock.unlock()
        }
        return (raw, blurred)
    }

    /// The glow spreads about 1.5% of the short side, whatever the resolution.
    private func blur(for mask: MTLTexture) -> MPSImageGaussianBlur {
        let sigma = max(1.5, Float(min(mask.width, mask.height)) * 0.015)
        let key = Int((sigma * 4).rounded())
        lock.lock()
        defer { lock.unlock() }
        if let existing = blurCache[key] { return existing }
        let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
        blur.edgeMode = .clamp
        blurCache[key] = blur
        return blur
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, state: MTLComputePipelineState, width: Int, height: Int) {
        let threadWidth = state.threadExecutionWidth
        let threadHeight = max(1, state.maxTotalThreadsPerThreadgroup / threadWidth)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        )
    }

    private static func makeTexture2D(device: MTLDevice, values: [Float], size: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let halves = values.map { Float16($0) }
        halves.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: size * 2)
        }
        return texture
    }

    private static func makeEmptyLUT(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = 2
        descriptor.height = 2
        descriptor.depth = 2
        descriptor.usage = .shaderRead
        return device.makeTexture(descriptor: descriptor)
    }
}
