import Foundation

/// The viewfinder's exposure aids, drawn only on the viewfinder, never into photos or recordings.
/// Levels are display levels of the graded picture (0 black, 1 white). Grade.metal (`assist`) draws the
/// same bands and stripes.
public enum ExposureAssist {
    /// Zebra stripes from this level up: close to clipping.
    public static let zebraLevel = 0.95

    public enum Band: Equatable, Sendable {
        /// Crushed to black: purple.
        case crushed
        /// Deep shadow: blue.
        case shadow
        /// Middle grey (18% grey, about 0.46 in sRGB): green.
        case middleGrey
        /// One stop over middle grey, where lit skin sits: pink.
        case skin
        /// Just under clipping: yellow.
        case nearClip
        /// Clipped: red.
        case clipped
        /// Everything else is shown in grey.
        case other
    }

    public static func band(luma: Double) -> Band {
        switch luma {
        case ..<0.025: .crushed
        case ..<0.10: .shadow
        case 0.42 ..< 0.50: .middleGrey
        case 0.60 ..< 0.68: .skin
        case 0.93 ..< 0.985: .nearClip
        case 0.985...: .clipped
        default: .other
        }
    }

    /// The false-colour picture for a pixel of display level `luma`.
    public static func falseColor(luma: Double) -> SIMD3<Double> {
        switch band(luma: luma) {
        case .crushed: SIMD3(0.55, 0.1, 0.85)
        case .shadow: SIMD3(0.1, 0.35, 1.0)
        case .middleGrey: SIMD3(0.2, 0.85, 0.3)
        case .skin: SIMD3(1.0, 0.55, 0.7)
        case .nearClip: SIMD3(1.0, 0.9, 0.1)
        case .clipped: SIMD3(1.0, 0.15, 0.1)
        case .other: SIMD3(repeating: luma * 0.85)
        }
    }

    /// Diagonal zebra stripes, 8 pixels wide, that crawl with `phase`.
    public static func zebraStripe(x: Int, y: Int, phase: Int) -> Bool {
        ((x + y + phase) / 8) % 2 == 0
    }
}

/// White balance the camera is held at: auto, or a colour temperature with a tint.
public enum WhiteBalanceSteps {
    public static let kelvins = [2800, 3200, 4000, 4800, 5600, 6500, 7500]
    public static let tints = [-30, -15, 0, 15, 30]

    /// "5600K", or "AUTO".
    public static func label(kelvin: Int?) -> String {
        kelvin.map { "\($0)K" } ?? "AUTO"
    }
}

/// An RGB waveform, as video monitors draw it: across are the columns of the picture, up each channel's
/// level, brighter where more pixels share that level in that column.
public struct Waveform: Equatable, Sendable {
    public let columns: Int
    public let levels: Int
    /// Pixels sampled per column.
    public private(set) var samplesPerColumn = 0
    /// Per channel (red, green, blue): `columns * levels` counts, column-major (`column * levels + level`).
    public private(set) var counts: [[UInt32]]

    public init(columns: Int = 128, levels: Int = 64) {
        self.columns = max(1, columns)
        self.levels = max(2, levels)
        counts = Array(repeating: Array(repeating: 0, count: self.columns * self.levels), count: 3)
    }

    /// Counts made elsewhere (on the GPU): `flat` holds red, green and blue in turn, each `columns * levels`.
    public init(columns: Int, levels: Int, flat: [UInt32], samplesPerColumn: Int) {
        self.init(columns: columns, levels: levels)
        let size = self.columns * self.levels
        guard flat.count >= size * 3 else { return }
        counts = (0 ..< 3).map { Array(flat[$0 * size ..< ($0 + 1) * size]) }
        self.samplesPerColumn = max(0, samplesPerColumn)
    }

    public func level(of value: UInt8) -> Int {
        min(Int(value) * levels / 256, levels - 1)
    }

    mutating func add(column: Int, red: UInt8, green: UInt8, blue: UInt8) {
        let base = column * levels
        counts[0][base + level(of: red)] += 1
        counts[1][base + level(of: green)] += 1
        counts[2][base + level(of: blue)] += 1
    }

    /// Measures BGRA pixels, sampling `rows` rows and two pixels per column.
    public static func measure(
        bgra: UnsafeRawBufferPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        columns: Int = 128,
        levels: Int = 64,
        rows: Int = 72
    ) -> Waveform {
        var waveform = Waveform(columns: columns, levels: levels)
        guard width > 0, height > 0, bgra.count >= bytesPerRow * height else { return waveform }
        let rowCount = min(rows, height)
        for column in 0 ..< waveform.columns {
            for sub in 0 ..< 2 {
                let x = min(width - 1, (column * 2 + sub) * width / (waveform.columns * 2))
                for r in 0 ..< rowCount {
                    let y = min(height - 1, (r * height + height / 2) / rowCount)
                    let offset = y * bytesPerRow + x * 4
                    waveform.add(column: column, red: bgra[offset + 2], green: bgra[offset + 1], blue: bgra[offset])
                }
            }
        }
        waveform.samplesPerColumn = rowCount * 2
        return waveform
    }

    /// Brightness of a cell, 0...1: how many of the column's samples sit at that level, eased so a few
    /// pixels still show.
    public func intensity(channel: Int, column: Int, level: Int) -> Double {
        guard samplesPerColumn > 0 else { return 0 }
        let share = Double(counts[channel][column * levels + level]) / Double(samplesPerColumn)
        return min(1, (share * Double(levels) / 3).squareRoot())
    }

    /// RGBA pixels, premultiplied, `columns` wide and `levels` high, white at the top. Each channel draws
    /// in its own colour, so where they agree the trace is white.
    public func render() -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: columns * levels * 4)
        for column in 0 ..< columns {
            for level in 0 ..< levels {
                let r = intensity(channel: 0, column: column, level: level)
                let g = intensity(channel: 1, column: column, level: level)
                let b = intensity(channel: 2, column: column, level: level)
                let row = levels - 1 - level
                let index = (row * columns + column) * 4
                pixels[index] = UInt8(r * 255)
                pixels[index + 1] = UInt8(g * 255)
                pixels[index + 2] = UInt8(b * 255)
                pixels[index + 3] = UInt8(max(r, g, b) * 255)
            }
        }
        return pixels
    }
}
