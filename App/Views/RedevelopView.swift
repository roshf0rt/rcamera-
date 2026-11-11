import CameraCore
import CoreVideo
import SwiftUI

/// Redevelop a photo: another preset, push/pull, grain and halation at any level.
///
/// Kept fast by doing the slow part once: the RAW (or the camera's original) is decoded into a reduced
/// "base" only when push/pull changes. Switching presets or effects just re-grades that base on the GPU,
/// and every preset's LUT is loaded in the background when the screen opens.
struct RedevelopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var presetID = ""
    @State private var pushPull = 0.0
    /// Grain and halation of this photo, set finely (after yCam's Texture panel).
    @State private var texture = PhotoTexture()
    /// The panel shown under the photo, and in Texture, whether Grain or Halation.
    @State private var tab = Tab.look
    @State private var textureTab = TextureTab.grain
    /// ARRI only: the mix of its two LUTs for this photo.
    @State private var crossover = 0.0
    /// Shadows moved afterwards, -1 (down) ... 1 (up).
    @State private var shadowLift = 0.0
    /// Portrait photos: the aperture and lens the background is drawn with, and the depth it is drawn from.
    @State private var fNumber = PortraitAperture.standard
    @State private var lens = LensStyle.solis
    @State private var depth: DepthMap?
    @State private var source: PhotoPipeline.Source?
    @State private var base: CVPixelBuffer?
    @State private var baseEV: Double?
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var preview: UIImage?
    @State private var isSaving = false
    @State private var loaded = false
    @State private var original: UIImage?
    /// The saved photo's real long side; `original` is decoded smaller for a 48 MP photo.
    @State private var originalLongSide: Int?
    /// The picture is pinched in: the preview is then made larger, so details can be checked before Render.
    @State private var zoomed = false
    @State private var baseScale: Float = 0.35

    private var record: CaptureRecord? { model.captures.first { $0.id == recordID } }

    private var hasChanges: Bool {
        guard let record else { return false }
        return presetID != record.presetID
            || abs(pushPull - record.evPushPull) > 0.01
            || texture != record.resolvedTexture
            || (presetID == ArriLook.presetID && abs(crossover - recordCrossover(record)) > 0.005)
            || abs(shadowLift - record.shadowLift) > 0.01
            || (record.lensStyle != nil && (fNumber != record.portraitFNumber || lens != record.lensStyle))
    }

    private var renderKey: String {
        "\(presetID)|\(pushPull)|\(texture)|\(presetID == ArriLook.presetID ? crossover : 0)|\(shadowLift)|\(source != nil)|\(fNumber)|\(lens)|\(depth != nil)|\(zoomed)"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar.padding(.horizontal, 16)
            previewArea.padding(.horizontal, 16)
            // One panel at a time, always the same height, so the photo does not jump when the tab changes.
            panel
                .frame(height: 150, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            tabBar
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .task(id: renderKey) { await renderPreview() }
        .task(id: source != nil) { await renderThumbnails() }
        .task { await model.prepareLooks() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button("Cancel") { dismiss() }
                .font(.system(size: 18))
                .foregroundStyle(.white)
            Spacer()
            if let record, model.fileExists(.rawDNG, for: record) {
                ShareLink(item: model.url(.rawDNG, for: record)) {
                    HStack(spacing: 6) {
                        Text("RAW").font(.system(size: 18, weight: .medium))
                        Image(systemName: "arrow.down.to.line")
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(Capsule().fill(Theme.chrome))
                }
            }
            Button { Task { await save() } } label: {
                Text("Done")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(hasChanges ? .white : Theme.secondaryText)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(Capsule().fill(Theme.chrome))
            }
            .disabled(!hasChanges || isSaving)
        }
        .frame(height: 56)
    }

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08))
            if let shown = hasChanges ? (preview ?? original) : (original ?? preview) {
                // Pinch to zoom, drag to pan, double tap for 2.5×: the grade stays on while looking closer.
                ZoomableImage(image: shown, isZoomed: $zoomed)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ProgressView()
            }
            if isSaving { ProgressView().controlSize(.large) }
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 6)
    }

    /// The four panels, after yCam's bottom bar: one shows at a time instead of every control at once.
    enum Tab: String, CaseIterable {
        case look = "Look"
        case light = "Light"
        case texture = "Texture"
        case lens = "Lens"

        var symbol: String {
            switch self {
            case .look: "camera.filters"
            case .light: "sun.max"
            case .texture: "aqi.medium"
            case .lens: "camera.aperture"
            }
        }
    }

    enum TextureTab: String, CaseIterable {
        case grain = "Grain"
        case halation = "Halation"
    }

    /// Lens only for portrait photos, which have a background to draw again.
    private var tabs: [Tab] { record?.lensStyle != nil ? Tab.allCases : [.look, .light, .texture] }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .look:
            VStack(spacing: 12) {
                presetRow
                if presetID == ArriLook.presetID { crossoverControl }
            }
        case .light:
            VStack(spacing: 14) {
                evControl
                LabeledSlider(title: "Shadows", value: $shadowLift, range: -1 ... 1, reset: 0, format: {
                    abs($0) < 0.005 ? "0" : String(format: "%+.0f", $0 * 100)
                })
            }
        case .texture:
            textureControls
        case .lens:
            portraitControls
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { item in
                Button {
                    withAnimation(.smooth(duration: 0.2)) { tab = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 20))
                        Text(item.rawValue).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? Theme.accent : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    /// Grain or Halation, picked by the chips; the chosen one's controls sit under them.
    private var textureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(TextureTab.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { textureTab = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(textureTab == item ? Color.black : .white)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(Capsule().fill(textureTab == item ? Color.white : Theme.chrome))
                            .overlay(alignment: .topTrailing) {
                                // A dot when the effect is off, so the other chip still says so.
                                if isOff(item) { Circle().fill(Theme.secondaryText).frame(width: 6, height: 6).offset(x: -6, y: 6) }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            switch textureTab {
            case .grain: grainControls
            case .halation: halationControls
            }
        }
    }

    private func isOff(_ tab: TextureTab) -> Bool {
        switch tab {
        case .grain: texture.grainAmount < 0.005
        case .halation: !texture.halationOn || texture.halationAmount < 0.005
        }
    }

    /// The preset's own grain size, where the size slider starts and returns on a double tap.
    private var presetGrainSize: Double { model.preset(id: presetID)?.adjustments.grainSize ?? 1 }

    private var grainControls: some View {
        VStack(spacing: 10) {
            LabeledSlider(title: "Amount", value: $texture.grainAmount, range: PhotoTexture.amountRange, reset: 1)
            LabeledSlider(
                title: "Size",
                value: Binding(
                    get: { texture.grainSize ?? presetGrainSize },
                    // The preset's own size is stored as nil, so it follows the preset.
                    set: { texture.grainSize = abs($0 - presetGrainSize) < 0.01 ? nil : $0 }
                ),
                range: PhotoTexture.sizeRange,
                reset: presetGrainSize
            )
        }
    }

    private var halationControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Toggle("Halation", isOn: $texture.halationOn)
                    .labelsHidden()
                    .tint(Theme.accent)
                Picker("Kind", selection: $texture.halation) {
                    ForEach(PhotoTexture.Halation.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!texture.halationOn)
            }
            LabeledSlider(title: "Amount", value: $texture.halationAmount, range: PhotoTexture.amountRange, reset: 1)
                .disabled(!texture.halationOn)
                .opacity(texture.halationOn ? 1 : 0.4)
        }
    }

    /// The Crossover mix a record stands for: its own, or the ARRI preset's when it has none.
    private func recordCrossover(_ record: CaptureRecord) -> Double {
        record.crossover ?? model.preset(id: ArriLook.presetID)?.adjustments.crossover ?? 0
    }

    /// ARRI's two LUTs mixed for this photo: warm highlights and cool shadows to the right, the reverse to the left.
    private var crossoverControl: some View {
        LabeledSlider(title: "Crossover", value: $crossover, range: ArriLook.crossoverRange, reset: 0, format: { String(format: "%+.2f", $0) })
    }

    /// The aperture and lens of a portrait photo's background. Changing them draws the background again.
    private var portraitControls: some View {
        let lenses = LensStyle.allCases.sorted { $0.order < $1.order }
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PortraitAperture.stops, id: \.self) { stop in
                        choice("ƒ" + ApertureTitle.format(stop), selected: stop == fNumber) { fNumber = stop }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lenses, id: \.self) { style in
                        choice(style.label, selected: style == lens) { lens = style }
                    }
                }
            }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? Theme.accent : .white.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var presetRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.visiblePresets) { preset in
                        PresetCard(preset: preset, isSelected: preset.id == presetID, thumbnail: thumbnails[preset.id]) {
                            presetID = preset.id
                        }
                        .id(preset.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(presetID, anchor: .center) }
            .onChange(of: loaded) { _, _ in proxy.scrollTo(presetID, anchor: .center) }
        }
        .frame(height: 96)
    }

    private var evControl: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Exposure").font(.system(size: 16)).foregroundStyle(.white)
                Spacer()
                Text(EVScale.format(pushPull))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(abs(pushPull) > 0.01 ? Theme.accent : Theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            EVWheel(value: $pushPull, isActive: .constant(true), pinnedOpen: true)
        }
    }

    private func load() {
        guard !loaded, let record else { return }
        presetID = record.presetID
        pushPull = record.evPushPull
        texture = record.resolvedTexture
        crossover = recordCrossover(record)
        shadowLift = record.shadowLift
        fNumber = record.portraitFNumber ?? PortraitAperture.standard
        lens = record.lensStyle ?? .solis
        loaded = true
        let url = model.url(.processed, for: record)
        Task {
            let decoded = await Task.detached(priority: .userInitiated) {
                (ImageDecoding.image(at: url, maxPixels: ImageDecoding.viewerPixels), ImageDecoding.pixelLongSide(at: url))
            }.value
            original = decoded.0
            originalLongSide = decoded.1
            source = await model.redevelopSource(for: record)
            depth = await model.depthMap(for: record)
        }
    }

    private func renderPreview() async {
        guard loaded, let source, let record, let preset = model.preset(id: presetID) else { return }

        // Decoding is only needed when push/pull changed; wait a moment so a drag on the wheel decodes once.
        // Zoomed in, the base is as large as the photo comes out (up to about 4000 px), so detail is real.
        let scale = zoomed ? detailScale : 0.35
        if base == nil || baseEV != pushPull || baseScale != scale {
            if base != nil { try? await Task.sleep(for: .milliseconds(120)) }
            if Task.isCancelled { return }
            let value = pushPull, aspect = record.aspect, mirror = record.mirrored
            let decoded = await Task.detached(priority: .userInitiated) {
                PhotoPipeline.previewBase(source: source, pushPull: value, aspect: aspect, mirror: mirror, scale: scale)
            }.value
            if Task.isCancelled { return }
            base = decoded
            baseEV = value
            baseScale = scale
        }
        guard let base else { return }

        var look = await model.photoLook(
            for: preset,
            texture: texture,
            crossover: presetID == ArriLook.presetID ? crossover : nil,
            shadowLift: shadowLift
        )
        let pass = depth.flatMap {
            PhotoPipeline.portraitPass(
                PhotoPipeline.PortraitDepth(map: $0, fNumber: fNumber, lens: lens),
                aspect: record.aspect,
                width: CVPixelBufferGetWidth(base),
                height: CVPixelBufferGetHeight(base)
            )
        }
        if pass != nil { look = look.with { lens.apply(to: &$0) } }
        if Task.isCancelled { return }
        let image = await Task.detached(priority: .userInitiated) { PhotoPipeline.gradePreview(base, look: look, portrait: pass) }.value
        if !Task.isCancelled, let image { preview = image }
    }

    /// The preview scale at which the photo's long side is about 4000 px, capped at full size.
    private var detailScale: Float {
        guard let longSide = originalLongSide.map(CGFloat.init)
            ?? original.map({ max($0.size.width, $0.size.height) * $0.scale })
        else { return 1 }
        return Float(min(1, max(0.35, 4000 / max(longSide, 1))))
    }

    /// This photo, small, in every preset: the most honest way to compare looks.
    private func renderThumbnails() async {
        guard let source, let record, thumbnails.isEmpty else { return }
        let aspect = record.aspect, mirror = record.mirrored
        let small = await Task.detached(priority: .utility) {
            PhotoPipeline.previewBase(source: source, pushPull: 0, aspect: aspect, mirror: mirror, scale: 0.08)
        }.value
        guard let small else { return }
        for preset in model.visiblePresets {
            if Task.isCancelled { return }
            let look = await model.baseLook(for: preset).with(grain: false, halation: true)
            if let image = await Task.detached(priority: .utility, operation: { PhotoPipeline.gradePreview(small, look: look) }).value {
                thumbnails[preset.id] = image
            }
        }
    }

    private func save() async {
        guard let record else { return }
        isSaving = true
        let ok = await model.redevelop(
            record,
            presetID: presetID,
            pushPull: pushPull,
            texture: texture,
            crossover: crossover,
            portraitFNumber: fNumber,
            lens: lens,
            shadowLift: shadowLift
        )
        isSaving = false
        if ok { dismiss() }
    }
}
