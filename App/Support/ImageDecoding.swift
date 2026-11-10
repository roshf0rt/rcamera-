import ImageIO
import UIKit

/// Decodes pictures off the main thread at the size they are shown at.
///
/// `UIImage(contentsOfFile:)` only reads the file: the picture is decoded the first time it is drawn, which is on
/// the main thread, so every new thumbnail or photo page cost a frame or more while scrolling or swiping. ImageIO
/// here decodes right away (`ShouldCacheImmediately`), already scaled down, and turned by the file's orientation.
enum ImageDecoding {
    /// Long side of the photos the viewer shows. A 12 MP photo stays whole; a 48 MP one is shown at a quarter of
    /// its pixels (a quarter of the memory), still more than the screen at the deepest zoom of most photos.
    static let viewerPixels = 4032

    /// Long side of grid thumbnails: three to a row at the phone's pixel density.
    static let thumbnailPixels = 600

    /// The picture at `url`, decoded, its long side at most `maxPixels`.
    static func image(at url: URL, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The long side of the picture at `url` in pixels, read from its header without decoding it.
    static func pixelLongSide(at url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(width, height)
    }
}
