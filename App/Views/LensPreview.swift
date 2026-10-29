import CameraCore
import SwiftUI
import UIKit

/// Lens previews, drawn once per lens from `LensPreviewScene` at the ring's size on a 3× screen, and kept for the session.
@MainActor
final class LensPreviewCache {
    static let shared = LensPreviewCache()
    private var images: [LensStyle: UIImage] = [:]

    func image(for lens: LensStyle) -> UIImage? { images[lens] }

    func load(_ lens: LensStyle) async -> UIImage? {
        if let cached = images[lens] { return cached }
        let size = 320
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let pixels = LensPreviewScene.render(lens: lens, size: size)
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let cgImage = CGImage(
                      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                      space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
                  )
            else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
        images[lens] = image
        return image
    }
}

/// One lens's preview: its bokeh in a night scene.
struct LensPreview: View {
    let lens: LensStyle
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.04)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .task(id: lens) {
            image = LensPreviewCache.shared.image(for: lens)
            if image == nil {
                let loaded = await LensPreviewCache.shared.load(lens)
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
        }
    }
}
