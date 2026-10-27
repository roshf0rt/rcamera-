import CameraCore
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.96, green: 0.94, blue: 0.36)
    static let chrome = Color(white: 0.17)
    static let chromeDark = Color(white: 0.09)
    static let cardLight = Color(red: 0.92, green: 0.91, blue: 0.86)
    static let secondaryText = Color(white: 0.55)

    /// One gradient per preset card; the preset's `accentIndex` picks one.
    static let gradients: [[Color]] = [
        [Color(red: 0.20, green: 0.24, blue: 0.45), Color(red: 0.80, green: 0.80, blue: 0.86)],
        [Color(red: 0.16, green: 0.40, blue: 0.32), Color(red: 0.96, green: 0.72, blue: 0.52)],
        [Color(red: 0.20, green: 0.46, blue: 0.98), Color(red: 0.62, green: 0.30, blue: 0.80), Color(red: 0.90, green: 0.28, blue: 0.20)],
        [Color(red: 0.95, green: 0.50, blue: 0.15), Color(red: 0.98, green: 0.86, blue: 0.30)],
        [Color(red: 0.10, green: 0.50, blue: 0.52), Color(red: 0.62, green: 0.92, blue: 0.78)],
        [Color(red: 0.92, green: 0.38, blue: 0.62), Color(red: 0.48, green: 0.30, blue: 0.80)],
        [Color(red: 0.35, green: 0.36, blue: 0.38), Color(red: 0.95, green: 0.95, blue: 0.96)],
        [Color(red: 0.42, green: 0.26, blue: 0.14), Color(red: 0.92, green: 0.68, blue: 0.22)],
        [Color(red: 0.80, green: 0.16, blue: 0.16), Color(red: 0.98, green: 0.62, blue: 0.30)],
        [Color(red: 0.10, green: 0.72, blue: 0.90), Color(red: 0.16, green: 0.30, blue: 0.86)],
    ]

    static func colors(_ index: Int) -> [Color] {
        gradients[((index % gradients.count) + gradients.count) % gradients.count]
    }

    static func gradient(_ index: Int) -> LinearGradient {
        LinearGradient(colors: colors(index), startPoint: .leading, endPoint: .trailing)
    }
}

extension Preset {
    /// Two-letter badge for compact cards, e.g. "ПР" for "Пресет 1".
    var initials: String {
        let letters = name.filter { $0.isLetter }
        return String(letters.prefix(2)).uppercased()
    }
}
