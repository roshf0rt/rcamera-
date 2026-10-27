import CameraCore
import CoreImage
import ImageIO
import UIKit

/// Turns captured RAW or processed photo data into the final image: develop, crop, apply the preset look, encode.
enum PhotoPipeline {
    struct Developed: Sendable {
        var heic: Data
        var thumbnail: Data
    }

    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `scale` below 1 develops RAW at reduced size, which keeps interactive previews fast.
    static func baseImage(raw: Data?, processed: Data?, pushPull: Double, scale: Float = 1) -> CIImage? {
        if let raw, let filter = CIRAWFilter(imageData: raw, identifierHint: nil) {
            filter.exposure = Float(pushPull)
            if scale < 1 { filter.scaleFactor = scale }
            if let output = filter.outputImage {
                // The app is portrait-only, so a landscape RAW still needs its rotation applied.
                return output.extent.width > output.extent.height ? output.oriented(.right) : output
            }
        }
        if let processed {
            return CIImage(data: processed, options: [.applyOrientationProperty: true])
        }
        return nil
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
        result = look.apply(to: result)
        if mirror {
            result = result.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0))
        }
        return result
    }

    static func develop(
        raw: Data?,
        processed: Data?,
        look: FilmLook,
        pushPull: Double,
        aspect: AspectOption,
        mirror: Bool
    ) -> Developed? {
        guard let base = baseImage(raw: raw, processed: processed, pushPull: pushPull) else { return nil }
        let image = finish(base, look: look, aspect: aspect, mirror: mirror)

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
        return Developed(heic: heic, thumbnail: thumbnail)
    }

    /// A reduced-size render for the Redevelop screen.
    static func preview(
        raw: Data,
        look: FilmLook,
        pushPull: Double,
        aspect: AspectOption
    ) -> UIImage? {
        guard let base = baseImage(raw: raw, processed: nil, pushPull: pushPull, scale: 0.35) else { return nil }
        let image = finish(base, look: look, aspect: aspect, mirror: false)
        guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
