import CameraCore
import SwiftUI

struct RedevelopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var presetID = ""
    @State private var pushPull = 0.0
    @State private var raw: Data?
    @State private var preview: UIImage?
    @State private var isSaving = false
    @State private var loaded = false
    @State private var original: UIImage?

    private var record: CaptureRecord? { model.captures.first { $0.id == recordID } }

    private var hasChanges: Bool {
        guard let record else { return false }
        return presetID != record.presetID || abs(pushPull - record.evPushPull) > 0.01
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            previewArea
            presetRow.padding(.top, 14)
            evControl.padding(.top, 20)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 16)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .task(id: "\(presetID)-\(pushPull)") { await renderPreview() }
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
            if let shown = hasChanges ? preview : (original ?? preview) {
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

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.presets) { preset in
                    PresetChip(preset: preset, isSelected: preset.id == presetID) { presetID = preset.id }
                }
            }
        }
        .frame(height: 74)
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
            if let record {
                Text("RAW data will be deleted in \(max(model.daysUntilRAWExpires(record), 0)) days")
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    private func load() {
        guard !loaded, let record else { return }
        loaded = true
        presetID = record.presetID
        pushPull = record.evPushPull
        raw = model.rawData(for: record)
        let url = model.url(.processed, for: record)
        Task { original = await Task.detached { UIImage(contentsOfFile: url.path) }.value }
    }

    private func renderPreview() async {
        guard loaded, let raw, let record, let preset = model.preset(id: presetID) else { return }
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        let look = model.look(for: preset)
        let aspect = record.aspect
        let value = pushPull
        let offset = record.rawExposureOffset
        let image = await Task.detached(priority: .userInitiated) {
            PhotoPipeline.preview(raw: raw, look: look, pushPull: value, rawExposureOffset: offset, aspect: aspect)
        }.value
        if !Task.isCancelled, let image { preview = image }
    }

    private func save() async {
        guard let record else { return }
        isSaving = true
        let ok = await model.redevelop(record, presetID: presetID, pushPull: pushPull)
        isSaving = false
        if ok { dismiss() }
    }
}
