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
    var hasPreviousLUT: Int32 = 0
    var previousLutScale: Float = 1
    var previousLutOffset: Float = 0
    var previousMix: Float = 0
    var exposure: Float = 1
    var temp: Float = 0
    var tint: Float = 0
    var contrast: Float = 1
    var shadows: Float = 0
    var midpoint: Float = 0
    var highlights: Float = 0
    var fade: Float = 0
    var shoulderKnee: Float = 1
    var shadowLift: Float = 0
    var crush: Float = 0
    var saturation: Float = 1
    var hueCos: Float = 1
    var hueSin: Float = 0
    var hasHue: Int32 = 0
    var filmStrength: Float = 1
    var bloom: Float = 0
    var sharpness: Float = 0
    var fringe: Float = 0
    var hasPortrait: Int32 = 0
    var depthRotated: Int32 = 0
    var sourceWidth: Int32 = 1
    var sourceHeight: Int32 = 1
    var depthFocus: Float = 1
    var swirl: Float = 0
    var lensVignette: Float = 0
    var bokehBoost: Float = 0
    var blades: Int32 = 0
    var catsEye: Float = 0
    var ovality: Float = 0
    var rim: Float = 0
    var rimWidth: Float = 0
    var fringing: Float = 0
    var bokehRadius: Float = 0
    var assist: Int32 = 0
    var stripePhase: Int32 = 0
    var zebraLevel: Float = 0.95
    var peakThreshold: Float = 0.1
    var waveColumns: Int32 = 1
    var waveLevels: Int32 = 2
    var waveStepX: Int32 = 1
    var waveStepY: Int32 = 1
    var waveTurn: Int32 = 0

    /// How `lens` draws the background, with a blur radius of `radius` pixels in the small bokeh texture.
    mutating func setLens(_ lens: LensStyle, radius: Float) {
        swirl = Float(lens.swirl)
        lensVignette = Float(lens.vignette)
        bokehBoost = Float(lens.highlightBoost)
        blades = Int32(lens.bladeCount)
        catsEye = Float(lens.catsEye)
        ovality = Float(lens.ovality)
        rim = Float(lens.rim)
        rimWidth = Float(lens.rimWidth)
        fringing = Float(lens.fringing)
        bokehRadius = radius
    }
}

/// The live portrait background for one frame: the depth map and how the lens draws it.
struct PortraitPass {
    var depth: CVPixelBuffer
    /// The depth map is portrait like the frames (its connection was turned); otherwise landscape.
    var depthRotated: Bool
    /// The subject's disparity, from the middle of the depth map.
    var focus: Float
    /// 1 at f/2.8, stronger wide open.
    var strength: Float
    var lens: LensStyle
}

/// The viewfinder's aids for one frame (`ExposureAssist`). Only the viewfinder stream asks for them.
struct AssistPass: Equatable {
    var zebra = false
    var falseColor = false
    var peaking = false
    /// Draw the waveform picture (`FrameHub` shows it).
    var waveform = false
    /// How the phone is held (`DeviceOrientation.quarterTurns`), so the waveform runs across the picture as seen.
    var quarterTurns = 0
    /// Count the graded picture this frame, for the waveform; `takeWaveform` returns the counts.
    var counts = false
    /// Frame counter, so the zebra stripes crawl.
    var phase = 0

    var isEmpty: Bool { !zebra && !falseColor && !peaking && !waveform }
}

/// Applies a `FilmLook` on the GPU in one pass, like Lampa's Ironstone: camera pixel, LUT, halation, grain.
///
/// Live frames, recorded video and saved photos all go through `grade`, so they look the same.
/// Halation needs a highlight mask: it is built at a quarter of the size, blurred with MPS, then sampled.
final class MetalGrader: @unchecked Sendable {
    static let shared = MetalGrader()

    /// A grader of its own, for redeveloping videos in the background without sharing the viewfinder's.
    static func makeForBackground() -> MetalGrader? { MetalGrader() }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let gradeState: MTLComputePipelineState
    private let maskState: MTLComputePipelineState
    private let bokehState: MTLComputePipelineState
    private let lensState: MTLComputePipelineState
    private let packState: MTLComputePipelineState
    private let emptyColor: MTLTexture
    private var bokehCache: [Int: BokehTargets] = [:]
    private let textureCache: CVMetalTextureCache
    private let grainTextures: [MTLTexture]
    private let emptyLUT: MTLTexture
    private let emptyMask: MTLTexture

    private let lock = NSLock()
    /// Waveform counts, written by the grade kernel; one at a time, for the viewfinder.
    private var waveBuffer: MTLBuffer?
    private let emptyWave: MTLBuffer
    private var latestWaveform: Waveform?
    static let waveColumns = 128
    static let waveLevels = 64
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
              let bokehFunction = library.makeFunction(name: "bokehSource"),
              let lensFunction = library.makeFunction(name: "lensBokeh"),
              let packFunction = library.makeFunction(name: "packPortrait"),
              let gradeState = try? device.makeComputePipelineState(function: gradeFunction),
              let maskState = try? device.makeComputePipelineState(function: maskFunction),
              let bokehState = try? device.makeComputePipelineState(function: bokehFunction),
              let lensState = try? device.makeComputePipelineState(function: lensFunction),
              let packState = try? device.makeComputePipelineState(function: packFunction)
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

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        colorDescriptor.usage = .shaderRead
        guard let emptyWave = device.makeBuffer(length: 16, options: .storageModeShared),
              let emptyLUT = Self.makeEmptyLUT(device: device),
              let emptyMask = Self.makeTexture2D(device: device, values: [0], size: 1),
              let emptyColor = device.makeTexture(descriptor: colorDescriptor)
        else { return nil }

        self.device = device
        self.queue = queue
        self.gradeState = gradeState
        self.maskState = maskState
        self.bokehState = bokehState
        self.lensState = lensState
        self.packState = packState
        self.emptyColor = emptyColor
        self.textureCache = cache
        self.grainTextures = grains
        self.emptyLUT = emptyLUT
        self.emptyMask = emptyMask
        self.emptyWave = emptyWave
    }

    // MARK: Grading

    /// Renders `crop` of `source` with `look` into `output`, whose size must match the crop.
    /// `source` may be BGRA or 10-bit bi-planar Y'CbCr (the camera's Apple Log stream).
    /// `cachedMasks` reuses mask textures between calls; only the capture queue should pass true.
    /// `previous` with `previousMix` above 0 blends in another look's LUT, for a crossfade between presets.
    @discardableResult
    func grade(
        source: CVPixelBuffer,
        crop: CropRect,
        mirror: Bool,
        look: FilmLook,
        into output: CVPixelBuffer,
        cachedMasks: Bool = true,
        previous: FilmLook? = nil,
        previousMix: Float = 0,
        portrait: PortraitPass? = nil,
        assist: AssistPass? = nil
    ) -> Bool {
        var params = GradeParams()
        var holders: [CVMetalTexture] = []

        let luma: MTLTexture
        let chroma: MTLTexture
        switch CVPixelBufferGetPixelFormatType(source) {
        case kCVPixelFormatType_32BGRA:
            guard let texture = texture(from: source, plane: nil, format: .bgra8Unorm, holders: &holders) else { return false }
            luma = texture
            chroma = texture
        case kCVPixelFormatType_64RGBAHalf:
            guard let texture = texture(from: source, plane: nil, format: .rgba16Float, holders: &holders) else { return false }
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
        let outputFormat: MTLPixelFormat = CVPixelBufferGetPixelFormatType(output) == kCVPixelFormatType_64RGBAHalf ? .rgba16Float : .bgra8Unorm
        guard let destination = texture(from: output, plane: nil, format: outputFormat, holders: &holders),
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

        var previousLUT: MTLTexture?
        if let previous, previousMix > 0 {
            params.previousMix = min(previousMix, 1)
            previousLUT = previous.texture(on: device)
            if let previousLUT {
                let size = Float(previousLUT.width)
                params.hasPreviousLUT = 1
                params.previousLutScale = (size - 1) / size
                params.previousLutOffset = 0.5 / size
            }
        }

        params.grain = FilmMath.grainIntensity(look.grain)
        // One grain texel per output pixel at 1080 across, scaled up for bigger frames, so the grain
        // looks the same in the viewfinder, in 4K and in a 12 MP photo. Grain size scales it further.
        let regulators = RegulatorUniforms(look.adjustments)
        params.grainScale = Float(max(1, Double(min(crop.width, crop.height)) / 1080) * regulators.grainSizeScale)
        params.exposure = Float(regulators.exposure)
        params.temp = Float(regulators.temp)
        params.tint = Float(regulators.tint)
        params.contrast = Float(regulators.contrast)
        params.shadows = Float(regulators.shadows)
        params.midpoint = Float(regulators.midpoint)
        params.highlights = Float(regulators.highlights)
        params.fade = Float(regulators.fade)
        params.shoulderKnee = Float(regulators.shoulderKnee)
        params.shadowLift = Float(regulators.shadowLift)
        params.crush = Float(regulators.crush)
        params.saturation = Float(regulators.saturation)
        params.hueCos = Float(regulators.hueCos)
        params.hueSin = Float(regulators.hueSin)
        params.hasHue = regulators.hasHue ? 1 : 0
        params.filmStrength = Float(regulators.filmStrength)
        params.bloom = Float(regulators.bloom)
        params.sharpness = Float(regulators.sharpness)
        params.fringe = Float(regulators.fringe)
        let grainSpan = Float(Self.grainTextureSize) * params.grainScale
        params.grainOffsetX = Float.random(in: 0 ..< grainSpan)
        params.grainOffsetY = Float.random(in: 0 ..< grainSpan)
        let grain = grainTextures.randomElement() ?? emptyMask

        params.halation = FilmMath.halationStrength(look.halation)
        // Bloom reuses the halation mask, so it needs the mask even when halation is off.
        let needsGlow = params.halation > 0 || params.bloom > 0

        guard let commandBuffer = queue.makeCommandBuffer() else { return false }

        var glow = emptyMask
        if needsGlow,
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

            blur(for: masks.raw, cached: cachedMasks).encode(commandBuffer: commandBuffer, sourceTexture: masks.raw, destinationTexture: masks.blurred)
            glow = masks.blurred
        } else {
            params.halation = 0
            params.bloom = 0
        }

        var depthTexture = emptyMask
        var bokehTexture = emptyColor
        if let portrait,
           let depth = texture(from: portrait.depth, plane: nil, format: .r16Float, holders: &holders),
           let targets = bokehTargets(width: crop.width, height: crop.height, cached: cachedMasks),
           let encoder = commandBuffer.makeComputeCommandEncoder() {
            params.hasPortrait = 1
            params.depthRotated = portrait.depthRotated ? 1 : 0
            params.sourceWidth = Int32(CVPixelBufferGetWidth(source))
            params.sourceHeight = Int32(CVPixelBufferGetHeight(source))
            params.depthFocus = portrait.focus
            let radius = Self.bokehRadius(width: targets.raw.width, height: targets.raw.height, strength: portrait.strength)
            params.setLens(portrait.lens, radius: radius)
            encoder.setComputePipelineState(bokehState)
            encoder.setTexture(luma, index: 0)
            encoder.setTexture(chroma, index: 1)
            encoder.setTexture(lut ?? emptyLUT, index: 2)
            encoder.setTexture(targets.raw, index: 3)
            encoder.setTexture(depth, index: 4)
            encoder.setBytes(&params, length: MemoryLayout<GradeParams>.stride, index: 0)
            dispatch(encoder, state: bokehState, width: targets.raw.width, height: targets.raw.height)
            encoder.endEncoding()
            encodeLensBokeh(commandBuffer, from: targets.raw, through: targets.gathered, into: targets.smooth, params: &params, cached: cachedMasks)
            depthTexture = depth
            bokehTexture = targets.smooth
        }

        var wave = emptyWave
        var waveSamples = 0
        if let assist, !assist.isEmpty {
            params.assist = (assist.zebra ? 1 : 0) | (assist.falseColor ? 2 : 0) | (assist.peaking ? 4 : 0)
            params.stripePhase = Int32(assist.phase % 16)
            params.zebraLevel = Float(ExposureAssist.zebraLevel)
            // Apple Log is flat, so its edges are fainter.
            params.peakThreshold = params.inputKind == 1 ? 0.06 : 0.1
            if assist.counts, let buffer = waveformBuffer() {
                params.assist |= 8
                params.waveColumns = Int32(Self.waveColumns)
                params.waveLevels = Int32(Self.waveLevels)
                params.waveTurn = Int32(assist.quarterTurns)
                // About three samples per column along the columns, 96 across them.
                let alongX = assist.quarterTurns == 0
                let along = alongX ? crop.width : crop.height, across = alongX ? crop.height : crop.width
                let stepAlong = Int32(max(1, along / (Self.waveColumns * 3))), stepAcross = Int32(max(1, across / 96))
                params.waveStepX = alongX ? stepAlong : stepAcross
                params.waveStepY = alongX ? stepAcross : stepAlong
                memset(buffer.contents(), 0, buffer.length)
                wave = buffer
                let sampledX = (crop.width + Int(params.waveStepX) - 1) / Int(params.waveStepX)
                let sampledY = (crop.height + Int(params.waveStepY) - 1) / Int(params.waveStepY)
                waveSamples = max(1, sampledX * sampledY / Self.waveColumns)
            }
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(gradeState)
        encoder.setTexture(luma, index: 0)
        encoder.setTexture(chroma, index: 1)
        encoder.setTexture(lut ?? emptyLUT, index: 2)
        encoder.setTexture(glow, index: 3)
        encoder.setTexture(grain, index: 4)
        encoder.setTexture(destination, index: 5)
        encoder.setTexture(previousLUT ?? emptyLUT, index: 6)
        encoder.setTexture(depthTexture, index: 7)
        encoder.setTexture(bokehTexture, index: 8)
        encoder.setBytes(&params, length: MemoryLayout<GradeParams>.stride, index: 0)
        encoder.setBuffer(wave, offset: 0, index: 1)
        dispatch(encoder, state: gradeState, width: crop.width, height: crop.height)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        withExtendedLifetime(holders) {}
        let completed = commandBuffer.status == .completed
        if completed, waveSamples > 0 {
            let count = Self.waveColumns * Self.waveLevels
            let flat = Array(UnsafeBufferPointer(start: wave.contents().assumingMemoryBound(to: UInt32.self), count: count))
            let measured = Waveform(columns: Self.waveColumns, levels: Self.waveLevels, flat: flat, samplesPerColumn: waveSamples)
            lock.lock()
            latestWaveform = measured
            lock.unlock()
        }
        return completed
    }

    /// The waveform counted by the last viewfinder frame that asked for one, once.
    func takeWaveform() -> Waveform? {
        lock.lock()
        defer { lock.unlock() }
        let waveform = latestWaveform
        latestWaveform = nil
        return waveform
    }

    private func waveformBuffer() -> MTLBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if let waveBuffer { return waveBuffer }
        let length = Self.waveColumns * Self.waveLevels * MemoryLayout<UInt32>.stride
        waveBuffer = device.makeBuffer(length: length, options: .storageModeShared)
        return waveBuffer
    }

    /// Largest still graded in half float. Above it (48 MP) two half-float buffers would cost over 700 MB,
    /// so those are graded in 8 bits like the viewfinder.
    static let halfFloatPixelLimit = 25_000_000

    /// Grades a still image. The image is rendered with the sRGB curve first, the encoding the LUTs expect.
    /// Up to `halfFloatPixelLimit` it is rendered in half float and extended sRGB: shadows keep their
    /// gradations and a developed RAW keeps its highlights above white for the dynamic-range roll-off.
    func grade(image: CIImage, look: FilmLook, context: CIContext) -> CIImage? {
        let extent = image.extent.integral
        let width = Int(extent.width) & ~1
        let height = Int(extent.height) & ~1
        let halfFloat = width * height <= Self.halfFloatPixelLimit
        let format = halfFloat ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        guard width > 0, height > 0,
              let input = Self.makePixelBuffer(width: width, height: height, format: format),
              let output = Self.makePixelBuffer(width: width, height: height, format: format),
              let space = CGColorSpace(name: halfFloat ? CGColorSpace.extendedSRGB : CGColorSpace.sRGB)
        else { return nil }

        let placed = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        context.render(placed, to: input, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: space)
        let crop = CropRect(x: 0, y: 0, width: width, height: height)
        guard grade(source: input, crop: crop, mirror: false, look: look, into: output, cachedMasks: false) else { return nil }
        return CIImage(cvPixelBuffer: output, options: [.colorSpace: space])
    }

    // MARK: Helpers

    static func makePixelBuffer(width: Int, height: Int, format: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, format, attributes as CFDictionary, &buffer)
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

    /// The textures of the portrait background at a quarter of the frame: the graded picture with the mask
    /// in alpha, the lens's gather of it, and that gather lightly smoothed.
    private struct BokehTargets {
        var raw: MTLTexture
        var gathered: MTLTexture
        var smooth: MTLTexture
    }

    private func bokehTargets(width: Int, height: Int, cached: Bool) -> BokehTargets? {
        let targetWidth = max(8, width / 4)
        let targetHeight = max(8, height / 4)
        let key = targetWidth << 16 | targetHeight
        if cached {
            lock.lock()
            defer { lock.unlock() }
            if let existing = bokehCache[key] { return existing }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: targetWidth, height: targetHeight, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let raw = device.makeTexture(descriptor: descriptor),
              let gathered = device.makeTexture(descriptor: descriptor),
              let smooth = device.makeTexture(descriptor: descriptor)
        else { return nil }
        let targets = BokehTargets(raw: raw, gathered: gathered, smooth: smooth)
        if cached {
            lock.lock()
            bokehCache[key] = targets
            lock.unlock()
        }
        return targets
    }

    /// Blur radius in pixels of the small bokeh texture: 4.5% of its short side at f/2.8.
    private static func bokehRadius(width: Int, height: Int, strength: Float) -> Float {
        Float(min(width, height)) * 0.045 * strength
    }

    /// The lens's gather of `raw` into `gathered`, then a light blur into `smooth` that hides the sample pattern.
    private func encodeLensBokeh(_ commandBuffer: MTLCommandBuffer, from raw: MTLTexture, through gathered: MTLTexture, into smooth: MTLTexture, params: inout GradeParams, cached: Bool) {
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(lensState)
            encoder.setTexture(raw, index: 0)
            encoder.setTexture(gathered, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<GradeParams>.stride, index: 0)
            dispatch(encoder, state: lensState, width: gathered.width, height: gathered.height)
            encoder.endEncoding()
        }
        let sigma = max(0.8, params.bokehRadius * 0.07)
        blur(sigma: (sigma * 4).rounded() / 4, cached: cached).encode(commandBuffer: commandBuffer, sourceTexture: gathered, destinationTexture: smooth)
    }

    /// The background of a portrait photo drawn by `lens`: the photo (and its background `mask`, white behind
    /// the subject) at up to 1280 px goes through the same gather as the viewfinder, and comes back as a
    /// picture the size of `image` to be laid under the sharp subject.
    func portraitBackground(image: CIImage, mask: CIImage, lens: LensStyle, strength: Double, context: CIContext) -> CIImage? {
        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        let scale = min(1, 1280 / max(extent.width, extent.height))
        let width = max(8, Int(extent.width * scale) & ~1)
        let height = max(8, Int(extent.height * scale) & ~1)
        guard let colour = Self.makePixelBuffer(width: width, height: height, format: kCVPixelFormatType_64RGBAHalf),
              let maskBuffer = Self.makePixelBuffer(width: width, height: height, format: kCVPixelFormatType_32BGRA),
              let output = Self.makePixelBuffer(width: width, height: height, format: kCVPixelFormatType_64RGBAHalf),
              let space = CGColorSpace(name: CGColorSpace.extendedSRGB)
        else { return nil }

        let shrink = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.render(image.transformed(by: shrink), to: colour, bounds: bounds, colorSpace: space)
        context.render(mask.transformed(by: shrink), to: maskBuffer, bounds: bounds, colorSpace: nil)

        var holders: [CVMetalTexture] = []
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let colourTexture = texture(from: colour, plane: nil, format: .rgba16Float, holders: &holders),
              let maskTexture = texture(from: maskBuffer, plane: nil, format: .bgra8Unorm, holders: &holders),
              let outputTexture = texture(from: output, plane: nil, format: .rgba16Float, holders: &holders),
              let packed = device.makeTexture(descriptor: descriptor),
              let gathered = device.makeTexture(descriptor: descriptor),
              let smooth = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer()
        else { return nil }

        var params = GradeParams()
        params.setLens(lens, radius: Self.bokehRadius(width: width, height: height, strength: Float(strength)))
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(packState)
        encoder.setTexture(colourTexture, index: 0)
        encoder.setTexture(maskTexture, index: 1)
        encoder.setTexture(packed, index: 2)
        encoder.setBytes(&params, length: MemoryLayout<GradeParams>.stride, index: 0)
        dispatch(encoder, state: packState, width: width, height: height)
        encoder.endEncoding()
        encodeLensBokeh(commandBuffer, from: packed, through: gathered, into: smooth, params: &params, cached: false)
        // The pixel buffer's texture is not made for writing by a blur, so the result is copied into it.
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: smooth, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: outputTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        withExtendedLifetime(holders) {}
        guard commandBuffer.status == .completed else { return nil }

        return CIImage(cvPixelBuffer: output, options: [.colorSpace: space])
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// The glow spreads about 1.5% of the short side, whatever the resolution.
    /// MPS kernels are not thread-safe, so only the capture queue shares cached ones.
    private func blur(for mask: MTLTexture, cached: Bool) -> MPSImageGaussianBlur {
        blur(sigma: max(1.5, Float(min(mask.width, mask.height)) * 0.015), cached: cached)
    }

    /// A Gaussian blur, shared per sigma (to a quarter) on the capture queue: building one costs more than running it.
    private func blur(sigma: Float, cached: Bool) -> MPSImageGaussianBlur {
        guard cached else {
            let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
            blur.edgeMode = .clamp
            return blur
        }
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
