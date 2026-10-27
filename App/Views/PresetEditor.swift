import CameraCore
import SwiftUI

/// The preset editor, in the three tabs of mood.camera: Emulation (strength and colour balance), Quality
/// (grain, halation, fringing, bloom, film speed) and Tone (contrast, dynamic range, curve, fade, mute, contrast
/// curves). Every change is saved as soon as the control is released.
struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    let presetID: String

    enum Tab: String, CaseIterable {
        case emulation = "EMULATION"
        case quality = "QUALITY"
        case tone = "TONE"
    }

    @State private var tab: Tab = .emulation
    @State private var name = ""
    @State private var grain = 0.0
    @State private var halation = 0.0
    @State private var adjustments = LookAdjustments.neutral
    @State private var loaded = false
    @State private var lut: LUT3D?
    @State private var importSlot: LUTSlot?
    @State private var importing = false
    @State private var busy = false
    @State private var message: String?

    private var preset: Preset? { model.preset(id: presetID) }

    /// The preset as stored, or a placeholder while the list is still loading.
    private var current: Preset { model.preset(id: presetID) ?? Preset(id: presetID, name: name, accentIndex: 0) }

    var body: some View {
        VStack(spacing: 14) {
            nameBar
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .emulation: emulation
                    case .quality: quality
                    case .tone: tone
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 8)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let preset else { return }
            loaded = true
            name = preset.name
            grain = preset.grain
            halation = preset.halation
            adjustments = preset.adjustments
        }
        .task(id: presetID) {
            guard let preset = model.preset(id: presetID) else { return }
            lut = await model.baseLook(for: preset).lut
        }
        .onDisappear(perform: save)
        .background {
            Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                guard let slot = importSlot else { return }
                switch result {
                case .success(let url):
                    busy = true
                    Task {
                        message = await model.importLUT(from: url, presetID: presetID, slot: slot)
                        busy = false
                        lut = await model.baseLook(for: current).lut
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }
        .alert("LUT", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Bars

    private var nameBar: some View {
        HStack(spacing: 12) {
            if let preset {
                PresetArtView(preset: preset, override: nil)
                    .frame(width: 56, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            TextField("Name", text: $name)
                .font(.system(size: 20, weight: .semibold))
                .onSubmit(save)
            Button("Reset") {
                adjustments = .neutral
                grain = preset?.grain ?? 0
                halation = preset?.halation ?? 0
                save()
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(tab == item ? Theme.accent : Theme.secondaryText)
                        .overlay(Capsule().stroke(tab == item ? Theme.accent : Color.white.opacity(0.2), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Tabs

    private var emulation: some View {
        VStack(alignment: .leading, spacing: 18) {
            row {
                continuousTile("Strength", value: $adjustments.filmStrength, range: 0 ... 1) { String(format: "%.0f%%", $0 * 100) }
                continuousTile("Saturation", value: $adjustments.saturation, range: 0 ... 2) { String(format: "%.2f×", $0) }
                continuousTile("Temp", value: $adjustments.temp, range: -1 ... 1) { Regulator.temp.format($0) }
                continuousTile("Tint", value: $adjustments.tint, range: -1 ... 1) { Regulator.tint.format($0) }
                continuousTile("Hue", value: $adjustments.hue, range: -30 ... 30) { Regulator.hue.format($0) }
            }
            section("Colour chart") {
                ColourChartCard(look: adjustments, lut: lut)
            }
            lutSection
        }
    }

    private var quality: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Film speed") {
                chips(FilmSpeed.allCases.map(\.label)) { index in
                    var g = grain
                    FilmSpeed.allCases[index].apply(grain: &g, to: &adjustments)
                    grain = g
                    save()
                }
            }
            row {
                continuousTile("Grain level", value: $grain, range: 0 ... 1) { String(Int(($0 * 10).rounded())) }
                steppedTile("Grain size", labels: ["Fine", "Medium", "Coarse", "Heavy"], values: [1, 2, 3, 4], value: $adjustments.grainSize)
                steppedTile("Halation", labels: ["Off", "Low", "Medium", "High"], values: [0, 1.0 / 3, 2.0 / 3, 1], value: $halation)
                steppedTile("Aberration", labels: ["Off", "Low", "Medium", "High"], values: [0, 1, 2, 4], value: $adjustments.chromaticAberration)
                steppedTile("Bloom", labels: ["Off", "Low", "Medium", "High"], values: [0, 1.0 / 3, 2.0 / 3, 1], value: $adjustments.bloom)
                continuousTile("Sharpness", value: $adjustments.sharpness, range: -0.5 ... 0.5) { Regulator.sharpness.format($0) }
            }
        }
    }

    private var tone: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Contrast curve") {
                chips(ContrastCurve.allCases.map(\.label)) { index in
                    ContrastCurve.allCases[index].apply(to: &adjustments)
                    save()
                }
            }
            row {
                continuousTile("Contrast", value: $adjustments.contrast, range: 0.5 ... 1.5) { String(format: "%.2f×", $0) }
                steppedTile("Dynamic range", labels: ["ZERO", "LOW", "MED", "HIGH", "EXT+"], values: [0, 1.0 / 3, 2.0 / 3, 1, 1.5], value: $adjustments.dynamicRange)
                continuousTile("Shadows", value: $adjustments.shadows, range: -1 ... 1) { Regulator.shadows.format($0) }
                continuousTile("Midtones", value: $adjustments.midpoint, range: -1 ... 1) { Regulator.midpoint.format($0) }
                continuousTile("Highlights", value: $adjustments.highlights, range: -1 ... 1) { Regulator.highlights.format($0) }
                continuousTile("Fade", value: $adjustments.fade, range: 0 ... 1) { String(format: "%.0f%%", $0 * 100) }
                continuousTile("Mute", value: $adjustments.mute, range: 0 ... 1) { String(format: "%.0f%%", $0 * 100) }
                continuousTile("Brightness", value: $adjustments.postExposure, range: -1 ... 1) { Regulator.postExposure.format($0) }
            }
        }
    }

    private var lutSection: some View {
        section("LUTs") {
            VStack(spacing: 10) {
                ForEach(LUTSlot.allCases, id: \.self) { slot in
                    slotRow(slot)
                }
                if busy {
                    ProgressView().tint(Theme.accent)
                }
                Text("3D LUTs in .cube or .lut format. Video falls back to the photo LUT; Apple Log does not.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    /// A horizontal row of dial tiles, scrolled sideways like mood's control strip.
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) { content() }
                .padding(.vertical, 2)
        }
    }

    private func chips(_ titles: [String], action: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(titles.indices, id: \.self) { index in
                    Button(titles[index]) { action(index) }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.chrome))
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func continuousTile(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) -> some View {
        DialTile(title: title, valueText: format(value.wrappedValue)) {
            Slider(value: value, in: range) { editing in
                if !editing { save() }
            }
        }
    }

    /// Stops the slider on fixed values, the way mood's Off / Low / Medium / High controls do.
    private func steppedTile(_ title: String, labels: [String], values: [Double], value: Binding<Double>) -> some View {
        let index = Binding<Double>(
            get: {
                let current = value.wrappedValue
                let nearest = values.indices.min { abs(values[$0] - current) < abs(values[$1] - current) } ?? 0
                return Double(nearest)
            },
            set: { value.wrappedValue = values[min(max(Int($0.rounded()), 0), values.count - 1)] }
        )
        let text = labels[min(max(Int(index.wrappedValue.rounded()), 0), labels.count - 1)]
        return DialTile(title: title, valueText: text) {
            Slider(value: index, in: 0 ... Double(values.count - 1), step: 1) { editing in
                if !editing { save() }
            }
        }
    }

    private func slotRow(_ slot: LUTSlot) -> some View {
        let has = model.hasLUT(presetID, slot: slot)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                Text(has ? "Loaded" : (slot == .video && model.hasLUT(presetID, slot: .photo) ? "Using photo LUT" : "None"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button(has ? "Replace" : "Import") {
                importSlot = slot
                importing = true
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            if has {
                Button(role: .destructive) {
                    model.removeLUT(presetID: presetID, slot: slot)
                    Task { lut = await model.baseLook(for: current).lut }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
        }
    }

    private func save() {
        guard loaded, var updated = preset else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? updated.name : trimmed
        updated.grain = grain
        updated.halation = halation
        updated.adjustments = adjustments
        guard updated != preset else { return }
        model.updatePreset(updated)
    }
}

/// One control in a strip: a title, the current value, and the slider under them.
struct DialTile<Control: View>: View {
    let title: String
    let valueText: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Text(valueText)
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            control()
                .tint(Theme.accent)
        }
        .padding(12)
        .frame(width: 160, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.chrome.opacity(0.55)))
    }
}

/// The colour reference: a grey ramp and coloured patches, drawn through the look as it is now.
struct ColourChartCard: View {
    let look: LookAdjustments
    let lut: LUT3D?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(ColourChart.patches.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, patch in
                        let graded = ColourChart.grade(patch, look: look, lut: lut)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: graded.x, green: graded.y, blue: graded.z))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.09)))
    }
}
