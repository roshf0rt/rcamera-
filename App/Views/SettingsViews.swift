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
                                Text(model.hasAnyLUT(preset.id) ? "LUT" : "No LUT").foregroundStyle(Theme.secondaryText)
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

struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    let presetID: String

    @State private var name = ""
    @State private var grain = 0.0
    @State private var halation = 0.0
    @State private var loaded = false
    @State private var importSlot: LUTSlot?
    @State private var importing = false
    @State private var busy = false
    @State private var message: String?

    private var preset: Preset? { model.preset(id: presetID) }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name).onSubmit(save)
            }
            Section("Film") {
                slider("Grain", value: $grain)
                slider("Halation", value: $halation)
            }
            Section {
                ForEach(LUTSlot.allCases, id: \.self) { slot in
                    slotRow(slot)
                }
                if busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importing…").foregroundStyle(Theme.secondaryText)
                    }
                }
            } header: {
                Text("LUTs")
            } footer: {
                Text("3D LUTs in .cube or .lut format. Video falls back to the photo LUT when it has none of its own; Apple Log does not. Files named \(presetID).cube, \(presetID).video.cube and \(presetID).applelog.cube in the app's LUTs folder are picked up too.")
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
            halation = preset.halation
        }
        .onDisappear(perform: save)
        .background {
            Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                guard let slot = importSlot else { return }
                switch result {
                case .success(let url):
                    busy = true
                    Task {
                        message = await model.importLUT(from: url, presetID: presetID, slot: slot)
                        busy = false
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }
        .alert("LUT", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 84, alignment: .leading)
            Slider(value: value, in: 0 ... 1) { editing in
                if !editing { save() }
            }
            Text("\(Int(value.wrappedValue * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }

    private func slotRow(_ slot: LUTSlot) -> some View {
        let has = model.hasLUT(presetID, slot: slot)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                Text(has ? "Loaded" : (slot == .video && model.hasLUT(presetID, slot: .photo) ? "Using photo LUT" : "None"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button(has ? "Replace" : "Import") {
                importSlot = slot
                importing = true
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            if has {
                Button(role: .destructive) {
                    model.removeLUT(presetID: presetID, slot: slot)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
        }
    }

    private func save() {
        guard loaded, var updated = preset else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? updated.name : trimmed
        updated.grain = grain
        updated.halation = halation
        guard updated != preset else { return }
        model.updatePreset(updated)
    }
}
