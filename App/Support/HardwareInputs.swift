import AppIntents
import AVFoundation
import AVKit
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

/// Camera Control (iPhone 16 and later, iOS 18): a press of the hardware button takes a photo or starts
/// a recording, the same as the shutter. The button is a press on the whole viewfinder.
@available(iOS 18.0, *)
struct CameraControlHost: UIViewRepresentable {
    let onPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let interaction = AVCaptureEventInteraction(
            primary: { event in
                if event.phase == .ended { onPress() }
            },
            secondary: { _ in }
        )
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
