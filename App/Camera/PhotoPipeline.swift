import AVFoundation
import CameraCore
import CoreImage
import ImageIO
import UIKit

/// Turns captured photo data into the final image: choose a source, crop, apply the preset look, encode.
///
/// The saved photo is built from the camera's own processed image, the same source the viewfinder shows,
/// so the result matches what you saw. The RAW file is kept for Redevelop, with an exposure offset that
/// makes a developed RAW as bright as the processed image.
enum PhotoPipeline {
    struct Developed: Sendable {
        var heic: Data
        var thumbnail: Data
        /// EV that aligns the RAW's default rendering with the processed image. Zero without both inputs.
        var rawExposureOffset: Double
    }

    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func processedImage(_ data: Data) -> CIImage? {
        CIImage(data: data, options: [.applyOrientationProperty: true])
    }

    /// `scale` below 1 develops RAW at reduced size, which keeps interactive previews fast.
    private static func rawImage(_ data: Data, exposure: Double, scale: Float = 1) -> CIImage? {
        guard let filter = CIRAWFilter(imageData: data, identifierHint: nil) else { return nil }
        filter.exposure = Float(exposure)
        if scale < 1 { filter.scaleFactor = scale }
        guard let output = filter.outputImage else { return nil }
        // The app is portrait-only, so a landscape RAW still needs its rotation applied.
        return output.extent.width > output.extent.height ? output.oriented(.right) : output
    }

    /// Average linear brightness over the whole frame.
    private static func meanLuma(_ image: CIImage) -> Double? {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite,
              let average = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: image,
                  kCIInputExtentKey: CIVector(cgRect: extent),
              ])?.outputImage
        else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        let luma = Double(0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2])
        return luma > 0.0001 ? luma : nil
    }

    static func rawExposureOffset(raw: Data, processed: Data) -> Double {
        guard let rawImage = rawImage(raw, exposure: 0, scale: 0.2),
              let processed = processedImage(processed),
              let rawLuma = meanLuma(rawImage),
              let processedLuma = meanLuma(processed)
        else { return 0 }
        // The camera's own image is brighter mostly because its local tone mapping lifts the shadows.
        // Matching that with global exposure would push the highlights far past white, so RAW is
        // brightened by at most 1 EV; darkening is not limited.
        return min(max(log2(processedLuma / rawLuma), -3), 1)
    }

    static func finish(_ image: CIImage, look: FilmLook, aspect: AspectOption, mirror: Bool) -> CIImage {
        let extent = image.extent.integral
        let crop = aspect.cropRect(sourceWidth: Int(extent.width), sourceHeight: Int(extent.height))
        let rect = CGRect(
            x: extent.minX + CGFloat(crop.x),
            y: extent.minY + CGFloat(crop.y),
            width: CGFloat(crop.width),
            height: CGFloat(crop.height)
        )
        var result = image
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        // The same GPU grade as the viewfinder, so the photo matches what was on screen.
        if let graded = MetalGrader.shared?.grade(image: result, look: look, context: context) {
            result = graded
        }
        if mirror {
            result = result.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0))
        }
        return result
    }

    private static func encode(_ image: CIImage, rawExposureOffset: Double) -> Developed? {
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        // 10-bit HEIC keeps the half-float grade's gradations; 8 bits is the fallback.
        guard let heic = (try? context.heif10Representation(of: image, colorSpace: displayP3, options: [quality: 0.92]))
            ?? context.heifRepresentation(of: image, format: .RGBA8, colorSpace: displayP3, options: [quality: 0.92])
        else {
            return nil
        }
        let longSide = max(image.extent.width, image.extent.height)
        let factor = min(1, 480 / longSide)
        let small = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let thumbnail = context.jpegRepresentation(of: small, colorSpace: sRGB, options: [quality: 0.8]) else {
            return nil
        }
        return Developed(heic: heic, thumbnail: thumbnail, rawExposureOffset: rawExposureOffset)
    }

    /// Builds the saved photo at capture time. With a RAW it develops the RAW, as Lampa does, so the picture
    /// skips the camera's local tone mapping and keeps the sensor's range; the processed image only sets the
    /// exposure. Without one (flash, portrait, RAW off) it grades the processed image.
    static func develop(
        raw: Data?,
        processed: Data?,
        look: FilmLook,
        aspect: AspectOption,
        mirror: Bool,
        frame: FrameStyle = .off,
        label: String = "",
        accentIndex: Int = 0,
        depth: AVDepthData? = nil,
        fNumber: Double = PortraitAperture.standard,
        lens: LensStyle = .solis,
        orientation: DeviceOrientation = .portrait
    ) -> Developed? {
        let offset = (raw != nil && processed != nil) ? rawExposureOffset(raw: raw!, processed: processed!) : 0
        let base: CIImage?
        if let raw, let developed = rawImage(raw, exposure: offset) {
            base = developed
        } else if let processed {
            base = processedImage(processed)
        } else {
            base = nil
        }
        guard let base else { return nil }
        let blurred = depth.flatMap { portraitBlur(base, depth: $0, fNumber: fNumber, lens: lens) } ?? base
        let subject = depth == nil ? base : lensLook(blurred, lens: lens)
        let finished = turned(finish(subject, look: look, aspect: aspect, mirror: mirror), orientation)
        return encode(framedIfNeeded(finished, frame: frame, label: label, accentIndex: accentIndex), rawExposureOffset: offset)
    }

    /// The portrait frame turned to how the phone was held, before the border so the border fits the shot.
    static func turned(_ image: CIImage, _ orientation: DeviceOrientation) -> CIImage {
        let result: CIImage
        switch orientation.quarterTurns {
        case 1: result = image.oriented(.left)
        case -1: result = image.oriented(.right)
        default: return image
        }
        return result.transformed(by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
    }

    /// What a redevelop starts from: the RAW when it is still kept, otherwise the camera's own image.
    enum Source: @unchecked Sendable {
        case raw(Data, exposureOffset: Double)
        case original(Data)
    }

    /// `scale` below 1 renders smaller, for interactive previews.
    private static func baseImage(_ source: Source, pushPull: Double, scale: Float) -> CIImage? {
        switch source {
        case let .raw(data, offset):
            return rawImage(data, exposure: offset + pushPull, scale: scale)
        case let .original(data):
            guard var image = processedImage(data) else { return nil }
            if scale < 1 {
                image = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
            }
            if abs(pushPull) > 0.001 {
                image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: pushPull])
            }
            return image
        }
    }

    /// Re-renders a stored capture with another preset and push/pull.
    static func redevelop(
        source: Source,
        look: FilmLook,
        pushPull: Double,
        aspect: AspectOption,
        mirror: Bool,
        frame: FrameStyle = .off,
        label: String = "",
        accentIndex: Int = 0,
        orientation: DeviceOrientation = .portrait
    ) -> Developed? {
        guard let base = baseImage(source, pushPull: pushPull, scale: 1) else { return nil }
        let offset: Double
        if case let .raw(_, value) = source { offset = value } else { offset = 0 }
        let finished = turned(finish(base, look: look, aspect: aspect, mirror: mirror), orientation)
        return encode(framedIfNeeded(finished, frame: frame, label: label, accentIndex: accentIndex), rawExposureOffset: offset)
    }

    /// Blurs the background of a portrait photo with Core Image's depth blur, driven by the photo's depth map.
    /// The lens character on top of the blur: vignetting at the edges and a glow around the highlights.
    /// The look's colour fringing comes from the lens too, through `LensStyle.apply(to:)`.
    static func lensLook(_ image: CIImage, lens: LensStyle) -> CIImage {
        var result = image
        if let vignette = CIFilter(name: "CIVignette") {
            vignette.setValue(result, forKey: kCIInputImageKey)
            vignette.setValue(-lens.vignette, forKey: kCIInputIntensityKey)
            vignette.setValue(1.5, forKey: kCIInputRadiusKey)
            result = vignette.outputImage?.cropped(to: image.extent) ?? result
        }
        if let bloom = CIFilter(name: "CIBloom") {
            bloom.setValue(result, forKey: kCIInputImageKey)
            bloom.setValue(lens.ring * 0.5, forKey: kCIInputIntensityKey)
            bloom.setValue(10 + lens.highlightSpread * 20, forKey: kCIInputRadiusKey)
            result = bloom.outputImage?.cropped(to: image.extent) ?? result
        }
        return result
    }

    /// Portrait background blur drawn by the lens: the background (by the depth map) is blurred with
    /// Core Image's bokeh blur, whose rings and softness come from the lens, then swirled and stretched
    /// the way the lens draws, and laid back under the sharp subject. Strength follows the f-number.
    ///
    /// The depth map comes from the sensor's landscape orientation, so it is turned to match the photo.
    /// Strengths and orientation were written without a device to check them against.
    static func portraitBlur(_ image: CIImage, depth: AVDepthData, fNumber: Double, lens: LensStyle) -> CIImage? {
        let extent = image.extent
        guard let mask = backgroundMask(depth: depth, extent: extent) else { return nil }

        // Wide open is strong, f/16 nearly sharp. Radius in pixels of the full photo.
        let strength = PortraitAperture.blurStrength(fNumber: fNumber)
        let radius = Double(min(extent.width, extent.height)) * 0.03 * strength
        guard radius > 0.5 else { return image }

        // Blur at a quarter size (the result is soft anyway); anamorphic lenses squeeze the frame
        // sideways first, so round blur turns into tall ovals when it is stretched back.
        let quarter = 0.25
        let squeeze = 1 / (1 + 0.5 * max(0, lens.ovality))
        let small = image.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: quarter * squeeze, y: quarter))
        guard let bokeh = CIFilter(name: "CIBokehBlur") else { return nil }
        bokeh.setValue(small, forKey: kCIInputImageKey)
        bokeh.setValue(radius * quarter, forKey: kCIInputRadiusKey)
        bokeh.setValue(max(0, lens.rim) * 0.9, forKey: "inputRingAmount")
        bokeh.setValue(0.02 + 0.16 * lens.rimWidth, forKey: "inputRingSize")
        bokeh.setValue(lens.rim < 0 ? 3.0 : 0.6, forKey: "inputSoftness")
        guard var background = bokeh.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 1 / (quarter * squeeze), y: 1 / quarter))
        else { return nil }

        // Swirl around the centre for Helios- and Petzval-style lenses.
        if lens.swirl > 0.05, let twirl = CIFilter(name: "CITwirlDistortion") {
            twirl.setValue(background, forKey: kCIInputImageKey)
            twirl.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
            twirl.setValue(Double(max(extent.width, extent.height)) * 0.7, forKey: kCIInputRadiusKey)
            twirl.setValue(lens.swirl * 0.5 * strength.squareRoot(), forKey: kCIInputAngleKey)
            background = twirl.outputImage ?? background
        }
        background = background.cropped(to: extent)

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(background, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage?.cropped(to: extent)
    }

    /// White where the scene is behind the subject, black on the subject, with a soft edge. The subject is
    /// whatever is in the middle of the frame, as the portrait focus usually is.
    private static func backgroundMask(depth: AVDepthData, extent: CGRect) -> CIImage? {
        let disparity = depth.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32).depthDataMap
        let map = CIImage(cvPixelBuffer: disparity).oriented(.right)
        let fitted = map
            .transformed(by: CGAffineTransform(translationX: -map.extent.minX, y: -map.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / map.extent.width, y: extent.height / map.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        let centre = CGRect(x: extent.midX - extent.width * 0.15, y: extent.midY - extent.height * 0.15,
                            width: extent.width * 0.3, height: extent.height * 0.3)
        guard let focus = averageRed(fitted, in: centre), focus > 0.0001 else { return nil }
        // Disparity falls with distance: at 85% of the subject's it starts to blur, at 55% fully.
        let near = focus * 0.85, far = focus * 0.55
        let gain = 1 / (near - far)
        guard let matrix = CIFilter(name: "CIColorMatrix") else { return nil }
        matrix.setValue(fitted, forKey: kCIInputImageKey)
        let row = CIVector(x: CGFloat(-gain), y: 0, z: 0, w: 0)
        matrix.setValue(row, forKey: "inputRVector")
        matrix.setValue(row, forKey: "inputGVector")
        matrix.setValue(row, forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
        let bias = CGFloat(near * gain)
        matrix.setValue(CIVector(x: bias, y: bias, z: bias, w: 1), forKey: "inputBiasVector")
        guard let raw = matrix.outputImage else { return nil }
        let clamped = raw.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
        return clamped
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: Double(min(extent.width, extent.height)) * 0.008])
            .cropped(to: extent)
    }

    /// Mean of the red channel over `rect`, unclamped.
    private static func averageRed(_ image: CIImage, in rect: CGRect) -> Double? {
        guard let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return Double(pixel[0])
    }

    /// Draws a pattern in translucent white over the whole frame. The photo is drawn on top and hides the middle.
    /// `edge` is the frame's side width, so the pattern scales with the photo.
    static func drawPattern(_ pattern: FramePattern, in cg: CGContext, width: Int, height: Int, edge: CGFloat) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        cg.saveGState()
        defer { cg.restoreGState() }
        switch pattern {
        case .none:
            break
        case .dots:
            cg.setFillColor(UIColor.white.withAlphaComponent(0.25).cgColor)
            let step = edge * 1.6
            let radius = edge * 0.22
            var y = step / 2
            while y < h {
                var x = step / 2
                while x < w {
                    cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += step
                }
                y += step
            }
        case .stripes:
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
            cg.setLineWidth(edge * 0.4)
            let step = edge * 1.4
            var x: CGFloat = -h
            while x < w {
                cg.move(to: CGPoint(x: x, y: h))
                cg.addLine(to: CGPoint(x: x + h, y: 0))
                x += step
            }
            cg.strokePath()
        case .grid:
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
            cg.setLineWidth(max(1, edge * 0.08))
            let step = edge * 0.9
            var x: CGFloat = 0
            while x <= w {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: h))
                x += step
            }
            var y: CGFloat = 0
            while y <= h {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: w, y: y))
                y += step
            }
            cg.strokePath()
        }
    }

    private static func framedIfNeeded(_ image: CIImage, frame: FrameStyle, label: String, accentIndex: Int) -> CIImage {
        let style = frame.resolved(accentIndex: accentIndex)
        guard style != .off else { return image }
        return framed(image, label: label, accentIndex: accentIndex, pattern: style.pattern) ?? image
    }

    /// The photo on a border: the preset card's gradient, with the preset name on the bottom band.
    static func framed(_ image: CIImage, label: String, accentIndex: Int, pattern: FramePattern = .none) -> CIImage? {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        let layout = FrameLayout.make(width: width, height: height)
        let canvasWidth = layout.canvasWidth(photoWidth: width)
        let canvasHeight = layout.canvasHeight(photoHeight: height)
        guard let photo = context.createCGImage(image, from: extent) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasWidth, height: canvasHeight), format: format)
        let rendered = renderer.image { context in
            let cgColors = Theme.colors(accentIndex).map { UIColor($0).cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: CGFloat(canvasHeight)),
                    options: []
                )
            }
            drawPattern(pattern, in: context.cgContext, width: canvasWidth, height: canvasHeight, edge: CGFloat(min(width, height)) / 25)
            UIImage(cgImage: photo).draw(in: CGRect(x: layout.side, y: layout.top, width: width, height: height))

            let font = UIFont.systemFont(ofSize: CGFloat(layout.bottom) * 0.36, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .kern: 2]
            let text = label.uppercased() as NSString
            let size = text.size(withAttributes: attributes)
            let origin = CGPoint(
                x: (CGFloat(canvasWidth) - size.width) / 2,
                y: CGFloat(canvasHeight - layout.bottom) + (CGFloat(layout.bottom) - size.height) / 2
            )
            text.draw(at: origin, withAttributes: attributes)
        }
        guard let output = rendered.cgImage else { return nil }
        return CIImage(cgImage: output)
    }

    // MARK: Interactive preview

    /// The source developed, cropped and mirrored at reduced size, as an sRGB buffer. Decoding is the slow
    /// part, so the Redevelop screen keeps this and only re-grades it when the preset or effects change.
    static func previewBase(source: Source, pushPull: Double, aspect: AspectOption, mirror: Bool, scale: Float) -> CVPixelBuffer? {
        guard let base = baseImage(source, pushPull: pushPull, scale: scale) else { return nil }
        let extent = base.extent.integral
        let crop = aspect.cropRect(sourceWidth: Int(extent.width), sourceHeight: Int(extent.height))
        let rect = CGRect(x: extent.minX + CGFloat(crop.x), y: extent.minY + CGFloat(crop.y), width: CGFloat(crop.width), height: CGFloat(crop.height))
        var image = base.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        if mirror {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0))
        }
        guard let buffer = MetalGrader.makePixelBuffer(width: crop.width, height: crop.height) else { return nil }
        context.render(image, to: buffer, bounds: CGRect(x: 0, y: 0, width: crop.width, height: crop.height), colorSpace: sRGB)
        return buffer
    }

    /// Any photo (camera file, library pick) scaled to `longSide`, as a preview base.
    static func previewBase(data: Data, longSide: CGFloat = 1000) -> CVPixelBuffer? {
        processedImage(data).flatMap { previewBase(image: $0, longSide: longSide) }
    }

    static func previewBase(image: CIImage, longSide: CGFloat = 1000) -> CVPixelBuffer? {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        let factor = min(1, longSide / max(extent.width, extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let rect = scaled.extent.integral
        let placed = scaled.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let width = Int(rect.width) & ~1, height = Int(rect.height) & ~1
        guard width > 0, height > 0, let buffer = MetalGrader.makePixelBuffer(width: width, height: height) else { return nil }
        context.render(placed, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: sRGB)
        return buffer
    }

    /// The built-in test scene for the preset editor: sky, sun, greens, skin tones and shadows, ungraded.
    static func sampleScene(width: Int = 1000, height: Int = 750) -> CVPixelBuffer? {
        let pixels = LUTCardArt.render(lut: nil, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }
        return previewBase(image: CIImage(cgImage: cgImage), longSide: CGFloat(max(width, height)))
    }

    /// Grades a preview base with a look. A few milliseconds on the GPU.
    static func gradePreview(_ base: CVPixelBuffer, look: FilmLook) -> UIImage? {
        let width = CVPixelBufferGetWidth(base), height = CVPixelBufferGetHeight(base)
        guard let grader = MetalGrader.shared,
              let output = MetalGrader.makePixelBuffer(width: width, height: height),
              grader.grade(source: base, crop: CropRect(x: 0, y: 0, width: width, height: height), mirror: false, look: look, into: output, cachedMasks: false)
        else { return nil }
        let image = CIImage(cvPixelBuffer: output, options: [.colorSpace: sRGB])
        guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
