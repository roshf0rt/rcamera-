import SwiftUI

/// RWater: a camera for an underwater housing. It shares the camera engine with RCamera, without the film
/// looks: real photos (not frames of the stream), Apple Log video exposed slightly to the right, and AutoMotion
/// that keeps the shutter where it is and turns only ISO.
@main
struct RWaterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            UnderwaterView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
