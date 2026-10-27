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
        mirror: Bool
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
        return encode(finish(base, look: look, aspect: aspect, mirror: mirror), rawExposureOffset: offset)
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
    static func redevelop(source: Source, look: FilmLook, pushPull: Double, aspect: AspectOption, mirror: Bool) -> Developed? {
        guard let base = baseImage(source, pushPull: pushPull, scale: 1) else { return nil }
        let offset: Double
        if case let .raw(_, value) = source { offset = value } else { offset = 0 }
        return encode(finish(base, look: look, aspect: aspect, mirror: mirror), rawExposureOffset: offset)
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
