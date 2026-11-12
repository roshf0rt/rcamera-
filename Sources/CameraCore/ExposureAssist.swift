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

/// A luma waveform, as video monitors and Kino draw it: across are the columns of the picture as the phone
/// is held, up the brightness, brighter where more pixels share that brightness in that column.
public struct Waveform: Equatable, Sendable {
    public let columns: Int
    public let levels: Int
    /// Pixels sampled per column.
    public private(set) var samplesPerColumn = 0
    /// `columns * levels` counts, column-major (`column * levels + level`).
    public private(set) var counts: [UInt32]

    public init(columns: Int = 128, levels: Int = 64) {
        self.columns = max(1, columns)
        self.levels = max(2, levels)
        counts = Array(repeating: 0, count: self.columns * self.levels)
    }

    /// Counts made elsewhere (on the GPU), `columns * levels` of them.
    public init(columns: Int, levels: Int, flat: [UInt32], samplesPerColumn: Int) {
        self.init(columns: columns, levels: levels)
        guard flat.count >= counts.count else { return }
        counts = Array(flat[0 ..< counts.count])
        self.samplesPerColumn = max(0, samplesPerColumn)
    }

    /// The level a luma of 0...1 falls in.
    public func level(of luma: Double) -> Int {
        min(max(Int(luma * Double(levels)), 0), levels - 1)
    }

    /// Which column a pixel at `x`, `y` of a `width` × `height` picture falls in, for a phone turned
    /// `quarterTurns` from portrait (`DeviceOrientation.quarterTurns`): the columns run left to right as
    /// the picture is seen with the phone held that way.
    public static func column(x: Int, y: Int, width: Int, height: Int, columns: Int, quarterTurns: Int) -> Int {
        let across: Double
        switch quarterTurns {
        case 1: across = (Double(y) + 0.5) / Double(max(height, 1))
        case -1: across = 1 - (Double(y) + 0.5) / Double(max(height, 1))
        default: across = (Double(x) + 0.5) / Double(max(width, 1))
        }
        return min(max(Int(across * Double(columns)), 0), columns - 1)
    }

    /// Measures BGRA pixels, about `rows` × 2 `columns` samples, as `Grade.metal` does.
    public static func measure(
        bgra: UnsafeRawBufferPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        columns: Int = 128,
        levels: Int = 64,
        rows: Int = 72,
        quarterTurns: Int = 0
    ) -> Waveform {
        var waveform = Waveform(columns: columns, levels: levels)
        guard width > 0, height > 0, bgra.count >= bytesPerRow * height else { return waveform }
        let stepX = max(1, width / (waveform.columns * 2))
        let stepY = max(1, height / rows)
        var samples = 0
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * 4
                let luma = (0.299 * Double(bgra[offset + 2]) + 0.587 * Double(bgra[offset + 1]) + 0.114 * Double(bgra[offset])) / 255
                let column = column(x: x, y: y, width: width, height: height, columns: waveform.columns, quarterTurns: quarterTurns)
                waveform.counts[column * waveform.levels + waveform.level(of: luma)] += 1
                samples += 1
            }
        }
        waveform.samplesPerColumn = samples / waveform.columns
        return waveform
    }

    /// Brightness of a cell, 0...1. A column whose pixels spread evenly over all levels draws at about a
    /// third; a level holding an eighth of the column draws fully. A few stray pixels stay faint, so
    /// noise does not fill the panel.
    public func intensity(column: Int, level: Int) -> Double {
        guard samplesPerColumn > 0 else { return 0 }
        let share = Double(counts[column * levels + level]) / Double(samplesPerColumn)
        return min(1, (share * 8).squareRoot())
    }

    /// RGBA pixels, premultiplied, `columns` wide and `levels` high, white at the top: a pale green trace,
    /// whiter where it is dense, as on a monitor.
    public func render() -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: columns * levels * 4)
        for column in 0 ..< columns {
            for level in 0 ..< levels {
                let value = intensity(column: column, level: level)
                guard value > 0 else { continue }
                let row = levels - 1 - level
                let index = (row * columns + column) * 4
                // Green when faint, towards white when dense.
                let white = value * value
                pixels[index] = UInt8(value * (0.55 + 0.45 * white) * 255)
                pixels[index + 1] = UInt8(value * 255)
                pixels[index + 2] = UInt8(value * (0.6 + 0.4 * white) * 255)
                pixels[index + 3] = UInt8(value * 255)
            }
        }
        return pixels
    }
}

/// A histogram of the graded picture, as cameras draw it: across is brightness from black to white, up is how
/// much of the picture has it, for red, green, blue and luma. `Grade.metal` counts it for the viewfinder;
/// `measure` counts a finished picture the same way.
public struct Histogram: Equatable, Sendable {
    public enum Channel: Int, CaseIterable, Sendable {
        case red, green, blue, luma
    }

    public let bins: Int
    /// Pixels counted (each adds one to every channel).
    public private(set) var samples = 0
    /// `4 * bins` counts, channel-major (`channel * bins + bin`), in the order of `Channel`.
    public private(set) var counts: [UInt32]

    public init(bins: Int = 128) {
        self.bins = max(2, bins)
        counts = Array(repeating: 0, count: self.bins * Channel.allCases.count)
    }

    /// Counts made elsewhere (on the GPU), `4 * bins` of them.
    public init(bins: Int, flat: [UInt32]) {
        self.init(bins: bins)
        guard flat.count >= counts.count else { return }
        counts = Array(flat[0 ..< counts.count])
        samples = counts[Channel.luma.rawValue * self.bins ..< counts.count].reduce(0) { $0 + Int($1) }
    }

    /// The bin a level of 0...1 falls in.
    public func bin(of level: Double) -> Int {
        min(max(Int(level * Double(bins)), 0), bins - 1)
    }

    public func count(_ channel: Channel, bin: Int) -> Int {
        Int(counts[channel.rawValue * bins + bin])
    }

    /// Counts 8-bit pixels, four bytes each (RGBA when `redFirst`, else BGRA), about `maxSamples` of them
    /// spread evenly over the picture.
    public static func measure(
        pixels: UnsafeRawBufferPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        redFirst: Bool = false,
        bins: Int = 128,
        maxSamples: Int = 60000
    ) -> Histogram {
        var histogram = Histogram(bins: bins)
        guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * (height - 1) + width * 4 else { return histogram }
        let step = max(1, Int((Double(width * height) / Double(max(maxSamples, 1))).squareRoot().rounded(.up)))
        let size = histogram.bins
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = y * bytesPerRow + x * 4
                let red = Double(pixels[offset + (redFirst ? 0 : 2)]) / 255
                let green = Double(pixels[offset + 1]) / 255
                let blue = Double(pixels[offset + (redFirst ? 2 : 0)]) / 255
                let luma = 0.299 * red + 0.587 * green + 0.114 * blue
                histogram.counts[histogram.bin(of: red)] += 1
                histogram.counts[size + histogram.bin(of: green)] += 1
                histogram.counts[2 * size + histogram.bin(of: blue)] += 1
                histogram.counts[3 * size + histogram.bin(of: luma)] += 1
                histogram.samples += 1
            }
        }
        return histogram
    }

    /// The count the tallest bar stands for: the largest bin of any channel, the first and last bins left
    /// out, so a clipped sky or a black border does not flatten everything else.
    public var peak: Int {
        var top: UInt32 = 0
        for channel in 0 ..< Channel.allCases.count {
            for bin in 1 ..< bins - 1 { top = max(top, counts[channel * bins + bin]) }
        }
        return Int(top)
    }

    /// Bar heights of a channel, 0...1 against `peak`. The end bins stop at 1.
    public func heights(_ channel: Channel) -> [Double] {
        let peak = peak
        guard peak > 0 else { return Array(repeating: 0, count: bins) }
        return (0 ..< bins).map { min(1, Double(count(channel, bin: $0)) / Double(peak)) }
    }

    /// Share of the picture whose luma sits in the darkest bins (about the lowest 2.5%, `ExposureAssist`'s crushed band).
    public var crushedShare: Double { share(of: .luma, bins: 0 ..< max(1, bin(of: 0.025) + 1)) }

    /// Share of the picture with a channel in the brightest bins (from about 98.5% up): clipped.
    public var clippedShare: Double {
        let first = min(bins - 1, bin(of: 0.985))
        return [Channel.red, .green, .blue].map { share(of: $0, bins: first ..< bins) }.max() ?? 0
    }

    private func share(of channel: Channel, bins range: Range<Int>) -> Double {
        guard samples > 0 else { return 0 }
        let sum = range.reduce(0) { $0 + count(channel, bin: $1) }
        return Double(sum) / Double(samples)
    }
}
