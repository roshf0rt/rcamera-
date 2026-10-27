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
                                Capsule().fill(Theme.gradient(preset.accentIndex)).frame(width: 28, height: 6)
                                Text(preset.name)
                                Spacer()
                                Text(model.hasLUT(preset.id) ? "LUT" : "No LUT").foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }

                Section("Camera") {
                    Toggle("Grid", isOn: model.binding(\.isGridEnabled))
                    Toggle("Level", isOn: model.binding(\.isLevelEnabled))
                    Toggle("Mirror front camera", isOn: model.binding(\.mirrorFrontCamera))
                    Toggle("Capture RAW", isOn: model.binding(\.capturesRAW))
                    Toggle("Save location", isOn: model.binding(\.savesLocation))
                }

                Section {
                    Picker("Resolution", selection: model.binding(\.videoResolution)) {
                        ForEach(VideoResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Frame rate", selection: model.binding(\.videoFPS)) {
                        ForEach([24, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                    }
                    Toggle("Stabilization", isOn: model.binding(\.videoStabilization))
                } header: {
                    Text("Video")
                } footer: {
                    Text("RAW files are kept for \(CaptureStore.rawRetentionDays) days so you can redevelop photos, then deleted. The processed photo stays.")
                }
                .disabled(model.engine.isRecording)
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

struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    let presetID: String

    @State private var name = ""
    @State private var grain = 0.0
    @State private var importing = false
    @State private var loaded = false

    private var preset: Preset? { model.preset(id: presetID) }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name).onSubmit(save)
            }
            Section("Grain") {
                HStack {
                    Slider(value: $grain, in: 0 ... 1) { editing in
                        if !editing { save() }
                    }
                    Text("\(Int(grain * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(model.hasLUT(presetID) ? "LUT loaded" : "No LUT").foregroundStyle(Theme.secondaryText)
                }
                Button("Import LUT…") { importing = true }
                if model.hasLUT(presetID) {
                    Button("Remove LUT", role: .destructive) { model.removeLUT(presetID: presetID) }
                }
            } header: {
                Text("LUT")
            } footer: {
                Text("Pick a 3D LUT file: .cube (Adobe/Resolve) or .lut (35³-style binary). It is validated, then stored for this preset. You can also bundle files named \(presetID).cube in the app's LUTs folder.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(preset?.name ?? "Preset")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let preset else { return }
            loaded = true
            name = preset.name
            grain = preset.grain
        }
        .onDisappear(perform: save)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                model.importLUT(from: url, presetID: presetID)
            }
        }
        .alert("LUT", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? "")
        }
    }

    private func save() {
        guard loaded, var updated = preset else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? updated.name : trimmed
        updated.grain = grain
        guard updated != preset else { return }
        model.updatePreset(updated)
    }
}
