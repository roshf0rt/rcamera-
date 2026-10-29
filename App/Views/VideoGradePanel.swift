import CameraCore
import SwiftUI

/// The look a Log video is shown with while it is redeveloped. The viewer's own player plays it graded.
struct VideoGrade: Equatable {
    var presetID: String
    var grain: GrainLevel
    var halation: EffectLevel

    init(_ record: CaptureRecord) {
        presetID = record.presetID
        grain = record.grainLevel
        halation = record.halationLevel
    }
}

/// Redevelop for a Log video: the controls only. The clip itself plays in the viewer, full size, so it can be
/// watched and taken to full screen as any video; this panel takes the place of the viewer's bottom bar and
/// changes the look it plays with. Render appears once the look differs from the clip's, and writes the file.
struct VideoGradePanel: View {
    @Environment(AppModel.self) private var model
    let record: CaptureRecord
    @Binding var grade: VideoGrade
    let close: () -> Void

    @State private var isRendering = false

    /// Room the viewer leaves for the panel under the clip.
    static let height: CGFloat = 276

    private var progress: Double? { model.videoProgress[record.id] }

    private var hasChanges: Bool { grade != VideoGrade(record) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 15))
                Text("Look").font(.system(size: 15, weight: .semibold))
                Spacer()
                LevelToggle(title: "GRAIN", level: grade.grain) { grade.grain = grade.grain.next }
                LevelToggle(title: "HALATION", level: grade.halation) { grade.halation = grade.halation.next }
            }
            .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.visiblePresets) { preset in
                        PresetCard(preset: preset, isSelected: preset.id == grade.presetID, thumbnail: nil) {
                            grade.presetID = preset.id
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
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Theme.chrome))
                }
                .disabled(isRendering)
                if hasChanges {
                    Button(action: render) {
                        Text(isRendering ? "Rendering…" : "Render")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .disabled(isRendering || grade.presetID.isEmpty)
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.88).ignoresSafeArea(edges: .bottom))
        .animation(.smooth(duration: 0.2), value: hasChanges)
    }

    private func render() {
        guard !grade.presetID.isEmpty else { return }
        isRendering = true
        let chosen = grade
        Task {
            let ok = await model.redevelopVideo(record, presetID: chosen.presetID, grain: chosen.grain, halation: chosen.halation)
            isRendering = false
            if ok { close() }
        }
    }
}
