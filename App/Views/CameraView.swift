import CameraCore
import SwiftUI

/// The camera screen. Everything is stacked top to bottom inside the safe area, so no control sits on
/// another: top bar, viewfinder (sized to the aspect and whatever room is left), exposure wheel,
/// shutter row, mode row. Zoom chips, the preset picker and the options panel live inside the viewfinder.
struct CameraView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var showOptions = false
    @State private var showPresets = false
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var evActive = false
    @State private var focusMarker: FocusPoint?
    @State private var pinchStart: Double?

    private struct FocusPoint: Equatable {
        var location: CGPoint
        var id = UUID()
    }

    var body: some View {
        let engine = model.engine
        VStack(spacing: 0) {
            topBar(engine: engine)
                .frame(height: 52)
            viewfinderArea(engine: engine)
            EVWheel(
                value: Binding(get: { engine.evBias }, set: { engine.setEV($0) }),
                isActive: $evActive
            )
            .frame(height: 46)
            .padding(.top, 12)
            shutterRow(engine: engine)
                .frame(height: 92)
                .padding(.top, 8)
            modeRow(engine: engine)
                .frame(height: 44)
                .padding(.bottom, 4)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay { if engine.access == .denied { accessDenied } }
        .fullScreenCover(isPresented: $showGallery) { GalleryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("RCamera", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? engine.message ?? "")
        }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await activate() }
            } else if phase == .background {
                engine.stop()
                model.location.stop()
                model.level.stop()
            }
        }
        .onChange(of: model.settings.isLevelEnabled) { _, enabled in
            enabled ? model.level.start() : model.level.stop()
        }
        .onChange(of: engine.mode) { _, _ in showOptions = false }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alert != nil || model.engine.message != nil },
            set: { shown in
                if !shown {
                    model.alert = nil
                    model.engine.message = nil
                }
            }
        )
    }

    private func activate() async {
        if model.settings.savesLocation { model.location.start() }
        if model.settings.isLevelEnabled { model.level.start() }
        await model.engine.start()
    }

    // MARK: Top bar

    private func topBar(engine: CameraEngine) -> some View {
        HStack(spacing: 8) {
            Button { showSettings = true } label: {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.chrome))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            EffectToggle(title: "Grain", systemName: "circle.dotted", isOn: model.settings.grainEnabled) {
                model.updateSettings { $0.grainEnabled.toggle() }
            }
            EffectToggle(title: "Halation", systemName: "sun.max", isOn: model.settings.halationEnabled) {
                model.updateSettings { $0.halationEnabled.toggle() }
            }
            Spacer(minLength: 0)

            Button { withAnimation(.easeOut(duration: 0.18)) { showOptions.toggle(); showPresets = false } } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(showOptions ? Theme.accent : .white)
                    .frame(width: 56, height: 38)
                    .background(Capsule().fill(Theme.chrome))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Viewfinder

    private func viewfinderArea(engine: CameraEngine) -> some View {
        GeometryReader { geo in
            let ratio = engine.mode == .video ? 16.0 / 9.0 : model.settings.aspect.portraitHeightOverWidth
            let width = min(geo.size.width - 12, geo.size.height / CGFloat(ratio))
            let size = CGSize(width: max(width, 1), height: max(width * CGFloat(ratio), 1))
            viewfinder(engine: engine, size: size)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.easeInOut(duration: 0.22), value: size)
        }
        .padding(.top, 2)
    }

    private func viewfinder(engine: CameraEngine, size: CGSize) -> some View {
        ZStack {
            ViewfinderLayerView(layer: engine.displayLayer)
            if model.settings.isGridEnabled { GridOverlay() }
            if model.settings.isLevelEnabled { LevelOverlay(roll: model.level.roll) }
            if let marker = focusMarker {
                FocusMarker()
                    .position(marker.location)
                    .id(marker.id)
                    .task(id: marker.id) {
                        try? await Task.sleep(for: .seconds(1.2))
                        if focusMarker?.id == marker.id { focusMarker = nil }
                    }
            }
            if let countdown = engine.countdown {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .thin))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
            }
            if engine.showsSwitchBlur {
                Rectangle().fill(.ultraThinMaterial).transition(.opacity)
            }
            bottomOverlay(engine: engine)
            if engine.isRecording { recordingBadge(engine: engine) }
            if showOptions { optionsPanel }
        }
        .animation(.easeInOut(duration: 0.15), value: engine.showsSwitchBlur)
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                if showOptions || showPresets {
                    withAnimation(.easeOut(duration: 0.18)) { showOptions = false; showPresets = false }
                    return
                }
                focusMarker = FocusPoint(location: value.location)
                engine.focus(atNormalized: CGPoint(x: value.location.x / size.width, y: value.location.y / size.height))
            }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? engine.zoomFactor
                    pinchStart = start
                    engine.setContinuousZoom(start * value.magnification)
                }
                .onEnded { _ in pinchStart = nil }
        )
    }

    /// Zoom chips sit on the bottom edge of the picture, like the system camera. The exposure readout and
    /// the preset picker take their place while they are in use.
    private func bottomOverlay(engine: CameraEngine) -> some View {
        VStack {
            Spacer()
            Group {
                if showPresets {
                    PresetPicker()
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.35))
                        .background(.ultraThinMaterial)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if evActive {
                    EVBubble(value: engine.evBias)
                        .padding(.bottom, 12)
                } else if engine.lens != .front, !engine.zoomStops.isEmpty {
                    ZoomChips(stops: engine.zoomStops, active: engine.activeStop, mode: engine.mode) { stop in
                        engine.selectZoom(stop)
                    }
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(Color.black.opacity(0.32)))
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var optionsPanel: some View {
        VStack {
            OptionsPanel(
                mode: model.engine.mode,
                settings: model.settings,
                update: { change in model.updateSettings(change) }
            )
            .padding(.top, 8)
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func recordingBadge(engine: CameraEngine) -> some View {
        VStack {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(Self.format(engine.recordingSeconds))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .padding(.top, 12)
            Spacer()
        }
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Bottom controls

    private func shutterRow(engine: CameraEngine) -> some View {
        HStack {
            Button { showGallery = true } label: {
                ZStack {
                    if let latest = model.captures.first {
                        CaptureThumbnail(record: latest)
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.chrome)
                    }
                    if model.processingCount > 0 { ProgressView().tint(.white) }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(width: 72, alignment: .leading)

            Spacer()
            ShutterButton(mode: engine.mode, isRecording: engine.isRecording, isCapturing: engine.isCapturing) {
                engine.shutterTapped()
            }
            .disabled(engine.access != .granted || engine.isSwitchingMode)
            Spacer()

            presetButton
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 22)
    }

    private var presetButton: some View {
        let preset = model.selectedPreset
        return Button { withAnimation(.easeOut(duration: 0.2)) { showPresets.toggle(); showOptions = false } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.gradient(preset.accentIndex))
                    .frame(width: 58, height: 58)
                    .offset(x: 4, y: 4)
                    .opacity(showPresets ? 0 : 0.8)
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(white: showPresets ? 0.1 : 0.14))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(white: showPresets ? 0.5 : 0.3), lineWidth: 1))
                    .overlay(
                        Text(preset.name.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .padding(4)
                    )
                    .frame(width: 58, height: 58)
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
    }

    private func modeRow(engine: CameraEngine) -> some View {
        ZStack {
            HStack(spacing: 36) {
                modeButton("PHOTO", mode: .photo, engine: engine)
                modeButton("VIDEO", mode: .video, engine: engine)
            }
            HStack {
                Button { engine.flipCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.chrome))
                }
                .buttonStyle(.plain)
                .disabled(engine.isRecording)
                Spacer()
                Button { engine.toggleLock() } label: {
                    HStack(spacing: 5) {
                        Text("AE/AF").font(.system(size: 13, weight: .semibold))
                        Image(systemName: engine.isAELocked ? "lock.fill" : "lock.open.fill").font(.system(size: 12))
                    }
                    .foregroundStyle(engine.isAELocked ? Theme.accent : Theme.secondaryText)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Capsule().fill(Theme.chrome))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    private func modeButton(_ title: String, mode: CaptureMode, engine: CameraEngine) -> some View {
        Button { engine.selectMode(mode) } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(engine.mode == mode ? Theme.accent : Theme.secondaryText)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(engine.isRecording || engine.isSwitchingMode)
    }

    private var accessDenied: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill").font(.system(size: 40))
            Text("Camera access is off").font(.title3.weight(.semibold))
            Text("Allow camera access for RCamera in Settings.").foregroundStyle(Theme.secondaryText)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(.black)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
    }
}

/// A small on/off chip in the top bar, like Lampa's grain and halation switches.
private struct EffectToggle: View {
    let title: String
    let systemName: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemName).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.black : Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(isOn ? Theme.accent : Theme.chrome))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Photo: a light disc in a ring. Video: a red disc that turns into a rounded square while recording.
/// Both fit inside the ring, so nothing sticks out of it.
private struct ShutterButton: View {
    let mode: CaptureMode
    let isRecording: Bool
    let isCapturing: Bool
    let action: () -> Void

    private let ring: CGFloat = 80
    private let ringWidth: CGFloat = 4

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color(white: 0.85), lineWidth: ringWidth)
                if mode == .video {
                    RoundedRectangle(cornerRadius: isRecording ? 7 : 31)
                        .fill(Color(red: 0.92, green: 0.18, blue: 0.14))
                        .frame(width: isRecording ? 30 : 62, height: isRecording ? 30 : 62)
                } else {
                    Circle()
                        .fill(Theme.cardLight)
                        .frame(width: 64, height: 64)
                        .scaleEffect(isCapturing ? 0.88 : 1)
                }
            }
            .frame(width: ring, height: ring)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.2), value: isRecording)
            .animation(.easeOut(duration: 0.1), value: isCapturing)
        }
        .buttonStyle(.plain)
    }
}
