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
    /// The pro tools, opened from the PRO row of the options shade.
    @State private var showPro = false
    /// The viewfinder goes dark for a blink when a photo is taken, as a shutter does.
    @State private var shutterBlink = false
    @Namespace private var modeSpace
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
    @State private var focusMarker: FocusPoint?
    @State private var pinchStart: Double?
    /// A swipe on the picture, once its direction is known: along the user's horizontal it moves the exposure.
    private enum SwipeAxis { case exposure, panels }
    @State private var swipeAxis: SwipeAxis?
    @State private var evSwipeStart: Double?
    /// Where the zoom stood when a finger began to slide along the lens chips.
    @State private var scrubStart: Double?

    private struct FocusPoint: Equatable {
        var location: CGPoint
        var id = UUID()
    }

    private let topBarHeight: CGFloat = 50
    /// Shutter row and mode row. The exposure ruler left this block for the top of the picture.
    private let controlsHeight: CGFloat = 146
    /// The exposure ruler's thickness, and its gap to the picture's edge.
    private let rulerThickness: CGFloat = 56
    private let rulerInset: CGFloat = 8
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

                exposureRuler(engine: engine, in: layout.preview, floor: geo.size.height - controlsHeight - zoomLineHeight - (engine.mode == .video ? 48 : 6))

                if engine.mode == .video, !engine.isSwitchingMode, !showPresets {
                    ExposureHUD(
                        state: engine.cineState,
                        autoMotion: model.settings.autoMotion,
                        locked: engine.isAELocked,
                        fps: model.settings.videoFPS
                    ) {
                        model.updateSettings { $0.autoMotion.toggle() }
                    }
                    .frame(width: geo.size.width, height: 34)
                    .offset(y: geo.size.height - controlsHeight - zoomLineHeight - 40)
                    .transition(.opacity)
                }

                if let notice = engine.notice {
                    Text(notice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(width: geo.size.width - 48)
                        .offset(y: geo.size.height - controlsHeight - zoomLineHeight - 92)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                        .allowsHitTesting(false)
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
                        openPro: {
                            withAnimation(Self.panelSpring) { showOptions = false; showPro = true }
                        },
                        frameRates: engine.frameRates
                    )
                    .frame(width: geo.size.width)
                    .offset(y: topBarHeight + 6)
                    // The shade comes into focus out of a blur, grown from the top bar.
                    .transition(.blurReveal)
                }

                if showPro {
                    ProPanel(
                        mode: engine.mode,
                        settings: model.settings,
                        update: { change in model.updateSettings(change) },
                        back: { withAnimation(Self.panelSpring) { showPro = false; showOptions = true } }
                    )
                    .frame(width: geo.size.width)
                    .offset(y: topBarHeight + 6)
                    .transition(.blurReveal)
                }

            }
            .animation(.easeInOut(duration: 0.22), value: engine.mode)
            .animation(.smooth(duration: 0.25), value: engine.notice)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.iconRotation, model.orientation.current.iconRotation)
        .onChange(of: model.orientation.current) { _, held in engine.deviceOrientation = held }
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
                model.orientation.stop()
                model.location.stop()
                model.level.stop()
            }
        }
        .onChange(of: model.settings.isLevelEnabled) { _, enabled in
            enabled ? model.level.start() : model.level.stop()
        }
        .onChange(of: engine.mode) { _, _ in showOptions = false; showPro = false }
        .onChange(of: engine.isCapturing) { _, capturing in
            guard capturing else { return }
            shutterBlink = true
            withAnimation(.easeOut(duration: 0.28).delay(0.06)) { shutterBlink = false }
        }
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
        model.orientation.start()
        model.engine.deviceOrientation = model.orientation.current
        await model.engine.start()
    }

    // MARK: Top bar

    private func topBar(engine: CameraEngine) -> some View {
        HStack(spacing: 8) {
            Button { showSettings = true } label: {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(white: 0.7))
                    .followsDevice()
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.chrome))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            if engine.isRecording {
                recordingBadge(engine: engine)
            } else {
                LevelToggle(title: "GRAIN", level: model.settings.grainLevel) {
                    model.updateSettings { $0.grainLevel = $0.grainLevel.next }
                }
                LevelToggle(title: "HALATION", level: model.settings.halationLevel) {
                    model.updateSettings { $0.halationLevel = $0.halationLevel.next }
                }
            }
            Spacer(minLength: 0)

            Button {
                Haptics.impact(.light)
                withAnimation(Self.panelSpring) {
                    showOptions = !(showOptions || showPro)
                    showPro = false
                    showPresets = false
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .followsDevice()
                    .foregroundStyle(showOptions || showPro ? Theme.accent : .white)
                    .frame(width: 56, height: 36)
                    .background(Capsule().fill(Theme.chrome))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .animation(Self.panelSpring, value: engine.isRecording)
    }

    // MARK: Exposure ruler

    /// The ruler lies along the top of the picture as the user sees it: across the top held upright, along the
    /// right edge of the portrait layout held top-left, along the left edge held top-right. It turns with the phone,
    /// and glides to its new place when the phone is turned.
    private func exposureRuler(engine: CameraEngine, in preview: CGRect, floor: CGFloat) -> some View {
        let held = model.orientation.current
        let turns = held.quarterTurns
        // Along a side edge the ruler stops above the zoom chips, the flip button and the video readout, which sit
        // at the foot of the picture; across the top there is nothing in its way.
        let along = turns == 0 ? preview.width - 24 : max(120, min(preview.maxY, floor) - preview.minY - 16)
        let middle = turns == 0 ? preview.midX : preview.minY + 8 + along / 2
        let centre: CGPoint = switch turns {
        case 1: CGPoint(x: preview.maxX - rulerInset - rulerThickness / 2, y: middle)
        case -1: CGPoint(x: preview.minX + rulerInset + rulerThickness / 2, y: middle)
        default: CGPoint(x: middle, y: preview.minY + rulerInset + rulerThickness / 2)
        }
        return ExposureRuler(
            value: Binding(get: { engine.evBias }, set: { engine.setEV($0) }),
            orientation: held,
            highlighted: evSwipeStart != nil
        )
        .frame(width: along, height: rulerThickness)
        .rotationEffect(.degrees(held.iconRotation))
        .offset(x: centre.x - along / 2, y: centre.y - rulerThickness / 2)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: held)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: preview)
        .opacity(engine.isSwitchingMode || showOptions || showPro ? 0 : 1)
        .allowsHitTesting(!showOptions && !showPro && !showPresets)
        .animation(.easeOut(duration: 0.18), value: showOptions || showPro)
    }

    /// Room the ruler takes at the picture's corners, so the scopes and the legend keep clear of it.
    private var rulerClearance: EdgeInsets {
        let band = rulerThickness + rulerInset + 4
        let turns = model.orientation.current.quarterTurns
        return EdgeInsets(top: 10 + (turns == 0 ? band : 0), leading: 10 + (turns == -1 ? band : 0), bottom: 10, trailing: 10 + (turns == 1 ? band : 0))
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
            if model.settings.waveform || model.settings.histogram {
                ScopesPanel(engine: engine, showsHistogram: model.settings.histogram, showsWaveform: model.settings.waveform)
                    .padding(rulerClearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            }
            if model.settings.falseColor {
                FalseColorLegend()
                    .padding(rulerClearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
            }
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
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .contentTransition(.numericText(countsDown: true))
                    .followsDevice()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .allowsHitTesting(false)
            }
            // The shutter's blink: instant dark, quick return.
            Color.black
                .opacity(shutterBlink ? 0.75 : 0)
                .allowsHitTesting(false)
            if engine.showsSwitchBlur {
                Rectangle().fill(.ultraThinMaterial).transition(.opacity)
            }
            if let toast = presetToast {
                VStack(spacing: 2) {
                    Text(PresetCardStyle.subtitle(of: model.selectedPreset).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(toast)
                        .font(.system(size: 30, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.5), radius: 10)
                .followsDevice()
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(false)
                .id(toast)
            }
        }
        .animation(Self.panelSpring, value: presetToast)
        .animation(Self.panelSpring, value: model.settings.histogram)
        .animation(Self.panelSpring, value: model.settings.waveform)
        .animation(.easeOut(duration: 0.2), value: model.settings.falseColor)
        .animation(.snappy(duration: 0.3), value: engine.countdown)
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
                if showOptions || showPresets || showPro {
                    withAnimation(Self.panelSpring) { showOptions = false; showPresets = false; showPro = false }
                    return
                }
                Haptics.impact(.light)
                focusMarker = FocusPoint(location: value.location)
                engine.focus(atNormalized: CGPoint(x: value.location.x / size.width, y: value.location.y / size.height))
            }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? engine.absoluteZoom
                    pinchStart = start
                    engine.setContinuousZoom(start * value.magnification)
                }
                .onEnded { _ in pinchStart = nil }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onChanged { value in exposureSwipe(value, engine: engine) }
                .onEnded { value in
                    let axis = swipeAxis
                    swipeAxis = nil
                    evSwipeStart = nil
                    if axis == .panels { swipe(value) }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    // Holding the viewfinder locks exposure and focus, as on the stock camera.
                    engine.toggleLock()
                    Haptics.impact(.medium)
                }
        )
    }

    /// A swipe along the user's horizontal anywhere on the picture moves the exposure, as the ruler does, so there is
    /// no reaching for it. Its direction is settled by the first stretch of the swipe and kept to the end. Not while a
    /// pinch zooms or a panel is open.
    private func exposureSwipe(_ value: DragGesture.Value, engine: CameraEngine) {
        guard pinchStart == nil, !showOptions, !showPro, !showPresets else { return }
        let held = model.orientation.current
        let dx = Double(value.translation.width), dy = Double(value.translation.height)
        let right = held.rightwardTravel(dx: dx, dy: dy)
        if swipeAxis == nil {
            swipeAxis = abs(right) > abs(held.upwardTravel(dx: dx, dy: dy)) * 1.2 ? .exposure : .panels
        }
        guard swipeAxis == .exposure else { return }
        let start = evSwipeStart ?? engine.evBias
        if evSwipeStart == nil { evSwipeStart = start }
        engine.setEV(EVScale.dragged(from: start, travel: right))
    }

    /// Swipes on the viewfinder along the user's vertical: up opens the filters, down pulls the options shade from the
    /// top and a second swipe down goes on into PRO. Up undoes down one step at a time. Only clearly vertical swipes
    /// count; photo and video switch with their buttons.
    private func swipe(_ value: DragGesture.Value) {
        let held = model.orientation.current
        let dx = Double(value.translation.width), dy = Double(value.translation.height)
        let up = held.upwardTravel(dx: dx, dy: dy), right = held.rightwardTravel(dx: dx, dy: dy)
        guard abs(up) > abs(right) * 1.4, abs(up) > 60 else { return }
        Haptics.impact(.soft)
        if up > 0 {
            if showPro {
                withAnimation(Self.panelSpring) { showPro = false; showOptions = true }
            } else if showOptions {
                withAnimation(Self.panelSpring) { showOptions = false }
            } else if !showPresets {
                withAnimation(Self.panelSpring) { showPresets = true }
            }
        } else if showPresets {
            withAnimation(Self.panelSpring) { showPresets = false }
        } else if showOptions {
            withAnimation(Self.panelSpring) { showOptions = false; showPro = true }
        } else if !showPro {
            withAnimation(Self.panelSpring) { showOptions = true }
        }
    }

    /// Zoom chips centered, flip button on the right, as in Lampa. The exposure readout replaces the chips
    /// while the wheel turns.
    private func zoomLine(engine: CameraEngine) -> some View {
        ZStack {
            if engine.lens != .front, !engine.zoomStops.isEmpty, !showPresets {
                ZoomChips(stops: engine.zoomStops, reading: engine.zoomReading, mode: engine.mode) { stop in
                    engine.selectZoom(stop)
                }
                .padding(.horizontal, 4)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                // Sliding along the chips zooms smoothly: right zooms in, left out, a doubling for about 150 points.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            let start = scrubStart ?? engine.absoluteZoom
                            scrubStart = start
                            engine.setContinuousZoom(start * pow(2, Double(value.translation.width) / 150))
                        }
                        .onEnded { _ in scrubStart = nil }
                )
            }
            HStack {
                Spacer()
                if !showPresets {
                    Button { engine.flipCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .followsDevice()
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
            shutterRow(engine: engine)
                .frame(height: 90)
                .padding(.top, 8)
            modeRow(engine: engine)
                .frame(height: 40)
            Spacer(minLength: 0)
        }
    }

    private func recordingBadge(engine: CameraEngine) -> some View {
        HStack(spacing: 6) {
            PulsingDot()
            Text(Self.format(engine.recordingSeconds))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Color.red.opacity(0.25)))
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
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
                            .id(latest.id)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.chrome)
                    }
                    if model.processingCount > 0 { ProgressView().tint(.white) }
                }
                .followsDevice()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: model.captures.first?.id)
            }
            .buttonStyle(PressableStyle())
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
        return Button { withAnimation(Self.panelSpring) { showPresets.toggle(); showOptions = false; showPro = false } } label: {
            ZStack(alignment: .bottomLeading) {
                PresetSwatch(preset: preset, corner: 14)
                    .followsDevice()
                Text(preset.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.light ? Color.black : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
            .frame(width: 58, height: 58)
            .scaleEffect(showPresets ? 1.06 : 1)
            .frame(width: 64, height: 64)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Presets, \(preset.name)")
    }

    private func modeRow(engine: CameraEngine) -> some View {
        ZStack {
            HStack(spacing: 4) {
                modeButton("PHOTO", mode: .photo, engine: engine)
                modeButton("VIDEO", mode: .video, engine: engine)
            }
            .padding(3)
            .background(Capsule().fill(Theme.chromeDark))
            .animation(Self.panelSpring, value: engine.mode)
            .haptic(.selection, trigger: engine.mode)
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
                    .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle())
                .haptic(.impact(weight: .light), trigger: engine.isAELocked)
            }
            .padding(.horizontal, 16)
        }
    }

    private func modeButton(_ title: String, mode: CaptureMode, engine: CameraEngine) -> some View {
        Button { engine.selectMode(mode) } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(engine.mode == mode ? Color.black : Theme.secondaryText)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background {
                    // One pill that slides under the mode in use.
                    if engine.mode == mode {
                        Capsule().fill(Theme.accent).matchedGeometryEffect(id: "mode", in: modeSpace)
                    }
                }
                .contentShape(Capsule())
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

/// The red dot of a running recording, breathing.
private struct PulsingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Shutter, shutter angle and ISO over the video picture, as the camera runs them. With AutoMotion on, a
/// light says how they stand against the 180° rule: green on 180° with the picture exposed right, amber
/// while it ramps or when the shutter had to bend (with the ND filter that would fix it, or LOW LIGHT),
/// red when the light is out of reach and the iPhone's own exposure runs. A tap switches AutoMotion.
struct ExposureHUD: View {
    let state: CaptureSessionController.CineState?
    let autoMotion: Bool
    let locked: Bool
    let fps: Int
    let toggle: () -> Void

    private static let green = Color(red: 0.25, green: 0.9, blue: 0.4)
    private static let amber = Color(red: 1, green: 0.78, blue: 0.2)
    private static let red = Color(red: 1, green: 0.27, blue: 0.23)

    private var color: Color {
        guard autoMotion, !locked else { return Color(white: 0.6) }
        switch state?.status {
        case .cinematic: return Self.green
        case .settling, .bent, .noMeter, .none: return Self.amber
        case .handedOver: return Self.red
        }
    }

    private var label: String {
        if locked { return "AE LOCK" }
        guard autoMotion else { return "AUTO" }
        switch state?.status {
        case .cinematic, .settling, .none: return "180°"
        case .bent(let stops) where stops > 0: return String(format: "ND %.1f", max(stops, 0.1))
        case .bent: return "LOW LIGHT"
        case .handedOver(let tooBright): return tooBright ? "ND 1+" : "LOW LIGHT"
        case .noMeter: return "NO METER"
        }
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .shadow(color: autoMotion ? color.opacity(0.9) : .clear, radius: 4)
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 66, alignment: .leading)
                }
                divider
                value(state?.shutter ?? "—", caption: nil, width: 46)
                divider
                value(state.map { "\($0.angle)°" } ?? "—", caption: nil, width: 32)
                divider
                value(state.map { "\($0.iso)" } ?? "—", caption: "ISO", width: 36)
                divider
                value("\(fps)", caption: "FPS", width: 22)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(autoMotion ? color.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1))
            // Only the light fades; the numbers change in place, several times a second.
            .animation(.easeOut(duration: 0.25), value: color)
        }
        .buttonStyle(PressableStyle())
        .haptic(.selection, trigger: autoMotion)
        .accessibilityLabel("Exposure \(state?.shutter ?? ""), ISO \(state?.iso ?? 0). AutoMotion \(autoMotion ? "on" : "off")")
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 12)
    }

    /// A number in a fixed width, so the bar keeps its size as the numbers change.
    private func value(_ text: String, caption: String?, width: CGFloat) -> some View {
        HStack(spacing: 3) {
            if let caption {
                Text(caption)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: width, alignment: .leading)
                .transaction { $0.animation = nil }
        }
    }
}

/// The GRAIN and HALATION switches: each tap steps Off, Low, Med, High. Three bars show the level, so
/// both fit in the top bar on every phone.
struct LevelToggle: View {
    let title: String
    let level: EffectLevel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1 ... 3, id: \.self) { bar in
                        Capsule()
                            .fill(bar <= Self.bars(level) ? Theme.accent : Color(white: 0.35))
                            .frame(width: 3, height: CGFloat(4 + bar * 3))
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(level == .off ? Theme.secondaryText : .white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.chrome))
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: level)
        }
        .buttonStyle(PressableStyle())
        .haptic(.selection, trigger: level)
        .accessibilityLabel("\(title.capitalized), \(level.label.lowercased())")
    }

    private static func bars(_ level: GrainLevel) -> Int {
        switch level {
        case .off: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
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
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
            .animation(.easeOut(duration: 0.1), value: isCapturing)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .haptic(.impact(weight: .medium), trigger: isRecording)
    }
}

/// Comes into focus out of a blur, slightly grown from the top, as the system's own panels appear.
private struct BlurReveal: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: hidden ? 14 : 0)
            .scaleEffect(hidden ? 0.92 : 1, anchor: .top)
            .opacity(hidden ? 0 : 1)
    }
}

extension AnyTransition {
    static var blurReveal: AnyTransition {
        .modifier(active: BlurReveal(hidden: true), identity: BlurReveal(hidden: false))
    }
}
