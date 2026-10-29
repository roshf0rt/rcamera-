import CameraCore
import SwiftUI

/// Redevelop a recorded Log video, laid out as Kino's grading sheet: the picture takes the sheet, the looks
/// run along the bottom, and Render writes the clip only once something has changed. The picture is a frame
/// from the middle of the clip, graded as the chosen look, grain and halation would make it.
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

    /// Render is offered only when the look differs from the one the clip has now.
    private var hasChanges: Bool {
        guard let record else { return false }
        return presetID != record.presetID || grainLevel != record.grainLevel || halationLevel != record.halationLevel
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                }
                .disabled(isRendering)
                Spacer()
                Text("Redevelop").font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).hidden()
            }
            .foregroundStyle(.white)
            .padding(.top, 6)

            previewArea
                .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 15))
                Text("Look").font(.system(size: 15, weight: .semibold))
                Spacer()
                LevelToggle(title: "GRAIN", level: grainLevel) { grainLevel = grainLevel.next }
                LevelToggle(title: "HALATION", level: halationLevel) { halationLevel = halationLevel.next }
            }
            .foregroundStyle(.white)

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

            if let progress {
                VStack(spacing: 4) {
                    ProgressView(value: progress).tint(Theme.accent)
                    Text("Rendering \(Int(progress * 100))% · keep the app open")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            HStack(spacing: 12) {
                if hasChanges {
                    Button(action: render) {
                        Text(isRendering ? "Rendering…" : "Render")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .disabled(isRendering || presetID.isEmpty)
                } else {
                    Spacer()
                }
                if let record {
                    ShareLink(item: model.shareURL(for: record)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Theme.chrome))
                    }
                    .disabled(isRendering)
                }
            }
            .padding(.bottom, 8)
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
