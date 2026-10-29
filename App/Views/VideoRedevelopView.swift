import CameraCore
import SwiftUI

/// Redevelop a recorded Log video: another preset, grain and halation. The clip is graded again from its
/// Apple Log frames, one frame at a time, so it takes about as long as the clip is long.
struct VideoRedevelopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var presetID = ""
    @State private var grainLevel = GrainLevel.medium
    @State private var halationLevel = EffectLevel.medium
    @State private var isRunning = false

    private var record: CaptureRecord? { model.captures.first { $0.id == recordID } }
    private var progress: Double? { model.videoProgress[recordID] }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Cancel") { dismiss() }
                    .disabled(isRunning)
                    .foregroundStyle(.white)
                Spacer()
                Text("Redevelop").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button("Develop") { develop() }
                    .disabled(isRunning || presetID.isEmpty)
                    .foregroundStyle(isRunning || presetID.isEmpty ? Theme.secondaryText : .white)
            }
            .font(.system(size: 18))
            .frame(height: 46)

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
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 8)
            }

            Text("The clip is graded frame by frame from its Apple Log file. Keep the app open until it finishes.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            guard let record else { return }
            presetID = record.presetID
            grainLevel = record.grainLevel
            halationLevel = record.halationLevel
        }
    }

    private func develop() {
        guard let record, !presetID.isEmpty else { return }
        isRunning = true
        Task {
            let ok = await model.redevelopVideo(record, presetID: presetID, grain: grainLevel, halation: halationLevel)
            isRunning = false
            if ok { dismiss() }
        }
    }
}
