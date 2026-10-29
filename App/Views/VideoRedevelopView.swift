import CameraCore
import SwiftUI

/// Redevelop a recorded Log video in a sheet: a preview frame from the middle of the clip, graded as the
/// chosen preset, grain and halation would make it. Render writes the whole clip, which takes about as long
/// as the clip is long.
struct VideoRedevelopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var presetID = ""
    @State private var grainLevel = GrainLevel.medium
    @State private var halationLevel = EffectLevel.medium
    @State private var preview: UIImage?
    @State private var grader: MetalGrader?
    @State private var isRendering = false

    private var record: CaptureRecord? { model.captures.first { $0.id == recordID } }
    private var progress: Double? { model.videoProgress[recordID] }
    private var renderKey: String { "\(presetID)|\(grainLevel)|\(halationLevel)" }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel") { dismiss() }
                    .disabled(isRendering)
                Spacer()
                Text("Redevelop").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Render") { render() }
                    .disabled(isRendering || presetID.isEmpty)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .padding(.top, 4)

            previewArea
                .frame(height: 210)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.visiblePresets) { preset in
                        PresetCard(preset: preset, isSelected: preset.id == presetID, thumbnail: nil) {
                            presetID = preset.id
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 96)

            HStack(spacing: 10) {
                LevelToggle(title: "GRAIN", level: grainLevel) { grainLevel = grainLevel.next }
                LevelToggle(title: "HALATION", level: halationLevel) { halationLevel = halationLevel.next }
                Spacer()
            }

            if let progress {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                    Text("Rendering \(Int(progress * 100))% · keep the app open")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isRendering)
        .onAppear {
            guard let record else { return }
            presetID = record.presetID
            grainLevel = record.grainLevel
            halationLevel = record.halationLevel
            grader = MetalGrader.makeForBackground()
        }
        .task(id: renderKey) { await updatePreview() }
    }

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08))
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ProgressView()
            }
        }
    }

    /// Grades one frame again after each change; a quick run of changes only grades the last one.
    private func updatePreview() async {
        guard let record, !presetID.isEmpty, let grader else { return }
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        guard let look = await model.videoDevelopLook(presetID: presetID, grain: grainLevel, halation: halationLevel) else { return }
        let source = model.url(.video, for: record)
        let image = await VideoRedeveloper.previewImage(source: source, look: look, grader: grader)
        if !Task.isCancelled, let image { preview = image }
    }

    private func render() {
        guard let record, !presetID.isEmpty else { return }
        isRendering = true
        Task {
            let ok = await model.redevelopVideo(record, presetID: presetID, grain: grainLevel, halation: halationLevel)
            isRendering = false
            if ok { dismiss() }
        }
    }
}
