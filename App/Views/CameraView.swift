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
    @State private var showDynamicRange = false
    @State private var apertureOpen = false
    @State private var showLenses = false
    /// The preset name shown over the picture for a moment after a switch.
    @State private var presetToast: String?
    /// The version, shown for a few seconds at launch so an installed build can be told apart.
    @State private var showVersion = true
    @State private var editingPresetID: String?
    /// The new-preset sheet: `.some(nil)` starts from scratch, `.some(preset)` from that preset.
    @State private var newPresetBase: Preset??
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
    /// One spring for every panel that slides in, so the screen moves as one.
    static let panelSpring = Animation.spring(response: 0.36, dampingFraction: 0.86)

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

                if model.settings.portrait, engine.mode == .photo {
                    HStack(spacing: 8) {
                        ApertureControl(
                            fNumber: model.settings.portraitFNumber,
                            expanded: $apertureOpen
                        ) { stop in
                            model.updateSettings { $0.portraitFNumber = stop }
                            apertureOpen = false
                        }
                        Button {
                            withAnimation(Self.panelSpring) { showLenses.toggle(); showPresets = false; showOptions = false }
                        } label: {
                            HStack(spacing: 8) {
                                LensPreview(lens: model.settings.lensStyle)
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                                Text(model.settings.lensStyle.label)
                                    .font(.system(size: 14, weight: .semibold))
                                    .tracking(0.6)
                            }
                            .foregroundStyle(showLenses ? Theme.accent : .white)
                            .padding(.leading, 7)
                            .padding(.trailing, 14)
                            .frame(height: 38)
                            .background(Capsule().fill(Color.black.opacity(0.45)).background(.ultraThinMaterial, in: Capsule()))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .frame(width: geo.size.width, height: 44)
                    .offset(y: geo.size.height - controlsHeight - zoomLineHeight - 50)
                    .transition(.opacity)
                }

                if showLenses, model.settings.portrait, engine.mode == .photo {
                    LensPicker(selected: model.settings.lensStyle) { lens in
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(Self.panelSpring) { model.updateSettings { $0.lensStyle = lens } }
                    }
                    .background(Color.black.opacity(0.55))
                    .background(.ultraThinMaterial)
                    .frame(width: geo.size.width)
                    .offset(y: geo.size.height - controlsHeight - 196)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                zoomLine(engine: engine)
                    .frame(width: geo.size.width, height: zoomLineHeight)
                    .offset(y: geo.size.height - controlsHeight - zoomLineHeight)

                if showPresets {
                    PresetPicker(onEdit: { editingPresetID = $0 }, onCreate: { newPresetBase = .some($0) })
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55))
                        .background(.ultraThinMaterial)
                        .frame(width: geo.size.width)
                        .offset(y: geo.size.height - controlsHeight - 112)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                controls(engine: engine)
                    .frame(width: geo.size.width, height: controlsHeight)
                    .offset(y: geo.size.height - controlsHeight)

                topBar(engine: engine)
                    .frame(width: geo.size.width, height: topBarHeight)

                if showVersion {
                    Text("RCamera \(SettingsView.version)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent))
                        .frame(width: geo.size.width)
                        .offset(y: topBarHeight + 14)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .task {
                            try? await Task.sleep(for: .seconds(4))
                            withAnimation(.easeOut(duration: 0.4)) { showVersion = false }
                        }
                }

                if showOptions {
                    OptionsPanel(
                        mode: engine.mode,
                        settings: model.settings,
                        update: { change in model.updateSettings(change) },
                        openDynamicRange: {
                            withAnimation(Self.panelSpring) { showOptions = false; showDynamicRange = true }
                        }
                    )
                    .frame(width: geo.size.width)
                    .offset(y: topBarHeight + 6)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                    ))
                }

                if showDynamicRange {
                    DynamicRangeStrip(selected: model.settings.dynamicRange) { choice in
                        model.updateSettings { $0.dynamicRange = choice }
                        withAnimation(Self.panelSpring) { showDynamicRange = false }
                    }
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
        .sheet(isPresented: Binding(get: { editingPresetID != nil }, set: { if !$0 { editingPresetID = nil } })) {
            if let id = editingPresetID {
                NavigationStack {
                    PresetEditorView(presetID: id, onCreated: { editingPresetID = $0 })
                        .id(id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { editingPresetID = nil }
                            }
                        }
                }
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
            }
        }
        .sheet(isPresented: Binding(get: { newPresetBase != nil }, set: { if !$0 { newPresetBase = nil } })) {
            NewPresetSheet(base: newPresetBase ?? nil) { id in
                newPresetBase = nil
                // Straight into the editor, so the new preset can be tuned at once.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    editingPresetID = id
                }
            }
        }
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
                model.syncVolumeShutter(active: false)
                model.location.stop()
                model.level.stop()
            }
        }
        .onChange(of: model.settings.isLevelEnabled) { _, enabled in
            enabled ? model.level.start() : model.level.stop()
        }
        .onChange(of: engine.mode) { _, _ in showOptions = false; showLenses = false }
        .onChange(of: model.settings.portrait) { _, on in if !on { withAnimation(Self.panelSpring) { showLenses = false } } }
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
        model.syncVolumeShutter(active: true)
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

            Button { withAnimation(Self.panelSpring) { showOptions.toggle(); showPresets = false; showLenses = false; showDynamicRange = false } } label: {
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
                .background {
                    if #available(iOS 18.0, *) {
                        CameraControlHost { engine.shutterTapped() }
                    }
                }
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
            if let toast = presetToast {
                VStack(spacing: 2) {
                    Text(PresetCardStyle.of(model.selectedPreset).subtitle.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(toast)
                        .font(.system(size: 30, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.5), radius: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(false)
                .id(toast)
            }
        }
        .animation(Self.panelSpring, value: presetToast)
        .onChange(of: model.selectedPreset.id) { _, _ in
            presetToast = model.selectedPreset.name
        }
        .task(id: presetToast) {
            guard presetToast != nil else { return }
            try? await Task.sleep(for: .seconds(1.1))
            if !Task.isCancelled { presetToast = nil }
        }
        .animation(.easeInOut(duration: 0.15), value: engine.showsSwitchBlur)
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                if showOptions || showPresets || showLenses || showDynamicRange {
                    withAnimation(Self.panelSpring) { showOptions = false; showPresets = false; showLenses = false; showDynamicRange = false }
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in swipe(value, engine: engine) }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    // Holding the viewfinder locks exposure and focus, as on the stock camera.
                    engine.toggleLock()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
        )
    }

    /// Lampa-style swipes on the viewfinder: up opens the filters, down closes them or opens settings,
    /// left and right switch between photo and video. Only clearly directional drags count.
    private func swipe(_ value: DragGesture.Value, engine: CameraEngine) {
        let dx = value.translation.width, dy = value.translation.height
        if abs(dy) > abs(dx) * 1.4, abs(dy) > 60 {
            if dy < 0 {
                guard !showPresets else { return }
                withAnimation(Self.panelSpring) { showPresets = true; showOptions = false; showLenses = false }
            } else if showPresets || showOptions || showLenses || showDynamicRange {
                withAnimation(Self.panelSpring) { showPresets = false; showOptions = false; showLenses = false; showDynamicRange = false }
            } else {
                showSettings = true
            }
        } else if abs(dx) > abs(dy) * 1.4, abs(dx) > 70, !engine.isRecording, !engine.isSwitchingMode {
            engine.selectMode(engine.mode == .photo ? .video : .photo)
        }
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
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1))
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
        let style = PresetCardStyle.of(preset)
        return Button { withAnimation(Self.panelSpring) { showPresets.toggle(); showOptions = false; showLenses = false } } label: {
            ZStack(alignment: .bottomLeading) {
                PresetSwatch(preset: preset, corner: 14)
                Text(preset.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.light ? Color.black : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
            .frame(width: 58, height: 58)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(showPresets ? Theme.accent : Color.white.opacity(0.15), lineWidth: showPresets ? 2 : 1)
            )
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Presets, \(preset.name)")
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
struct EffectToggle: View {
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
