import AVFoundation
import CameraCore
import Observation
import UIKit

/// Drives the camera. Every change to the session goes through `CameraStateMachine`; the effects it
/// returns are what actually touch `CaptureSessionController`.
@MainActor
@Observable
final class CameraEngine {
    enum Access {
        case unknown, granted, denied
    }

    /// The preset resolved for each kind of input. `appleLog` is the preset's Apple Log LUT, or a neutral
    /// Apple Log → Rec.709 conversion followed by its video LUT, so every preset works in Apple Log.
    struct Looks {
        var photo = FilmLook.identity
        var video = FilmLook.identity
        var appleLog: FilmLook?
    }

    struct PhotoResult {
        var raw: Data?
        var processed: Data?
        var aspect: AspectOption
        var mirror: Bool
        var date: Date
        /// Set for portrait photos: the depth the blur is built from.
        var depth: AVDepthData?
    }

    private(set) var machine: CameraStateMachine
    private(set) var access: Access = .unknown
    private(set) var zoomStops: [ZoomStop] = []
    private(set) var activeStop: ZoomStop?
    private(set) var zoomFactor = 1.0
    private(set) var isAELocked = false
    private(set) var evBias = 0.0
    private(set) var countdown: Int?
    private(set) var recordingSeconds = 0.0
    private(set) var isCapturing = false
    private(set) var rawAvailable = false
    private(set) var appleLogActive = false
    /// Shown over the viewfinder while the session rebuilds, until fresh frames arrive (Lampa's "unblur").
    private(set) var showsSwitchBlur = false
    var message: String?

    var phase: CameraPhase { machine.phase }
    var mode: CaptureMode { machine.configuration.mode }
    var lens: LensID { machine.configuration.lens }
    /// True while the session is switching between photo and video.
    var isSwitchingMode: Bool { phase == .reconfiguringMode }
    var isRecording: Bool { [.startingRecording, .videoRecording, .finishingRecording, .reconfiguringLensInRecording].contains(phase) }

    @ObservationIgnored let controller = CaptureSessionController()
    @ObservationIgnored var onPhoto: ((PhotoResult) -> Void)?
    @ObservationIgnored var onVideo: ((URL) -> Void)?
    @ObservationIgnored var onModeChanged: ((CaptureMode) -> Void)?

    @ObservationIgnored private var settings: AppSettings
    @ObservationIgnored private var looks = Looks()
    @ObservationIgnored private var appleLogRequested = false
    @ObservationIgnored private var focalLengths = ZoomStop.defaultFocalLengths
    @ObservationIgnored private var digitalZoom = 1.0
    @ObservationIgnored private var recordingTimer: Timer?
    @ObservationIgnored private var recordingStart: Date?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    var displayLayer: AVSampleBufferDisplayLayer { controller.hub.displayLayer }

    init(settings: AppSettings) {
        self.settings = settings
        machine = CameraStateMachine(configuration: CameraConfiguration(
            mode: settings.lastCaptureMode,
            format: settings.videoFormat,
            lens: .wide
        ))
    }

    // MARK: Lifecycle

    func start() async {
        guard await controller.requestVideoAccess() else {
            access = .denied
            return
        }
        access = .granted
        if mode == .video { _ = await controller.requestMicrophoneAccess() }
        await applyConfig()
    }

    func stop() {
        countdownTask?.cancel()
        controller.stop()
    }

    func setLooks(_ looks: Looks) {
        self.looks = looks
        updateHub()
        reapplyIfAppleLogChanged()
    }

    func update(settings new: AppSettings) {
        let old = settings
        settings = new
        if new.videoFormat != old.videoFormat, !isRecording {
            send(.updateVideoConfiguration(new.videoFormat))
        } else if (new.videoStabilization != old.videoStabilization || new.capturesRAW != old.capturesRAW || new.photoResolution != old.photoResolution), !isRecording {
            Task { await applyConfig() }
        } else {
            reapplyIfAppleLogChanged()
        }
        if new.digitalZoomStop != old.digitalZoomStop {
            refreshStops()
            if let active = activeStop, !zoomStops.contains(active), let fallback = zoomStops.first(where: { $0.lens == lens }) {
                selectZoom(fallback)
            }
        }
        updateHub()
    }

    // MARK: User actions

    func selectMode(_ new: CaptureMode) {
        guard new != mode else { return }
        let previousZoom = digitalZoom
        digitalZoom = 1
        if send(.switchMode(new)) {
            // Crop and look follow at once; when photo and video share a format this is the whole switch.
            refreshStops()
            updateHub()
            onModeChanged?(new)
        } else {
            digitalZoom = previousZoom
        }
    }

    func selectZoom(_ stop: ZoomStop) {
        let previousZoom = digitalZoom
        digitalZoom = stop.digitalZoom
        if stop.lens != lens {
            guard send(.switchDevice(stop.lens)) else {
                digitalZoom = previousZoom
                return
            }
        }
        // The back cameras are one virtual device, so changing lens is only a zoom change. Apply it at once
        // instead of waiting for the session to be reconfigured.
        controller.setZoom(lens: stop.lens, digital: stop.digitalZoom)
        zoomFactor = stop.digitalZoom
        activeStop = stop
    }

    func setContinuousZoom(_ factor: Double) {
        digitalZoom = max(1, factor)
        zoomFactor = digitalZoom
        activeStop = nil
        controller.setZoom(lens: lens, digital: digitalZoom)
    }

    func flipCamera() {
        let target: LensID = lens == .front ? .wide : .front
        let previousZoom = digitalZoom
        digitalZoom = 1
        if !send(.switchDevice(target)) { digitalZoom = previousZoom }
    }

    func setEV(_ value: Double) {
        evBias = EVScale.snapped(value)
        controller.setExposureBias(evBias)
    }

    func toggleLock() {
        isAELocked.toggle()
        controller.setLocked(isAELocked)
    }

    /// `point` is normalized (0...1, origin top-left) inside the visible, cropped viewfinder.
    func focus(atNormalized point: CGPoint) {
        guard let geometry = controller.hub.currentGeometry else { return }
        var x = point.x
        if mirrorsOutput { x = 1 - x }
        let frameX = (CGFloat(geometry.crop.x) + x * CGFloat(geometry.crop.width)) / geometry.source.width
        let frameY = (CGFloat(geometry.crop.y) + point.y * CGFloat(geometry.crop.height)) / geometry.source.height
        // The portrait frame is the landscape sensor rotated a quarter turn, so the axes swap.
        controller.focus(at: CGPoint(x: frameY, y: 1 - frameX), lockAfter: isAELocked)
    }

    func shutterTapped() {
        switch mode {
        case .photo:
            if countdown != nil {
                countdownTask?.cancel()
                countdown = nil
                return
            }
            guard phase == .idle, !isCapturing else { return }
            let seconds = settings.timer.seconds
            if seconds > 0 {
                startCountdown(seconds)
            } else {
                performCapture()
            }
        case .video:
            if phase == .videoRecording {
                send(.stopRecordingTap)
            } else if phase == .idle {
                send(.startRecordingTap)
            }
        }
    }

    // MARK: State machine plumbing

    @discardableResult
    private func send(_ event: CameraEvent) -> Bool {
        do {
            let effects = try machine.handle(event)
            effects.forEach(run)
            return true
        } catch {
            return false
        }
    }

    private func run(_ effect: CameraEffect) {
        switch effect {
        case .reconfigureSessionToMode, .reconfigureSessionToVideoFormat, .reconfigureSessionToDevice:
            reconfigure()
        case .startVideoRecording:
            beginRecording()
        case .stopVideoRecording:
            endRecording()
        }
    }

    private func reconfigure() {
        send(.reconfigurationSessionDidStart)
        Task {
            if mode == .video { _ = await controller.requestMicrophoneAccess() }
            // Only blur when the switch is slow enough to notice.
            let blur = Task {
                try? await Task.sleep(for: .milliseconds(90))
                if !Task.isCancelled { showsSwitchBlur = true }
            }
            let info = await applyConfig()
            if info.didReconfigure { await waitForFreshFrames() }
            blur.cancel()
            showsSwitchBlur = false
            send(.reconfigurationSessionDidFinish)
        }
    }

    /// After a rebuild the first frames can still be dark or mid-exposure, so wait for a few.
    private func waitForFreshFrames() async {
        let start = controller.hub.frameCount
        for _ in 0 ..< 60 {
            if controller.hub.frameCount >= start + 3 { return }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Apple Log depends only on the setting, mode and camera, never on the preset, so switching presets
    /// never rebuilds the session.
    private var wantsAppleLog: Bool {
        settings.appleLogVideo && mode == .video && lens != .front
    }

    private func reapplyIfAppleLogChanged() {
        guard mode == .video, !isRecording, wantsAppleLog != appleLogRequested else { return }
        Task { await applyConfig() }
    }

    @discardableResult
    private func applyConfig() async -> CaptureSessionController.DeviceInfo {
        appleLogRequested = wantsAppleLog
        let config = CaptureSessionController.Config(
            lens: machine.configuration.lens,
            mode: machine.configuration.mode,
            format: machine.configuration.format,
            stabilization: settings.videoStabilization,
            appleLog: appleLogRequested,
            digitalZoom: digitalZoom,
            exposureBias: evBias,
            wantsRAW: settings.capturesRAW,
            photoResolution: settings.photoResolution
        )
        let info = await controller.apply(config)
        focalLengths = info.focalLengths
        rawAvailable = info.rawAvailable
        appleLogActive = info.appleLogActive
        refreshStops()
        updateHub()
        return info
    }

    private func refreshStops() {
        if lens == .front {
            zoomStops = []
            activeStop = nil
            return
        }
        zoomStops = mode == .photo
            ? ZoomStop.photoStops(focalLengths: focalLengths, digital: settings.digitalZoomStop)
            : ZoomStop.videoStops(focalLengths: focalLengths)
        activeStop = zoomStops.first { $0.lens == lens && abs($0.digitalZoom - digitalZoom) < 0.01 }
            ?? zoomStops.first { $0.lens == lens }
        zoomFactor = digitalZoom
    }

    private var mirrorsOutput: Bool { lens == .front && settings.mirrorFrontCamera }

    /// 10-bit Apple Log frames pick the Apple Log look by themselves. If the camera can only deliver
    /// Apple Log as BGRA, every video frame is log while it is active.
    private func updateHub() {
        let look: FilmLook
        if mode == .photo {
            look = looks.photo
        } else if appleLogActive, let appleLog = looks.appleLog {
            look = appleLog
        } else {
            look = looks.video
        }
        controller.hub.configure(
            look: look,
            logLook: mode == .video ? looks.appleLog : nil,
            aspect: mode == .photo ? settings.aspect : .ratio16x9,
            mirror: mirrorsOutput
        )
    }

    // MARK: Photo

    private func startCountdown(_ seconds: Int) {
        countdownTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                guard let self else { return }
                self.countdown = remaining
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    self.countdown = nil
                    return
                }
                remaining -= 1
            }
            self?.countdown = nil
            self?.performCapture()
        }
    }

    private func performCapture() {
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let mirror = mirrorsOutput
        let aspect = settings.aspect
        let portrait = settings.portrait
        controller.capturePhoto(flash: settings.flash, wantsRAW: settings.capturesRAW, portrait: portrait) { [weak self] outcome in
            Task { @MainActor in
                guard let self else { return }
                self.isCapturing = false
                if outcome.raw == nil, outcome.processed == nil {
                    self.message = outcome.error?.localizedDescription ?? "The photo could not be captured."
                    return
                }
                self.onPhoto?(PhotoResult(
                    raw: outcome.raw,
                    processed: outcome.processed,
                    aspect: aspect,
                    mirror: mirror,
                    date: Date(),
                    depth: outcome.depth
                ))
            }
        }
    }

    // MARK: Video

    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).mov")
        controller.startRecording(url: url, fps: machine.configuration.format.fps) { [weak self] in
            Task { @MainActor in self?.recordingDidStart() }
        } onFail: { [weak self] error in
            Task { @MainActor in
                self?.message = error.localizedDescription
                self?.send(.videoRecordingDidFinish)
            }
        }
    }

    private func recordingDidStart() {
        send(.videoRecordingDidStart)
        recordingSeconds = 0
        recordingStart = Date()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStart else { return }
                self.recordingSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    private func endRecording() {
        controller.stopRecording { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                self.recordingStart = nil
                self.send(.videoRecordingDidFinish)
                if let url {
                    self.onVideo?(url)
                } else if let error {
                    self.message = error.localizedDescription
                }
            }
        }
    }
}
