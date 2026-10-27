import SwiftUI

@main
struct RCameraApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            CameraView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
