import AppIntents
import AVFoundation
import AVKit
import GameController
import MediaPlayer
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted by `TakePhotoIntent`; `AppModel` takes a photo when it hears it.
    static let takePhotoRequested = Notification.Name("RCamera.takePhotoRequested")
}

/// Lets the Action button, Shortcuts and Siri take a photo. The app opens first, then the shutter fires.
struct TakePhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Take Photo"
    static var description = IntentDescription("Opens RCamera and takes a photo with the selected preset.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .takePhotoRequested, object: nil)
        return .result()
    }
}

struct RCameraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TakePhotoIntent(),
            phrases: ["Take a photo with \(.applicationName)"],
            shortTitle: "Take Photo",
            systemImageName: "camera"
        )
    }
}

/// Turns the hardware volume buttons into a shutter while the camera is on screen.
///
/// Each press changes the output volume. The change is seen through key-value observing, the shutter
/// fires, and the volume is put back through the slider of a hidden `MPVolumeView`, which also keeps the
/// system volume HUD away from the viewfinder. Not verified on a device yet.
@MainActor
final class VolumeShutter {
    var onPress: (() -> Void)?

    private var observation: NSKeyValueObservation?
    private var resting: Float = 0.5
    private let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.01
        return view
    }()

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        resting = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.volumeChanged() }
        }
        if volumeView.superview == nil {
            let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first
            window?.addSubview(volumeView)
        }
    }

    func stop() {
        observation = nil
        volumeView.removeFromSuperview()
    }

    private func volumeChanged() {
        let now = AVAudioSession.sharedInstance().outputVolume
        // Putting the volume back fires this observer again; the same level means nothing was pressed.
        guard abs(now - resting) > 0.01 else { return }
        onPress?()
        volumeView.subviews.compactMap { $0 as? UISlider }.first?.value = resting
    }
}

/// Camera Control (iPhone 16 and later) and the volume buttons (iOS 17.2 and later): a press takes a photo or
/// starts and stops a recording, the same as the shutter. Volume keys sent by Bluetooth remotes and the shutter
/// button of an underwater housing arrive the same way. The interaction sits on the whole viewfinder.
@available(iOS 17.2, *)
struct CameraControlHost: UIViewRepresentable {
    let onPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let interaction = AVCaptureEventInteraction(
            primary: { event in
                if event.phase == .ended { onPress() }
            },
            secondary: { event in
                if event.phase == .ended { onPress() }
            }
        )
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Reads the buttons of an underwater housing that pairs as a Bluetooth keyboard (`HousingRemote`): an
/// invisible view takes the keyboard while the camera is on screen and turns key presses into actions. A held
/// zoom key keeps zooming until it is let go.
struct HousingKeyHost: UIViewRepresentable {
    /// False while a sheet with text fields is up, so typing there is left alone.
    var active: Bool
    var onAction: (HousingRemote.Action, Double) -> Void

    func makeUIView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onAction = onAction
        return view
    }

    func updateUIView(_ view: KeyCatcherView, context: Context) {
        view.onAction = onAction
        view.isActive = active
    }

    final class KeyCatcherView: UIView {
        var onAction: ((HousingRemote.Action, Double) -> Void)?
        var isActive = true {
            didSet { claimKeyboard() }
        }
        private var repeatTimer: Timer?
        private var heldKey: UIKeyboardHIDUsage?
        private var activeObserver: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.claimKeyboard() }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit {
            if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
            repeatTimer?.invalidate()
        }

        override var canBecomeFirstResponder: Bool { isActive }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            claimKeyboard()
        }

        private func claimKeyboard() {
            guard window != nil else { return }
            if isActive, !isFirstResponder {
                becomeFirstResponder()
            } else if !isActive, isFirstResponder {
                resignFirstResponder()
                stopRepeat()
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key, let action = HousingRemote.action(for: key.charactersIgnoringModifiers) else { continue }
                handled = true
                onAction?(action, HousingRemote.stepFactor)
                if action == .zoomIn || action == .zoomOut { startRepeat(action, key: key.keyCode) }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if presses.contains(where: { $0.key?.keyCode == heldKey }) { stopRepeat() }
            super.pressesEnded(presses, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            stopRepeat()
            super.pressesCancelled(presses, with: event)
        }

        private func startRepeat(_ action: HousingRemote.Action, key: UIKeyboardHIDUsage) {
            stopRepeat()
            heldKey = key
            let start = Date().addingTimeInterval(HousingRemote.holdDelay)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: HousingRemote.holdInterval, repeats: true) { [weak self] _ in
                guard Date() >= start else { return }
                self?.onAction?(action, HousingRemote.holdFactor)
            }
        }

        private func stopRepeat() {
            repeatTimer?.invalidate()
            repeatTimer = nil
            heldKey = nil
        }
    }
}

/// Whether a keyboard (an underwater housing pairs as one) is connected. While it is, the camera keeps the
/// screen on: in the housing nobody touches the phone, and a locked screen underwater cannot be woken.
@MainActor
@Observable
final class HousingMonitor {
    private(set) var isConnected = GCKeyboard.coalesced != nil
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.isConnected = GCKeyboard.coalesced != nil }
            })
        }
    }
}
