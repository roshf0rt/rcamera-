import Foundation

public enum FlashMode: String, CaseIterable, Codable, Sendable {
    case off
    case auto
    case on

    public var next: FlashMode {
        switch self {
        case .off: .auto
        case .auto: .on
        case .on: .off
        }
    }
}

public enum TimerOption: String, CaseIterable, Codable, Sendable {
    case off
    case threeSeconds
    case fiveSeconds
    case tenSeconds

    public var seconds: Int {
        switch self {
        case .off: 0
        case .threeSeconds: 3
        case .fiveSeconds: 5
        case .tenSeconds: 10
        }
    }

    public var next: TimerOption {
        let all = TimerOption.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public struct CropRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum AspectOption: String, CaseIterable, Codable, Sendable {
    case ratio4x3 = "4:3"
    case ratio3x2 = "3:2"
    case ratio16x9 = "16:9"
    case ratio1x1 = "1:1"

    public var label: String { rawValue }

    /// Long side over short side.
    public var longOverShort: Double {
        switch self {
        case .ratio4x3: 4.0 / 3.0
        case .ratio3x2: 3.0 / 2.0
        case .ratio16x9: 16.0 / 9.0
        case .ratio1x1: 1.0
        }
    }

    /// Height over width for a portrait frame.
    public var portraitHeightOverWidth: Double { longOverShort }

    public var next: AspectOption {
        let all = AspectOption.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// Largest centered rectangle with this aspect. Orientation follows the source.
    /// Width and height are rounded down to even numbers so video encoders accept them.
    public func cropRect(sourceWidth: Int, sourceHeight: Int) -> CropRect {
        let targetWidthOverHeight = sourceWidth >= sourceHeight ? longOverShort : 1.0 / longOverShort
        let sourceWidthOverHeight = Double(sourceWidth) / Double(sourceHeight)
        var width = sourceWidth
        var height = sourceHeight
        if sourceWidthOverHeight > targetWidthOverHeight {
            width = Int((Double(sourceHeight) * targetWidthOverHeight).rounded())
        } else {
            height = Int((Double(sourceWidth) / targetWidthOverHeight).rounded())
        }
        width = max(2, min(sourceWidth, width) & ~1)
        height = max(2, min(sourceHeight, height) & ~1)
        return CropRect(x: (sourceWidth - width) / 2, y: (sourceHeight - height) / 2, width: width, height: height)
    }
}

public enum EVScale {
    public static let range: ClosedRange<Double> = -2.0 ... 2.0
    public static let step = 0.1

    public static func snapped(_ value: Double) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped / step).rounded() * step
    }

    public static func format(_ value: Double) -> String {
        let snapped = snapped(value)
        let text = String(format: "%.1f", abs(snapped))
        if abs(snapped) < 0.05 { return "0.0" }
        return snapped > 0 ? "+" + text : "-" + text
    }
}
