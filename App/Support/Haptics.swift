import SwiftUI
import UIKit

/// All of the app's haptic feedback goes through here, so one switch in Settings turns it off.
enum Haptics {
    static let key = "hapticsEnabled"

    /// On unless the user turned it off. Read from the defaults at each use, so it needs no actor.
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isOn else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        guard isOn else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isOn else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

extension View {
    /// `sensoryFeedback`, unless haptics are off in Settings.
    func haptic<Trigger: Equatable>(_ feedback: SensoryFeedback, trigger: Trigger) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in Haptics.isOn ? feedback : nil }
    }

    /// Feedback only when the trigger becomes true: arriving at zero, at an end, at level.
    func hapticOnArrival(_ feedback: SensoryFeedback, when condition: Bool) -> some View {
        sensoryFeedback(trigger: condition) { _, now in Haptics.isOn && now ? feedback : nil }
    }
}
