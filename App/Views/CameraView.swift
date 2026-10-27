import CameraCore
import SwiftUI

struct CameraView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var showOptions = false
    @State private var showPresets = false
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var showZoomSlider = false
    @State private var evActive = false
    @State private var focusMarker: FocusPoint?
    @State private var pinchStart: Double?

    private struct FocusPoint: Equatable {
        var location: CGPoint
        var id = UUID()
    }

    private let side: CGFloat = 6

    var body: some View {
        let engine = model.engine
        GeometryReader { geo in
            let width = geo.size.width - side * 2
            let videoRatio = CGFloat(16.0 / 9.0)
            let photoRatio = CGFloat(model.settings.aspect.portraitHeightOverWidth)
            let desired: CGFloat = engine.mode == .video ? width * videoRatio : width * photoRatio
            let reserved: CGFloat = showPresets ? 252 : (engine.mode == .video ? 74 : 232)
            let previewHeight = max(200, min(desired, geo.size.height - 52 - reserved))

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 8) {
                    topBar
                    viewfinder(engine: engine, size: CGSize(width: width, height: previewHeight))
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bottomControls(engine: engine)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
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

    private var topBar: some View {
        HStack {
            Button { showSettings = true } label: {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.chrome))
            }
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.18)) { showOptions.toggle() } } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(showOptions ? Theme.accent : .white)
                    .frame(width: 64, height: 40)
                    .background(Capsule().fill(Theme.chrome))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
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
            if engine.isRecording { recordingBadge(engine: engine) }
            if showOptions { optionsPanel }
            if showPresets { collapseButton }
        }
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
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

    private var collapseButton: some View {
        VStack {
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.2)) { showPresets = false } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .padding(.bottom, 10)
        }
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

    private func bottomControls(engine: CameraEngine) -> some View {
        VStack(spacing: 0) {
            if showPresets {
                PresetPicker()
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                zoomRow(engine: engine)
                EVWheel(
                    value: Binding(get: { engine.evBias }, set: { engine.setEV($0) }),
                    isActive: $evActive,
                    overlaid: engine.mode == .video
                )
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            shutterRow(engine: engine)
            modeRow(engine: engine)
                .padding(.top, 12)
        }
        .padding(.bottom, 4)
    }

    private func zoomRow(engine: CameraEngine) -> some View {
        ZStack {
            if evActive {
                EVBubble(value: engine.evBias)
            } else if showZoomSlider && engine.lens != .front {
                Slider(
                    value: Binding(get: { engine.zoomFactor }, set: { engine.setContinuousZoom($0) }),
                    in: 1 ... 10
                )
                .tint(Theme.accent)
                .padding(.horizontal, 80)
            } else {
                ZoomChips(stops: engine.zoomStops, active: engine.activeStop, mode: engine.mode) { stop in
                    engine.selectZoom(stop)
                }
            }
            HStack {
                if engine.mode == .video && engine.lens != .front {
                    CircleIconButton(systemName: "plus.magnifyingglass") { showZoomSlider.toggle() }
                }
                Spacer()
                CircleIconButton(systemName: "arrow.triangle.2.circlepath") { engine.flipCamera() }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 54)
    }

    private func shutterRow(engine: CameraEngine) -> some View {
        HStack {
            Button { showGallery = true } label: {
                ZStack {
                    if let latest = model.captures.first {
                        CaptureThumbnail(record: latest)
                    } else {
                        RoundedRectangle(cornerRadius: 16).fill(Theme.chrome)
                    }
                    if model.processingCount > 0 { ProgressView().tint(.white) }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
            shutterButton(engine: engine)
            Spacer()
            presetButton
        }
        .padding(.horizontal, 24)
    }

    private func shutterButton(engine: CameraEngine) -> some View {
        Button { engine.shutterTapped() } label: {
            ZStack {
                Circle()
                    .strokeBorder(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 5)
                    .frame(width: 88, height: 88)
                if engine.mode == .video {
                    RoundedRectangle(cornerRadius: engine.isRecording ? 8 : 36)
                        .fill(Color(red: 0.9, green: 0.15, blue: 0.1))
                        .frame(width: engine.isRecording ? 34 : 72, height: engine.isRecording ? 34 : 72)
                        .animation(.easeOut(duration: 0.2), value: engine.isRecording)
                } else {
                    Circle().fill(Theme.cardLight).frame(width: 72, height: 72)
                        .scaleEffect(engine.isCapturing ? 0.9 : 1)
                        .animation(.easeOut(duration: 0.1), value: engine.isCapturing)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(engine.access != .granted)
    }

    private var presetButton: some View {
        let preset = model.selectedPreset
        return Button { withAnimation(.easeOut(duration: 0.2)) { showPresets.toggle(); showOptions = false } } label: {
            ZStack {
                if !showPresets {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.gradient(preset.accentIndex))
                        .frame(width: 62, height: 62)
                        .offset(x: 5, y: 5)
                        .opacity(0.8)
                }
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: showPresets ? 0.1 : 0.14))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color(white: 0.3), lineWidth: 1))
                    .overlay(
                        Text(showPresets ? "PRESET" : preset.name.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(showPresets ? Theme.secondaryText : .white)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .padding(4)
                    )
                    .frame(width: 62, height: 62)
            }
            .frame(width: 70, height: 70)
        }
        .buttonStyle(.plain)
    }

    private func modeRow(engine: CameraEngine) -> some View {
        ZStack {
            HStack(spacing: 40) {
                modeButton("PHOTO", mode: .photo, engine: engine)
                modeButton("VIDEO", mode: .video, engine: engine)
            }
            HStack {
                Spacer()
                Button { engine.toggleLock() } label: {
                    HStack(spacing: 6) {
                        Text("AE/AF").font(.system(size: 14, weight: .semibold))
                        Image(systemName: engine.isAELocked ? "lock.fill" : "lock.open.fill").font(.system(size: 13))
                    }
                    .foregroundStyle(engine.isAELocked ? Theme.accent : Theme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.chrome))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
    }

    private func modeButton(_ title: String, mode: CaptureMode, engine: CameraEngine) -> some View {
        Button { engine.selectMode(mode) } label: {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(engine.mode == mode ? Theme.accent : Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(engine.isRecording)
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
