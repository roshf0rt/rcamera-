import CameraCore
import SwiftUI

/// Redevelop a photo: another preset, push/pull, grain and halation on or off.
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
    @State private var grainOn = true
    @State private var halationOn = true
    @State private var source: PhotoPipeline.Source?
    @State private var base: CVPixelBuffer?
    @State private var baseEV: Double?
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var preview: UIImage?
    @State private var isSaving = false
    @State private var loaded = false
    @State private var original: UIImage?

    private var record: CaptureRecord? { model.captures.first { $0.id == recordID } }

    private var hasChanges: Bool {
        guard let record else { return false }
        return presetID != record.presetID
            || abs(pushPull - record.evPushPull) > 0.01
            || grainOn != record.grainEnabled
            || halationOn != record.halationEnabled
    }

    private var renderKey: String {
        "\(presetID)|\(pushPull)|\(grainOn)|\(halationOn)|\(source != nil)"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            previewArea
            effects.padding(.top, 12)
            presetRow.padding(.top, 10)
            evControl.padding(.top, 14)
            footer
        }
        .padding(.horizontal, 16)
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
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ProgressView()
            }
            if isSaving { ProgressView().controlSize(.large) }
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 6)
    }

    private var effects: some View {
        HStack(spacing: 10) {
            EffectToggle(title: "GRAIN", isOn: grainOn) { grainOn.toggle() }
            EffectToggle(title: "HALATION", isOn: halationOn) { halationOn.toggle() }
            Spacer()
        }
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
            .onChange(of: loaded) { _, _ in proxy.scrollTo(presetID, anchor: .center) }
        }
        .frame(height: 96)
    }

    private var evControl: some View {
        VStack(spacing: 10) {
            HStack {
                Text("EV (Push/Pull)").font(.system(size: 17)).foregroundStyle(.white)
                Spacer()
                Text(EVScale.format(pushPull))
                    .font(.system(size: 17, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            EVWheel(value: $pushPull, isActive: .constant(true), pinnedOpen: true)
        }
    }

    private var footer: some View {
        Group {
            if let record, record.hasRAW {
                Text("RAW data will be deleted in \(max(model.daysUntilRAWExpires(record), 0)) days")
            } else if record != nil {
                Text("No RAW for this photo: it is redeveloped from the camera image.")
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    private func load() {
        guard !loaded, let record else { return }
        presetID = record.presetID
        pushPull = record.evPushPull
        grainOn = record.grainEnabled
        halationOn = record.halationEnabled
        loaded = true
        let url = model.url(.processed, for: record)
        Task {
            original = await Task.detached { UIImage(contentsOfFile: url.path) }.value
            source = await model.redevelopSource(for: record)
        }
    }

    private func renderPreview() async {
        guard loaded, let source, let record, let preset = model.preset(id: presetID) else { return }

        // Decoding is only needed when push/pull changed; wait a moment so a drag on the wheel decodes once.
        if base == nil || baseEV != pushPull {
            if base != nil { try? await Task.sleep(for: .milliseconds(120)) }
            if Task.isCancelled { return }
            let value = pushPull, aspect = record.aspect, mirror = record.mirrored
            let decoded = await Task.detached(priority: .userInitiated) {
                PhotoPipeline.previewBase(source: source, pushPull: value, aspect: aspect, mirror: mirror, scale: 0.35)
            }.value
            if Task.isCancelled { return }
            base = decoded
            baseEV = value
        }
        guard let base else { return }

        let look = await model.baseLook(for: preset).with(grain: grainOn, halation: halationOn)
        if Task.isCancelled { return }
        let image = await Task.detached(priority: .userInitiated) { PhotoPipeline.gradePreview(base, look: look) }.value
        if !Task.isCancelled, let image { preview = image }
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
        let ok = await model.redevelop(record, presetID: presetID, pushPull: pushPull, grain: grainOn, halation: halationOn)
        isSaving = false
        if ok { dismiss() }
    }
}
