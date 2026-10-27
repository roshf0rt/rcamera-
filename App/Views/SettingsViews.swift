import CameraCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showNewPreset = false

    private func presetRow(_ preset: Preset) -> some View {
        NavigationLink {
            PresetEditorView(presetID: preset.id)
        } label: {
            HStack(spacing: 12) {
                PresetSwatch(preset: preset, corner: 7)
                    .frame(width: 52, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                    Text(PresetCardStyle.subtitle(of: preset))
                        .font(.system(size: 12))
                        .foregroundStyle(preset.isCustom ? Theme.accent.opacity(0.8) : Theme.secondaryText)
                }
            }
        }
    }

    /// "0.1.0 (build 57)": the build is the CI run number, so every IPA can be told apart.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (build \(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // One list in the camera's order: hold a row and drag to move it, or use Edit.
                    ForEach(model.presets) { preset in
                        presetRow(preset)
                            .swipeActions(edge: .trailing, allowsFullSwipe: preset.isCustom) {
                                if preset.isCustom {
                                    Button(role: .destructive) {
                                        withAnimation { model.deletePreset(id: preset.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                    .onMove { source, destination in
                        withAnimation { model.movePresets(from: source, to: destination) }
                    }
                    Button {
                        showNewPreset = true
                    } label: {
                        Label("New preset", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("Presets")
                        Spacer()
                        EditButton()
                            .font(.system(size: 13, weight: .semibold))
                            .textCase(nil)
                    }
                } footer: {
                    Text("Hold a preset and drag it to change the order on the camera. Built-in presets change only film speed, contrast curve, dynamic range and their card; make your own to change everything. Swipe your own presets to delete them.")
                }

                Section {
                    Toggle("Grid", isOn: model.binding(\.isGridEnabled))
                    Toggle("Level", isOn: model.binding(\.isLevelEnabled))
                    Toggle("Mirror front camera", isOn: model.binding(\.mirrorFrontCamera))
                    Toggle("Capture RAW", isOn: model.binding(\.capturesRAW))
                    if model.settings.capturesRAW {
                        Picker("RAW format", selection: model.binding(\.rawFormat)) {
                            ForEach(RAWFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
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
                        let rates = model.engine.frameRates[model.settings.videoResolution.size.width] ?? []
                        ForEach(rates.isEmpty ? [24, 30, 60] : rates, id: \.self) { Text("\($0) fps").tag($0) }
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RAW files are kept for \(CaptureStore.rawRetentionDays) days so you can redevelop photos, then deleted. The processed photo stays.")
                        Text("RCamera \(Self.version)").font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .sheet(isPresented: $showNewPreset) {
                NewPresetSheet(base: nil) { _ in }
            }
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
