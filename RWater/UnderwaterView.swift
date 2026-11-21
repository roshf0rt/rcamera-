import CameraCore
import SwiftUI
import UIKit

/// The one screen of RWater. In the housing the touch screen does not work, so everything that matters is
/// on the housing's keys and big enough to read through the port; the touch controls are for the surface.
struct UnderwaterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSettings = false
    @State private var showGallery = false
    @State private var focusPoint: CGPoint?
    @State private var focusID = UUID()
    @State private var shutterBlink = false

    var body: some View {
        let engine = model.engine
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                viewfinder(engine: engine)
                    .frame(width: geo.size.width, height: previewHeight(geo.size, mode: engine.mode))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                VStack(spacing: 0) {
                    topBar(engine: engine)
                    Spacer(minLength: 0)
                    if let notice = engine.notice {
                        Text(notice)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                            .padding(.bottom, 10)
                            .transition(.opacity)
                    }
                    if engine.mode == .video {
                        ExposureHUD(
                            state: engine.cineState,
                            autoMotion: model.settings.autoMotion,
                            locked: engine.isAELocked,
                            fps: model.settings.videoFPS
                        ) {
                            model.updateSettings { $0.autoMotion.toggle() }
                        }
                        .frame(height: 34)
                        .padding(.bottom, 6)
                    }
                    bottomBar(engine: engine)
                }
            }
            .animation(.smooth(duration: 0.25), value: engine.notice)
            .animation(.easeInOut(duration: 0.2), value: engine.mode)
        }
        .background {
            // The housing's buttons arrive as a Bluetooth keyboard.
            HousingKeyHost(active: model.settings.housingKeys && !showSettings && !showGallery) { action, factor in
                model.engine.housingAction(action, factor: factor)
            }
        }
        .overlay { if engine.access == .denied { accessDenied } }
        .sheet(isPresented: $showSettings) { UnderwaterSettingsView() }
        .fullScreenCover(isPresented: $showGallery) { GalleryView() }
        .alert("RWater", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? engine.message ?? "")
        }
        .environment(\.iconRotation, model.orientation.current.iconRotation)
        .onChange(of: model.orientation.current) { _, held in engine.deviceOrientation = held }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await activate() }
            } else if phase == .background {
                engine.stop()
                model.syncVolumeShutter(active: false)
                model.orientation.stop()
                model.location.stop()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: model.housing.isConnected) { _, connected in
            engine.showNotice(connected ? "Housing connected" : "Housing disconnected")
        }
        .onChange(of: engine.isCapturing) { _, capturing in
            guard capturing else { return }
            shutterBlink = true
            withAnimation(.easeOut(duration: 0.28).delay(0.06)) { shutterBlink = false }
        }
        .onChange(of: engine.mode) { _, _ in reapplyFocus() }
        .onChange(of: engine.lens) { _, _ in reapplyFocus() }
    }

    private func previewHeight(_ size: CGSize, mode: CaptureMode) -> CGFloat {
        let ratio: CGFloat = mode == .video ? 16 / 9 : 4 / 3
        return min(size.width * ratio, size.height)
    }

    private func activate() async {
        // In the housing nobody touches the screen, and a locked phone cannot be woken underwater.
        UIApplication.shared.isIdleTimerDisabled = true
        if model.settings.savesLocation { model.location.start() }
        if #unavailable(iOS 17.2) { model.syncVolumeShutter(active: true) }
        model.orientation.start()
        model.engine.deviceOrientation = model.orientation.current
        await model.engine.start()
        reapplyFocus()
    }

    /// Manual focus is a lens position of the current camera; a new camera or mode starts in AF otherwise.
    private func reapplyFocus() {
        if let position = model.engine.manualFocus { model.engine.setManualFocus(position) }
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

    // MARK: Viewfinder

    private func viewfinder(engine: CameraEngine) -> some View {
        GeometryReader { geo in
            ZStack {
                ViewfinderLayerView(layer: engine.displayLayer)
                if #available(iOS 17.2, *) {
                    // The volume keys and Camera Control: the housing's shutter sends one of them.
                    CameraControlHost(volumeUp: true) { engine.shutterTapped() }
                }
                if model.settings.isGridEnabled { GridOverlay().allowsHitTesting(false) }
                if let focusPoint {
                    FocusMarker()
                        .id(focusID)
                        .position(focusPoint)
                        .allowsHitTesting(false)
                }
                Color.black.opacity(shutterBlink ? 0.85 : 0).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    focusPoint = value.location
                    focusID = UUID()
                    if engine.manualFocus != nil { engine.setManualFocus(nil) }
                    engine.focus(atNormalized: CGPoint(x: value.location.x / geo.size.width, y: value.location.y / geo.size.height))
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                    Haptics.impact(.medium)
                    engine.toggleLock()
                }
            )
        }
    }

    // MARK: Top bar

    private func topBar(engine: CameraEngine) -> some View {
        HStack(spacing: 10) {
            roundButton("gearshape.fill") { showSettings = true }
                .disabled(engine.isRecording)

            Image(systemName: model.housing.isConnected ? "keyboard.fill" : "keyboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.housing.isConnected ? Theme.accent : Color(white: 0.45))

            Spacer(minLength: 0)

            if engine.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                    Text(Self.format(engine.recordingSeconds))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.red.opacity(0.35)))
            } else {
                Text(engine.mode == .video ? "VIDEO" : "PHOTO")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            if engine.mode == .video, engine.appleLogActive {
                badge(model.settings.appleLog2 ? "LOG 2" : "LOG")
            }
            if engine.mode == .video, let ettr = engine.cineState?.ettr, let target = engine.cineState?.ettrTarget {
                // The push to the right now; dimmed while the highlight guard holds it back from the setting.
                Text(String(format: "ETTR %+.1f", ettr))
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(ettr < target - 0.05 ? Color.orange : Theme.accent)
            }
            if engine.mode == .photo, model.settings.capturesRAW {
                badge("RAW")
            }
            if engine.manualFocus != nil { badge("MF") }
            if engine.isAELocked { badge("AE-L") }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .frame(height: 50)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy, design: .monospaced))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent))
    }

    // MARK: Bottom bar

    private func bottomBar(engine: CameraEngine) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                pill("−") { engine.setEV(max(engine.evBias - 1.0 / 3, -3)) }
                Text(String(format: "EV %+.1f", engine.evBias))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(engine.evBias == 0 ? .white : Theme.accent)
                    .frame(width: 92)
                    .onTapGesture { engine.setEV(0) }
                pill("+") { engine.setEV(min(engine.evBias + 1.0 / 3, 3)) }
                Spacer(minLength: 0)
                pill("−") { engine.housingAction(.zoomOut) }
                Text(String(format: "%.1f×", engine.absoluteZoom))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 58)
                pill("+") { engine.housingAction(.zoomIn) }
            }

            HStack {
                Button { showGallery = true } label: {
                    Group {
                        if let last = model.captures.first {
                            CaptureThumbnail(record: last)
                        } else {
                            Color(white: 0.15)
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(engine.isRecording)

                Spacer()
                shutterButton(engine: engine)
                Spacer()

                VStack(spacing: 10) {
                    Button {
                        Haptics.impact(.light)
                        engine.housingAction(engine.mode == .video ? .photoMode : .videoMode)
                    } label: {
                        Image(systemName: engine.mode == .video ? "camera.fill" : "video.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(Theme.chrome))
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isRecording)
                }
            }
            .overlay(alignment: .trailing) {
                roundButton("arrow.triangle.2.circlepath") { engine.housingAction(.flipCamera) }
                    .offset(x: 0, y: -74)
                    .disabled(engine.isRecording)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }

    private func shutterButton(engine: CameraEngine) -> some View {
        Button {
            engine.shutterTapped()
        } label: {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 5).frame(width: 84, height: 84)
                if engine.mode == .video {
                    RoundedRectangle(cornerRadius: engine.isRecording ? 8 : 34)
                        .fill(Color.red)
                        .frame(width: engine.isRecording ? 34 : 68, height: engine.isRecording ? 34 : 68)
                } else {
                    Circle().fill(Color.white).frame(width: 68, height: 68)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: engine.isRecording)
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chrome))
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(white: 0.85))
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.chrome))
        }
        .buttonStyle(.plain)
    }

    private var accessDenied: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill").font(.system(size: 40))
            Text("Camera access is off").font(.title3.weight(.semibold))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
