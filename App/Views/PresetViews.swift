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

struct PresetCard: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.hasAnyLUT(preset.id) ? "LUT" : "No LUT")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.5) : Theme.secondaryText)
                Spacer(minLength: 0)
                Text(preset.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Capsule()
                    .fill(Theme.gradient(preset.accentIndex))
                    .frame(height: 5)
                    .padding(.top, 8)
            }
            .padding(13)
            .frame(width: 150, height: 92)
            .background(RoundedRectangle(cornerRadius: 22).fill(isSelected ? Theme.cardLight : Theme.chromeDark))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isSelected ? Color.white : Color(white: 0.25), lineWidth: isSelected ? 2.5 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Compact card with initials, used on the Redevelop screen.
struct PresetChip: View {
    let preset: Preset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(preset.initials).font(.system(size: 28, weight: .bold))
                    Spacer(minLength: 6)
                    Text(preset.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Capsule().fill(Theme.gradient(preset.accentIndex)).frame(height: 5)
            }
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 150, height: 72)
            .background(RoundedRectangle(cornerRadius: 20).fill(isSelected ? Theme.cardLight : Theme.chromeDark))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? Color.clear : Color(white: 0.25), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
