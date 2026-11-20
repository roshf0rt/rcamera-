import CameraCore
import SwiftUI

/// Few settings, set on the surface before the dive: quality, Log and its exposure, focus, and the housing keys.
struct UnderwaterSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private static func ettrLabel(_ value: Double) -> String {
        value == 0 ? "Off" : String(format: "+%.1f EV", value)
    }

    var body: some View {
        let engine = model.engine
        NavigationStack {
            Form {
                Section {
                    Picker("Resolution", selection: model.binding(\.videoResolution)) {
                        ForEach(VideoResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Frame rate", selection: model.binding(\.videoFPS)) {
                        let rates = engine.frameRates[model.settings.videoResolution.size.width] ?? []
                        ForEach(rates.isEmpty ? [24, 25, 30, 60] : rates, id: \.self) { Text("\($0) fps").tag($0) }
                    }
                    Picker("Stabilization", selection: model.binding(\.videoStabilization)) {
                        ForEach(VideoStabilization.allCases, id: \.self) { Text($0.label.capitalized).tag($0) }
                    }
                    Toggle("Apple Log", isOn: model.binding(\.appleLogVideo))
                    if model.settings.appleLogVideo {
                        if CaptureSessionController.supportsAppleLog2 {
                            Toggle("Apple Log 2", isOn: model.binding(\.appleLog2))
                        }
                        Picker("Log exposure (ETTR)", selection: model.binding(\.logETTR)) {
                            ForEach(AppSettings.logETTRChoices, id: \.self) { Text(Self.ettrLabel($0)).tag($0) }
                        }
                    }
                    Toggle("AutoMotion", isOn: model.binding(\.autoMotion))
                } header: {
                    Text("Video")
                } footer: {
                    Text("AutoMotion keeps the shutter at 180° (1/\(model.settings.videoFPS * 2) s) and turns only ISO, so motion looks the same through the whole clip; the shutter moves only when ISO runs out. Log is recorded flat and exposed to the right by the chosen amount for cleaner shadows; a highlight guard pulls it back as soon as bright areas start to clip.")
                }
                .disabled(engine.isRecording)

                Section {
                    Picker("Resolution", selection: model.binding(\.photoResolution)) {
                        ForEach(PhotoResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Capture RAW", isOn: model.binding(\.capturesRAW))
                    if model.settings.capturesRAW {
                        Picker("RAW format", selection: model.binding(\.rawFormat)) {
                            ForEach(RAWFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text("Photos are real captures from the sensor, not frames of the video stream.")
                }

                Section {
                    Toggle("Manual focus", isOn: Binding(
                        get: { engine.manualFocus != nil },
                        set: { engine.setManualFocus($0 ? 0.5 : nil) }
                    ))
                    if let position = engine.manualFocus {
                        HStack {
                            Image(systemName: "camera.macro").foregroundStyle(Theme.secondaryText)
                            Slider(value: Binding(get: { position }, set: { engine.setManualFocus($0) }), in: 0 ... 1)
                            Image(systemName: "mountain.2").foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Toggle("Grid", isOn: model.binding(\.isGridEnabled))
                    Toggle("Save location", isOn: model.binding(\.savesLocation))
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Manual focus holds the lens where you put it, so it does not hunt in murky water or on passing fish. A tap on the picture goes back to autofocus. Hold the picture to lock exposure.")
                }

                Section {
                    Toggle("Housing buttons", isOn: model.binding(\.housingKeys))
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(model.housing.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(model.housing.isConnected ? Theme.accent : Theme.secondaryText)
                    }
                    ForEach(HousingRemote.legend, id: \.key) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.key).font(.system(size: 15, weight: .semibold, design: .monospaced))
                            Spacer(minLength: 12)
                            Text(item.action)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                } header: {
                    Text("Housing")
                } footer: {
                    Text("Pair the housing in the iPhone's Bluetooth settings; it connects as a keyboard. The screen stays on while RWater is open.")
                }

                Section {
                    NavigationLink("Focus internals") { FocusInternalsView() }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Lists what the camera has inside for focus, depth and LiDAR, to look for a way to switch LiDAR-assisted focus off. Share the list with the developer.")
                }

                Section {} footer: {
                    Text("RWater \(SettingsView.version)").font(.system(size: 12, design: .monospaced))
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

/// The camera's focus, depth and LiDAR internals, as text to share.
struct FocusInternalsView: View {
    @Environment(AppModel.self) private var model
    @State private var lines: [String] = []

    var body: some View {
        List(lines, id: \.self) { line in
            Text(line)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
        .navigationTitle("Focus internals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: lines.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onAppear { lines = model.engine.focusInternals() }
    }
}
