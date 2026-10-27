import CameraCore
import SwiftUI

/// The horizontal row of preset cards shown above the shutter.
struct PresetPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.presets) { preset in
                        PresetCard(preset: preset, isSelected: preset.id == model.selectedPreset.id) {
                            model.selectPreset(preset.id)
                        }
                        .id(preset.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { proxy.scrollTo(model.selectedPreset.id, anchor: .center) }
        }
        .frame(height: 100)
    }
}

/// The preset's picture: the same soft landscape on every card, graded by that preset's LUT.
/// Until it is ready (it is built in the background) a neutral gradient stands in.
struct PresetArtView: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    /// Shown instead of the landscape, e.g. the user's own photo graded with this preset.
    var override: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = override ?? model.presetArt[preset.id]?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.gradient(preset.accentIndex).opacity(0.5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// The words for a preset's look, e.g. "Teal & Orange · Punchy".
struct PresetTags: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    var limit = 2

    var body: some View {
        Text((model.presetArt[preset.id]?.tags ?? []).prefix(limit).joined(separator: " · "))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// A card for the camera's preset picker: the preset's picture, its name and the words for its look.
struct PresetCard: View {
    let preset: Preset
    let isSelected: Bool
    var thumbnail: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                PresetArtView(preset: preset, override: thumbnail)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    PresetTags(preset: preset)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(preset.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(width: 140, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white)
                        .padding(6)
                }
            }
            .scaleEffect(isSelected ? 1 : 0.96)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
