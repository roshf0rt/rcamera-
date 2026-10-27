import CameraCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    ForEach(model.presets) { preset in
                        NavigationLink {
                            PresetEditorView(presetID: preset.id)
                        } label: {
                            HStack(spacing: 12) {
                                PresetArtView(preset: preset)
                                    .frame(width: 52, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                    PresetTags(preset: preset, limit: 3)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Grid", isOn: model.binding(\.isGridEnabled))
                    Toggle("Level", isOn: model.binding(\.isLevelEnabled))
                    Toggle("Mirror front camera", isOn: model.binding(\.mirrorFrontCamera))
                    Toggle("Capture RAW", isOn: model.binding(\.capturesRAW))
                    Toggle("Save location", isOn: model.binding(\.savesLocation))
                    Toggle("Volume buttons take photos", isOn: model.binding(\.volumeShutter))
                        .onChange(of: model.settings.volumeShutter) { _, on in
                            model.syncVolumeShutter(active: on)
                        }
                    Picker("Extra zoom stop", selection: model.binding(\.digitalZoomStop)) {
                        ForEach(DigitalZoomStop.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Lenses (0.5×, 1×, telephoto) are detected automatically. The extra stop is a crop of the main camera.")
                }

                Section {
                    Picker("Resolution", selection: model.binding(\.videoResolution)) {
                        ForEach(VideoResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Frame rate", selection: model.binding(\.videoFPS)) {
                        ForEach([24, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                    }
                    Picker("Stabilization", selection: model.binding(\.videoStabilization)) {
                        ForEach(VideoStabilization.allCases, id: \.self) { Text($0.label.capitalized).tag($0) }
                    }
                    Toggle("Apple Log", isOn: model.binding(\.appleLogVideo))
                } header: {
                    Text("Video")
                } footer: {
                    Text("Apple Log is used by default when the iPhone supports it and the preset has an Apple Log LUT; otherwise normal video is recorded. Cinematic stabilization delays the viewfinder.")
                }
                .disabled(model.engine.isRecording)

                Section {} footer: {
                    Text("RAW files are kept for \(CaptureStore.rawRetentionDays) days so you can redevelop photos, then deleted. The processed photo stays.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
