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
        result = look.apply(to: result, raw: false)
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

    /// Re-renders a stored RAW with another preset and push/pull.
    static func redevelop(
        raw: Data,
        look: FilmLook,
        pushPull: Double,
        rawExposureOffset: Double,
        aspect: AspectOption
    ) -> Developed? {
        guard let base = rawImage(raw, exposure: rawExposureOffset + pushPull) else { return nil }
        return encode(finish(base, look: look, aspect: aspect, mirror: false), rawExposureOffset: rawExposureOffset)
    }

    /// A reduced-size render for the Redevelop screen.
    static func preview(
        raw: Data,
        look: FilmLook,
        pushPull: Double,
        rawExposureOffset: Double,
        aspect: AspectOption
    ) -> UIImage? {
        guard let base = rawImage(raw, exposure: rawExposureOffset + pushPull, scale: 0.35) else { return nil }
        let image = finish(base, look: look, aspect: aspect, mirror: false)
        guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
