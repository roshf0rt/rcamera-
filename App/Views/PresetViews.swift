import CameraCore
import PhotosUI
import SwiftUI

/// How a preset's card looks, from the RCamera card designs (FilterPicker.swift and FilterCardsSVG):
/// a dark card with a colour strip, filled with the gradient when selected. The preset's `accentIndex`
/// picks the design, so a custom preset copied from a built-in one keeps that one's card.
struct PresetCardStyle {
    let subtitle: String
    let colors: [Color]
    /// Light gradients need dark text when the card is filled.
    var light = false
    /// Filled with this instead of the gradient when selected; the strip then stays visible.
    var selectedFill: Color?

    /// Bottom-left to top-right, as in the designs.
    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// In the order of the built-in presets: JaneSu, Carbon, Clear, Drift, Mosaic, Rise, Sienna, Silver, Solstice, Velvet.
    static let all: [PresetCardStyle] = [
        PresetCardStyle(subtitle: "Film color", colors: hex(0x218DFD, 0x7066D8, 0xF13722), light: true, selectedFill: hex(0xE9E9DF)[0]),
        PresetCardStyle(subtitle: "Mono · Contrast", colors: hex(0x33383C, 0x9DA1A0, 0xE0DED5)),
        PresetCardStyle(subtitle: "Clean · Neutral", colors: hex(0xE7E7DD, 0xC5C8BD), light: true),
        PresetCardStyle(subtitle: "Soft · Airy", colors: hex(0x476D74, 0x9CB8A9, 0xD6D6C4)),
        PresetCardStyle(subtitle: "Color · Vivid", colors: hex(0x4058A0, 0x996DA2, 0xEBCB8B)),
        PresetCardStyle(subtitle: "Custom · Color", colors: hex(0x1160A3, 0x7867A3, 0xDD87B0)),
        PresetCardStyle(subtitle: "Warm · Film", colors: hex(0xA84B32, 0xE38A50, 0xF2CA8F)),
        PresetCardStyle(subtitle: "Mono · Soft", colors: hex(0x676B6E, 0xC5C7C4, 0xECECE3)),
        PresetCardStyle(subtitle: "Warm · Light", colors: hex(0xBC703B, 0xE0B15D, 0xF7D99B)),
        PresetCardStyle(subtitle: "Grain · Cool green", colors: hex(0x008873, 0x85A764, 0xEDBD53)),
    ]

    static func of(_ preset: Preset) -> PresetCardStyle {
        all[((preset.accentIndex % all.count) + all.count) % all.count]
    }

    private static func hex(_ values: UInt32...) -> [Color] {
        values.map { rgb in
            Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
        }
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
                    ForEach(model.presets) { preset in
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

/// A preset card: its subtitle and name over a dark card with the colour strip, or over the gradient when
/// selected. With a `thumbnail` (Redevelop) the card shows that photo instead.
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
    /// The redevelop thumbnail, or the photo the user chose for a custom preset.
    private var picture: UIImage? { thumbnail ?? (preset.isCustom ? model.cover(for: preset.id) : nil) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.corner, style: .continuous) }
    private var foreground: Color { isSelected && style.light && picture == nil ? .black : .white }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                background
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(foreground.opacity(isSelected ? 0.65 : 0.5))
                        .lineLimit(1)
                    Text(preset.name)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    if picture == nil, !isSelected || style.selectedFill != nil {
                        RoundedRectangle(cornerRadius: 1.5).fill(style.gradient).frame(height: 5)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 9)
            }
            .frame(width: Self.width, height: Self.height)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.16), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel("\(preset.name), \(style.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var background: some View {
        if let picture {
            Image(uiImage: picture)
                .resizable()
                .scaledToFill()
                .frame(width: Self.width, height: Self.height)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
        } else if isSelected {
            if let fill = style.selectedFill { shape.fill(fill) } else { shape.fill(style.gradient) }
        } else {
            shape.fill(Color(white: 0.08))
        }
    }
}

/// A small square of the preset's card colours, for lists and the camera's preset button.
struct PresetSwatch: View {
    let preset: Preset
    var corner: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous).fill(PresetCardStyle.of(preset).gradient)
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
                                ForEach(model.presets) { preset in startCard(preset) }
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
