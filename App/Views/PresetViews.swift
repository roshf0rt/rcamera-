import CameraCore
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
                                Label("Edit", systemImage: "slider.horizontal.3")
                            }
                            if let url = model.exportPreset(id: preset.id) {
                                ShareLink(item: url) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                            }
                            if preset.isCustom {
                                Button(role: .destructive) { model.deletePreset(id: preset.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    Button { model.addPreset() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                            Text("New").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 84, height: PresetCard.height)
                        .background(RoundedRectangle(cornerRadius: PresetCard.corner, style: .continuous).fill(Color(white: 0.08)))
                    }
                    .buttonStyle(.plain)
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

    private var style: PresetCardStyle { PresetCardStyle.of(preset) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.corner, style: .continuous) }
    private var foreground: Color { isSelected && style.light && thumbnail == nil ? .black : .white }

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
                    if thumbnail == nil, !isSelected || style.selectedFill != nil {
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
        if let thumbnail {
            Image(uiImage: thumbnail)
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
