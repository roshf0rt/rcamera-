import CameraCore
import UIKit

/// A preset's card picture (`LUTCardArt` graded by its LUT) and the words for its look (`LUTProfile`).
struct PresetArt: @unchecked Sendable {
    let image: UIImage
    let tags: [String]
    let hasLUT: Bool

    static let pixelWidth = 360
    static let pixelHeight = 220

    /// A picture you made yourself (see App/Resources/Previews/README.md) replaces the generated landscape.
    /// Its words still come from the LUT. CPU work, a few milliseconds per preset. Call off the main thread.
    static func make(lut: LUT3D?, previewURL: URL?) -> PresetArt? {
        let tags = lut.map { LUTProfile(lut: $0).tags } ?? ["No LUT"]
        if let previewURL, let image = UIImage(contentsOfFile: previewURL.path) {
            return PresetArt(image: image, tags: tags, hasLUT: lut != nil)
        }
        let width = pixelWidth, height = pixelHeight
        let pixels = LUTCardArt.render(lut: lut, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { return nil }
        return PresetArt(image: UIImage(cgImage: cgImage), tags: tags, hasLUT: lut != nil)
    }
}
