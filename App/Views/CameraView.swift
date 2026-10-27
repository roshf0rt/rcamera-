import CameraCore
import SwiftUI

/// The camera screen, laid out like Lampa inside the safe area.
///
/// Top bar, then the viewfinder, then a fixed control block (exposure wheel, shutter row, mode row).
/// Photo: the picture ends exactly where the control block starts. Video: the 16:9 picture runs full
/// width and the control block sits on a dark band over its lower part, like the system camera.
/// Zoom chips and the flip button always sit on one line just above the control block, on the picture.
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

    private let topBarHeight: CGFloat = 50
    private let controlsHeight: CGFloat = 196
    private let zoomLineHeight: CGFloat = 56

    var body: some View {
        let engine = model.engine
        GeometryReader { geo in
            let layout = layout(in: geo.size, mode: engine.mode)
            ZStack(alignment: .topLeading) {
                Color.black

                viewfinder(engine: engine, size: layout.preview.size)
                    .frame(width: layout.preview.width, height: layout.preview.height)
                    .offset(x: layout.preview.minX, y: layout.preview.minY)

                if engine.mode == .video {
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .frame(width: geo.size.width, height: controlsHeight + 24)
                        .offset(y: geo.size.height - controlsHeight - 24)
                        .allowsHitTesting(false)
                }

                zoomLine(engine: engine)
                    .frame(width: geo.size.width, height: zoomLineHeight)
                    .offset(y: geo.size.height - controlsHeight - zoomLineHeight)

                if showPresets {
                    PresetPicker()
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55))
                        .background(.ultraThinMaterial)
                        .frame(width: geo.size.width)
                        .offset(y: geo.size.height - controlsHeight - 120)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                controls(engine: engine)
                    .frame(width: geo.size.width, height: controlsHeight)
                    .offset(y: geo.size.height - controlsHeight)

                topBar(engine: engine)
                    .frame(width: geo.size.width, height: topBarHeight)

                if showOptions {
                    OptionsPanel(
                        mode: engine.mode,
                        settings: model.settings,
                        update: { change in model.updateSettings(change) }
                    )
                    .frame(width: geo.size.width)
                    .offset(y: topBarHeight + 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: engine.mode)
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

    private struct Layout {
        var preview: CGRect
    }

    private func layout(in size: CGSize, mode: CaptureMode) -> Layout {
        let width = size.width - 12
        if mode == .video {
            let height = min(width * 16 / 9, size.height - topBarHeight)
            let fitted = height * 9 / 16
            return Layout(preview: CGRect(x: (size.width - fitted) / 2, y: topBarHeight, width: fitted, height: height))
        }
        let ratio = CGFloat(model.settings.aspect.portraitHeightOverWidth)
        let room = size.height - topBarHeight - controlsHeight
        let previewWidth = min(width, room / ratio)
        let previewHeight = previewWidth * ratio
        // Bottom-aligned, so the zoom chips always sit on the picture.
        return Layout(preview: CGRect(x: (size.width - previewWidth) / 2, y: topBarHeight + room - previewHeight, width: previewWidth, height: previewHeight))
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
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.chrome))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            if engine.isRecording {
                recordingBadge(engine: engine)
            } else {
                EffectToggle(title: "GRAIN", isOn: model.settings.grainEnabled) {
                    model.updateSettings { $0.grainEnabled.toggle() }
                }
                EffectToggle(title: "HALATION", isOn: model.settings.halationEnabled) {
                    model.updateSettings { $0.halationEnabled.toggle() }
                }
            }
            Spacer(minLength: 0)

            Button { withAnimation(.easeOut(duration: 0.18)) { showOptions.toggle(); showPresets = false } } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(showOptions ? Theme.accent : .white)
                    .frame(width: 56, height: 36)
                    .background(Capsule().fill(Theme.chrome))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Viewfinder

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

    /// Zoom chips centered, flip button on the right, as in Lampa. The exposure readout replaces the chips
    /// while the wheel turns.
    private func zoomLine(engine: CameraEngine) -> some View {
        ZStack {
            if evActive {
                EVBubble(value: engine.evBias)
            } else if engine.lens != .front, !engine.zoomStops.isEmpty, !showPresets {
                ZoomChips(stops: engine.zoomStops, active: engine.activeStop, mode: engine.mode) { stop in
                    engine.selectZoom(stop)
                }
                .padding(.horizontal, 4)
                .background(Capsule().fill(Color.black.opacity(0.35)))
            }
            HStack {
                Spacer()
                if !showPresets {
                    Button { engine.flipCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isRecording)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func controls(engine: CameraEngine) -> some View {
        VStack(spacing: 0) {
            EVWheel(
                value: Binding(get: { engine.evBias }, set: { engine.setEV($0) }),
                isActive: $evActive
            )
            .frame(height: 46)
            .padding(.top, 8)
            shutterRow(engine: engine)
                .frame(height: 90)
                .padding(.top, 6)
            modeRow(engine: engine)
                .frame(height: 40)
            Spacer(minLength: 0)
        }
    }

    private func recordingBadge(engine: CameraEngine) -> some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(Self.format(engine.recordingSeconds))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Color.red.opacity(0.25)))
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
                    .fill(Theme.swatch(model.swatches[preset.id], fallback: preset.accentIndex))
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

/// A small on/off switch in the top bar, like Lampa's grain and halation switches: a dot and a label,
/// lit in the accent color when on.
private struct EffectToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? Theme.accent : Color(white: 0.35))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(isOn ? .white : Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.chrome))
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
