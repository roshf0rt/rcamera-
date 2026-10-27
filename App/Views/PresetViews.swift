import CameraCore
import PhotosUI
import SwiftUI

/// How a preset's card looks: soft lights of colour blurred into each other under film grain, a small
/// description top left and the name large at the bottom, as in the RCamera card designs. The preset's
/// `accentIndex` picks the artwork; a built-in keeps its own description whatever artwork it is given.
struct PresetCardStyle {
    /// One soft light in the artwork: its colour, its centre (0...1 across and down) and its radius as a
    /// share of the card's width.
    struct Glow {
        var color: Color
        var x: CGFloat
        var y: CGFloat
        var radius: CGFloat
    }

    let subtitle: String
    let base: Color
    let glows: [Glow]
    /// Light artwork needs dark text.
    var light = false

    /// The artwork's colours as a plain gradient, for small dots.
    var gradient: LinearGradient {
        LinearGradient(colors: [base] + glows.map(\.color), startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// In the order of the built-in presets' ids: JaneSu, Carbon, Clear, Drift, Mosaic, Rise, Sienna, Silver, Solstice, Velvet.
    static let all: [PresetCardStyle] = [
        PresetCardStyle(subtitle: "Film • Color", base: hex(0x2F55D8), glows: [
            glow(0x218DFD, 0.1, 0.2, 0.45), glow(0x7066D8, 0.5, 0.6, 0.4), glow(0xF13722, 0.97, 0.5, 0.4), glow(0xF6A27A, 0.75, 1.05, 0.25),
        ]),
        PresetCardStyle(subtitle: "Mono • Contrast", base: hex(0x26292C), glows: [
            glow(0x9DA1A0, 0.75, 0.35, 0.4), glow(0xE8E6DE, 0.97, 0.12, 0.25), glow(0x111315, 0.1, 0.9, 0.4),
        ]),
        PresetCardStyle(subtitle: "Clean • Neutral", base: hex(0xD6D7CD), glows: [
            glow(0xF4F4EC, 0.3, 0.3, 0.45), glow(0xBFC3B6, 0.9, 0.95, 0.4), glow(0xE9E2CF, 0.8, 0.2, 0.3),
        ], light: true),
        PresetCardStyle(subtitle: "Grain • Golden", base: hex(0x7F9AA6), glows: [
            glow(0x6C93B8, 0.1, 0.15, 0.45), glow(0xE6DFA0, 0.55, 0.35, 0.35), glow(0xD5E86A, 0.97, 0.4, 0.4),
            glow(0x5E8A36, 0.12, 1.0, 0.45), glow(0x9BB38C, 0.6, 0.95, 0.35),
        ]),
        PresetCardStyle(subtitle: "Color • Vivid", base: hex(0x4058A0), glows: [
            glow(0x996DA2, 0.55, 0.5, 0.4), glow(0xEBCB8B, 1.0, 0.3, 0.35), glow(0x2D3F86, 0.05, 0.9, 0.4),
        ]),
        PresetCardStyle(subtitle: "Custom • Color LUT", base: hex(0x163566), glows: [
            glow(0x0F2A55, 0.05, 0.4, 0.45), glow(0x8EA4C6, 0.5, 1.0, 0.35), glow(0x6E7FB0, 0.6, 0.2, 0.3), glow(0xE2452C, 1.0, 0.45, 0.4),
        ]),
        PresetCardStyle(subtitle: "Warm • Film", base: hex(0x9C4429), glows: [
            glow(0xE38A50, 0.6, 0.5, 0.45), glow(0xF2CA8F, 1.0, 0.2, 0.35), glow(0x6E2A18, 0.0, 1.0, 0.4),
        ]),
        PresetCardStyle(subtitle: "Mono • Soft", base: hex(0x6C7073), glows: [
            glow(0xC5C7C4, 0.6, 0.4, 0.45), glow(0xF1F1EA, 0.95, 0.1, 0.3), glow(0x45494C, 0.05, 0.95, 0.4),
        ]),
        PresetCardStyle(subtitle: "Grain • Halation", base: hex(0x214C4E), glows: [
            glow(0x18393B, 0.1, 0.9, 0.5), glow(0xC9706C, 0.8, 0.55, 0.38), glow(0xFBE6E2, 0.88, 0.45, 0.18),
        ]),
        PresetCardStyle(subtitle: "Grain • Cool green", base: hex(0x0B5A4E), glows: [
            glow(0x85A764, 0.55, 0.6, 0.4), glow(0xEDBD53, 1.0, 0.3, 0.35), glow(0x063A33, 0.0, 0.1, 0.4),
        ]),
    ]

    static func of(_ preset: Preset) -> PresetCardStyle {
        all[((preset.accentIndex % all.count) + all.count) % all.count]
    }

    /// What the preset is: a built-in keeps its own description whatever artwork its card is given.
    static func subtitle(of preset: Preset) -> String {
        if preset.isCustom { return "My preset" }
        let number = Int(preset.id.replacingOccurrences(of: "preset-", with: "")) ?? 0
        return all.indices.contains(number - 1) ? all[number - 1].subtitle : of(preset).subtitle
    }

    private static func hex(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    private static func glow(_ rgb: UInt32, _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Glow {
        Glow(color: hex(rgb), x: x, y: y, radius: radius)
    }
}

/// A card's artwork: the style's lights blurred together, with film grain over them.
struct PresetArtwork: View {
    let style: PresetCardStyle

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                style.base
                ForEach(style.glows.indices, id: \.self) { index in
                    let glow = style.glows[index]
                    Circle()
                        .fill(glow.color)
                        .frame(width: glow.radius * 2 * size.width, height: glow.radius * 2 * size.width)
                        .position(x: glow.x * size.width, y: glow.y * size.height)
                }
            }
            .blur(radius: max(size.width, size.height) * 0.11, opaque: true)
            .overlay(FilmGrainOverlay())
        }
        .clipped()
        .drawingGroup()
    }
}

/// Fine monochrome grain, tiled. The same noise every time, so cards do not shimmer.
struct FilmGrainOverlay: View {
    private static let tile: UIImage = {
        let side = 96
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for index in 0 ..< side * side {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            let value = UInt8(truncatingIfNeeded: (z ^ (z >> 31)) >> 56)
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        guard let provider,
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: image)
    }()

    var body: some View {
        Rectangle()
            .fill(ImagePaint(image: Image(uiImage: Self.tile), scale: 0.5))
            .blendMode(.overlay)
            .opacity(0.45)
            .allowsHitTesting(false)
    }
}

/// The horizontal row of preset cards shown above the shutter.
struct PresetPicker: View {
    @Environment(AppModel.self) private var model
    /// Opens the editor for a preset, from the long-press menu.
    var onEdit: (String) -> Void = { _ in }
    /// Opens the new-preset sheet, from scratch (nil) or based on a preset.
    var onCreate: (Preset?) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.visiblePresets) { preset in
                        PresetCard(preset: preset, isSelected: preset.id == model.selectedPreset.id) {
                            model.selectPreset(preset.id)
                        }
                        .id(preset.id)
                        .contextMenu {
                            Button { onEdit(preset.id) } label: {
                                Label(preset.isCustom ? "Edit" : "Quality & Tone", systemImage: "slider.horizontal.3")
                            }
                            Button { onCreate(preset) } label: {
                                Label("New preset from this", systemImage: "plus.square.on.square")
                            }
                            if preset.isCustom {
                                if let url = model.exportPreset(id: preset.id) {
                                    ShareLink(item: url) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                }
                                Button(role: .destructive) { model.deletePreset(id: preset.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    Button { onCreate(nil) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                            Text("New").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 84, height: PresetCard.height)
                        .background(RoundedRectangle(cornerRadius: PresetCard.corner, style: .continuous).fill(Color(white: 0.08)))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(model.selectedPreset.id, anchor: .center) }
        }
        .frame(height: PresetCard.height + 8)
    }
}

/// A preset card: the artwork with the description small at the top and the name large at the bottom,
/// running off the edge like the designs. No frame: the selected card is at full colour and a little
/// larger, the others are dimmed. With a `thumbnail` (Redevelop) or a cover photo the card shows that instead.
struct PresetCard: View {
    static let width: CGFloat = 138
    static let height: CGFloat = 84
    static let corner: CGFloat = 18

    let preset: Preset
    let isSelected: Bool
    var thumbnail: UIImage?
    let action: () -> Void
    @Environment(AppModel.self) private var model

    private var style: PresetCardStyle { PresetCardStyle.of(preset) }
    /// The redevelop thumbnail, or the photo the user chose for the card.
    private var picture: UIImage? { thumbnail ?? model.cover(for: preset.id) }
    private var darkText: Bool { style.light && picture == nil }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                artwork
                Text(PresetCardStyle.subtitle(of: preset))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(darkText ? Color.black.opacity(0.45) : Color.white.opacity(0.62))
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .padding(.top, 9)
                Text(preset.name)
                    .font(.system(size: 34, weight: .regular))
                    .tracking(-1)
                    .foregroundStyle(darkText ? Color.black.opacity(0.85) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 9)
                    // The descenders run off the bottom edge, as in the designs.
                    .offset(y: 7)
            }
            .frame(width: Self.width, height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .fill(Color.black.opacity(isSelected ? 0 : 0.5))
                    .allowsHitTesting(false)
            }
            .scaleEffect(isSelected ? 1 : 0.96)
            .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isSelected)
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel("\(preset.name), \(PresetCardStyle.subtitle(of: preset))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var artwork: some View {
        if let picture {
            Image(uiImage: picture)
                .resizable()
                .scaledToFill()
                .frame(width: Self.width, height: Self.height)
                .clipped()
                .overlay(FilmGrainOverlay())
            LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        } else {
            PresetArtwork(style: style)
        }
    }
}

/// A small square of the preset's card: its photo if it has one, otherwise its artwork. For lists and
/// the camera's preset button.
struct PresetSwatch: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    var corner: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if let cover = model.cover(for: preset.id) {
            Color.clear
                .overlay { Image(uiImage: cover).resizable().scaledToFill() }
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom))
                .clipShape(shape)
        } else {
            PresetArtwork(style: PresetCardStyle.of(preset))
                .clipShape(shape)
        }
    }
}

/// The sheet for a new custom preset: a name, what it starts from (nothing, or one of the presets with
/// its LUTs), and its card: one of the card designs, or a photo.
struct NewPresetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Preselected starting point; nil starts from scratch.
    let base: Preset?
    /// Called with the new preset's id, so the caller can open its editor.
    let created: (String) -> Void

    @State private var name = ""
    @State private var baseID: String?
    @State private var accentIndex = 0
    @State private var coverItem: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var coverImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    TextField("Preset name", text: $name)
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chrome.opacity(0.6)))

                    section("Start from") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                startCard(nil)
                                ForEach(model.visiblePresets) { preset in startCard(preset) }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.horizontal, -16)
                        Text(baseID == nil
                             ? "An empty look: no LUT, no grain, every regulator neutral."
                             : "A copy of this preset's look and LUTs. Every regulator is yours to change.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    section("Card") {
                        HStack(spacing: 10) {
                            ForEach(PresetCardStyle.all.indices, id: \.self) { index in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { accentIndex = index }
                                } label: {
                                    Circle()
                                        .fill(PresetCardStyle.all[index].gradient)
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: accentIndex == index && coverImage == nil ? 2 : 0))
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $coverItem, matching: .images) {
                                Label(coverImage == nil ? "Use a photo" : "Change photo", systemImage: "photo")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            if coverImage != nil {
                                Button("Remove photo", role: .destructive) {
                                    withAnimation { coverImage = nil; coverData = nil; coverItem = nil }
                                }
                                .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .tint(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let source = baseID.flatMap { model.preset(id: $0) }
                        if let id = model.createPreset(name: name, base: source, accentIndex: accentIndex, cover: coverData) {
                            dismiss()
                            created(id)
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard name.isEmpty else { return }
                baseID = base?.id
                accentIndex = base?.accentIndex ?? 0
                name = base.map { "\($0.name) Custom" } ?? ""
            }
            .onChange(of: coverItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    withAnimation { coverData = data; coverImage = image }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    /// The card as it will look in the picker.
    private var preview: some View {
        let draft = Preset(id: PresetCatalog.customPrefix + "draft", name: name.isEmpty ? "New Preset" : name, accentIndex: accentIndex)
        return PresetCard(preset: draft, isSelected: true, thumbnail: coverImage) {}
            .scaleEffect(1.25)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
    }

    private func startCard(_ preset: Preset?) -> some View {
        let isOn = baseID == preset?.id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                baseID = preset?.id
                if let preset, coverImage == nil { accentIndex = preset.accentIndex }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let preset {
                        PresetSwatch(preset: preset, corner: 12)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.7)))
                    }
                }
                .frame(width: 74, height: 52)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isOn ? Theme.accent : .clear, lineWidth: 2))
                Text(preset?.name ?? "Blank")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accent : .white.opacity(0.8))
                    .lineLimit(1)
                    .frame(width: 74, alignment: .leading)
            }
        }
        .buttonStyle(PressableStyle())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryText)
            content()
        }
    }
}

/// mood's Quality / Tone control: a title on the left and a vertical wheel of values on the right.
/// Drag up or down to turn it, tap to step forward. The neighbouring values peek above and below.
struct WheelPicker: View {
    let title: String
    let labels: [String]
    /// The value shown now; nil when the preset matches none of them.
    let index: Int?
    let pick: (Int) -> Void

    @State private var dragStart: Int?

    private let step: CGFloat = 26

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                neighbour(-1)
                Text(index.map { labels[$0] } ?? "—")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                neighbour(1)
            }
            .frame(height: 72)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                                         .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.13)))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let start = dragStart ?? (index ?? 0)
                    dragStart = start
                    let moved = Int((-value.translation.height / step).rounded())
                    let target = min(max(start + moved, 0), labels.count - 1)
                    if target != index { turn(to: target) }
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture { turn(to: ((index ?? -1) + 1) % labels.count) }
        .sensoryFeedback(.selection, trigger: index)
    }

    private func neighbour(_ offset: Int) -> some View {
        let position = (index ?? 0) + offset
        return Text(labels.indices.contains(position) ? labels[position] : " ")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
    }

    private func turn(to target: Int) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { pick(target) }
    }
}
