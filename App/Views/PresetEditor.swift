import CameraCore
import PhotosUI
import SwiftUI

/// The preset editor, in the three tabs of mood.camera: Emulation (strength and colour balance), Quality
/// (grain, halation, fringing, bloom, film speed) and Tone (contrast, dynamic range, curve, fade, mute, contrast
/// curves). A live preview on top shows the look on a test picture; holding it shows the picture untouched.
/// Every change is saved as soon as the control is released.
struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    let presetID: String

    enum Tab: String, CaseIterable {
        case emulation = "EMULATION"
        case quality = "QUALITY"
        case tone = "TONE"
    }

    /// What the preview shows.
    enum PreviewSource: Equatable {
        case lastPhoto
        case scene
        case picked
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

    @State private var look: FilmLook?
    @State private var source: PreviewSource = .lastPhoto
    @State private var base: PreviewBase?
    @State private var graded: UIImage?
    @State private var original: UIImage?
    @State private var showOriginal = false
    @State private var picked: PhotosPickerItem?

    private var preset: Preset? { model.preset(id: presetID) }

    /// The preset as stored, or a placeholder while the list is still loading.
    private var current: Preset { model.preset(id: presetID) ?? Preset(id: presetID, name: name, accentIndex: 0) }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            nameBar
            previewCard
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
                .padding(.top, 4)
                .padding(.bottom, 40)
                .id(tab)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .scrollIndicators(.hidden)
            .animation(.spring(response: 0.35, dampingFraction: 0.88), value: tab)
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
        .task(id: presetID) { await reloadLUT() }
        .task(id: source) { await loadBase() }
        .task(id: renderKey) { await render() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let buffer = await Task.detached(priority: .userInitiated) { PhotoPipeline.previewBase(data: data) }.value
                if let buffer {
                    source = .picked
                    setBase(buffer)
                }
            }
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
                        await reloadLUT()
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

    // MARK: Preview

    /// A decoded preview picture, wrapped so a new one is a new identity for `renderKey`.
    final class PreviewBase: @unchecked Sendable {
        let buffer: CVPixelBuffer
        init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
    }

    private struct RenderKey: Equatable {
        var adjustments: LookAdjustments
        var grain: Double
        var halation: Double
        var base: ObjectIdentifier?
        var look: ObjectIdentifier?
    }

    private var renderKey: RenderKey {
        RenderKey(
            adjustments: adjustments,
            grain: grain,
            halation: halation,
            base: base.map { ObjectIdentifier($0) },
            look: look.map { ObjectIdentifier($0) }
        )
    }

    private var previewCard: some View {
        ZStack {
            Color(white: 0.06)
            if let shown = showOriginal ? original : graded {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(showOriginal ? "ORIGINAL" : "HOLD TO COMPARE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(showOriginal ? Color.black : .white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(showOriginal ? Theme.accent : Color.black.opacity(0.45)))
                .padding(10)
                .animation(.easeOut(duration: 0.15), value: showOriginal)
        }
        .overlay(alignment: .bottom) { sourceBar.padding(10) }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
            showOriginal = pressing
            if pressing { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        })
        .padding(.horizontal, 16)
    }

    private var sourceBar: some View {
        HStack(spacing: 6) {
            sourceChip("Last photo", active: source == .lastPhoto) { source = .lastPhoto }
            sourceChip("Scene", active: source == .scene) { source = .scene }
            PhotosPicker(selection: $picked, matching: .images) {
                chipLabel(source == .picked ? "Your photo" : "Choose…", active: source == .picked)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func sourceChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, active: active) }
            .buttonStyle(PressableStyle())
    }

    private func chipLabel(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Color.black : .white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(active ? Theme.accent : Color.black.opacity(0.5)))
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func reloadLUT() async {
        guard let preset = model.preset(id: presetID) else { return }
        let resolved = await model.baseLook(for: preset)
        lut = resolved.lut
        look = resolved
    }

    /// The newest photo's untouched camera image, or the built-in scene when there is none.
    private func loadBase() async {
        switch source {
        case .picked:
            return
        case .scene:
            let buffer = await Task.detached(priority: .userInitiated) { PhotoPipeline.sampleScene() }.value
            if let buffer { setBase(buffer) }
        case .lastPhoto:
            let record = model.captures.first { $0.kind == .photo }
            let url = record.map { model.fileExists(.original, for: $0) ? model.url(.original, for: $0) : model.url(.processed, for: $0) }
            let buffer = await Task.detached(priority: .userInitiated) { () -> CVPixelBuffer? in
                if let url, let data = try? Data(contentsOf: url), let buffer = PhotoPipeline.previewBase(data: data) {
                    return buffer
                }
                return PhotoPipeline.sampleScene()
            }.value
            if let buffer { setBase(buffer) }
        }
    }

    private func setBase(_ buffer: CVPixelBuffer) {
        let wrapped = PreviewBase(buffer)
        base = wrapped
        Task {
            original = await Task.detached(priority: .userInitiated) { PhotoPipeline.gradePreview(wrapped.buffer, look: .identity) }.value
        }
    }

    /// Re-grades the preview. Slider moves restart this task, so only the latest values are drawn.
    private func render() async {
        guard let base, let look else { return }
        try? await Task.sleep(for: .milliseconds(12))
        guard !Task.isCancelled else { return }
        let live = look.with(grain: grain, halation: halation, adjustments: adjustments)
        let image = await Task.detached(priority: .userInitiated) { PhotoPipeline.gradePreview(base.buffer, look: live) }.value
        guard !Task.isCancelled, let image else { return }
        graded = image
    }

    // MARK: Bars

    private var nameBar: some View {
        HStack(spacing: 12) {
            if let preset {
                PresetSwatch(preset: preset)
                    .frame(width: 40, height: 40)
            }
            TextField("Name", text: $name)
                .font(.system(size: 22, weight: .semibold))
                .onSubmit(save)
            Button("Reset") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    adjustments = .neutral
                    grain = preset?.grain ?? 0
                    halation = preset?.halation ?? 0
                }
                save()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.accent.opacity(0.14)))
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(tab == item ? Color.black : Theme.secondaryText)
                        .background {
                            if tab == item {
                                Capsule().fill(Theme.accent).matchedGeometryEffect(id: "tab", in: tabSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.chrome.opacity(0.7)))
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tab)
    }

    @Namespace private var tabSpace

    // MARK: Tabs

    private var emulation: some View {
        VStack(alignment: .leading, spacing: 18) {
            grid {
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
                chips(FilmSpeed.allCases.map(\.label), selected: selectedSpeed) { index in
                    var g = grain
                    FilmSpeed.allCases[index].apply(grain: &g, to: &adjustments)
                    grain = g
                    save()
                }
            }
            grid {
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
                chips(ContrastCurve.allCases.map(\.label), selected: selectedCurve) { index in
                    ContrastCurve.allCases[index].apply(to: &adjustments)
                    save()
                }
            }
            grid {
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

    /// The film speed whose values the preset has now, if any.
    private var selectedSpeed: Int? {
        FilmSpeed.allCases.firstIndex { speed in
            var g = grain
            var a = adjustments
            speed.apply(grain: &g, to: &a)
            return g == grain && a == adjustments
        }
    }

    /// The contrast curve whose values the preset has now, if any.
    private var selectedCurve: Int? {
        ContrastCurve.allCases.firstIndex { curve in
            var a = adjustments
            curve.apply(to: &a)
            return a == adjustments
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
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    /// Two tiles per row, so every control is on screen without sideways scrolling.
    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: columns, spacing: 10) { content() }
    }

    /// A sideways row of chips that runs to the screen edges instead of being cut at the padding.
    private func chips(_ titles: [String], selected: Int?, action: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(titles.indices, id: \.self) { index in
                    let isOn = index == selected
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action(index) }
                    } label: {
                        Text(titles[index])
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(isOn ? Theme.accent : Theme.chrome))
                            .foregroundStyle(isOn ? Color.black : .white)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
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
                    Task { await reloadLUT() }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chrome.opacity(0.55)))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.chrome.opacity(0.55)))
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
