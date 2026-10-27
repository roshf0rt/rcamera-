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
        return min(max(log2(processedLuma / rawLuma), -3), 3)
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
        guard let heic = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: displayP3, options: [quality: 0.92]) else {
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

    /// Builds the saved photo at capture time. Prefers the processed image; falls back to RAW when that is all there is.
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
        lens: LensStyle = .solis
    ) -> Developed? {
        let offset = (raw != nil && processed != nil) ? rawExposureOffset(raw: raw!, processed: processed!) : 0
        let base: CIImage?
        if let processed {
            base = processedImage(processed)
        } else if let raw {
            base = rawImage(raw, exposure: 0)
        } else {
            base = nil
        }
        guard let base else { return nil }
        let blurred = depth.flatMap { portraitBlur(base, depth: $0, fNumber: fNumber) } ?? base
        let subject = depth == nil ? base : lensLook(blurred, lens: lens)
        let finished = finish(subject, look: look, aspect: aspect, mirror: mirror)
        return encode(framedIfNeeded(finished, frame: frame, label: label, accentIndex: accentIndex), rawExposureOffset: offset)
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
        accentIndex: Int = 0
    ) -> Developed? {
        guard let base = baseImage(source, pushPull: pushPull, scale: 1) else { return nil }
        let offset: Double
        if case let .raw(_, value) = source { offset = value } else { offset = 0 }
        let finished = finish(base, look: look, aspect: aspect, mirror: mirror)
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

    /// The depth map comes from the sensor's landscape orientation, so it is turned to match the photo.
    /// Blur strength and orientation were written without a device to check them against.
    static func portraitBlur(_ image: CIImage, depth: AVDepthData, fNumber: Double) -> CIImage? {
        let disparity = depth.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat16).depthDataMap
        let map = CIImage(cvPixelBuffer: disparity).oriented(.right)
        let extent = image.extent
        let fitted = map.transformed(by: CGAffineTransform(
            scaleX: extent.width / map.extent.width,
            y: extent.height / map.extent.height
        ))
        guard let filter = CIFilter(name: "CIDepthBlurEffect") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(fitted, forKey: "inputDisparityImage")
        filter.setValue(fNumber, forKey: "inputAperture")
        return filter.outputImage?.cropped(to: extent)
    }

    private static func framedIfNeeded(_ image: CIImage, frame: FrameStyle, label: String, accentIndex: Int) -> CIImage {
        guard frame != .off else { return image }
        return framed(image, label: label, accentIndex: accentIndex) ?? image
    }

    /// The photo on a border: the preset card's gradient, with the preset name on the bottom band.
    static func framed(_ image: CIImage, label: String, accentIndex: Int) -> CIImage? {
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
