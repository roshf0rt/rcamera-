import CameraCore
import SwiftUI
import UIKit

/// Lens previews, rendered once from `LensBokeh` and kept for the session.
@MainActor
final class LensPreviewCache {
    static let shared = LensPreviewCache()
    private var images: [LensStyle: UIImage] = [:]

    func image(for lens: LensStyle) -> UIImage? { images[lens] }

    func load(_ lens: LensStyle) async -> UIImage? {
        if let cached = images[lens] { return cached }
        let size = 192
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let pixels = LensBokeh.render(lens: lens, size: size)
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

/// The lens strip for portrait mode, like mood's: a preview card per lens with its name and character.
struct LensPicker: View {
    let selected: LensStyle
    let pick: (LensStyle) -> Void

    private var lenses: [LensStyle] { LensStyle.allCases.sorted { $0.order < $1.order } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(lenses, id: \.self) { lens in
                        Button { pick(lens) } label: { card(lens) }
                            .buttonStyle(PressableStyle())
                            .id(lens)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
    }

    private func card(_ lens: LensStyle) -> some View {
        let isSelected = lens == selected
        return VStack(alignment: .leading, spacing: 6) {
            LensPreview(lens: lens)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                )
            Text(lens.label)
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(isSelected ? Theme.accent : .white)
            Text(lens.summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
                .frame(width: 96, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}

/// Buttons that dip a little under the finger, with a light tap.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
