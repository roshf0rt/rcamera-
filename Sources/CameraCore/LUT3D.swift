import Foundation

public enum LUTError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case unsupported1DLUT
    case unsupportedDomain
    case invalidSize(Int)
    case invalidData(String)
}

/// A 3D color lookup table. `rgba` holds `size^3` RGBA float entries, red varying fastest,
/// the same layout Core Image's color cube filters expect.
public struct LUT3D: Equatable, Sendable {
    public static let sizeRange = 2 ... 128

    public let size: Int
    public let rgba: [Float]

    public init(size: Int, rgba: [Float]) throws {
        guard Self.sizeRange.contains(size) else { throw LUTError.invalidSize(size) }
        guard rgba.count == size * size * size * 4 else {
            throw LUTError.invalidData("expected \(size * size * size * 4) floats, got \(rgba.count)")
        }
        self.size = size
        self.rgba = rgba
    }

    public static func identity(size: Int) throws -> LUT3D {
        var values: [Float] = []
        values.reserveCapacity(size * size * size * 4)
        let scale = Float(max(size - 1, 1))
        for b in 0 ..< size {
            for g in 0 ..< size {
                for r in 0 ..< size {
                    values.append(Float(r) / scale)
                    values.append(Float(g) / scale)
                    values.append(Float(b) / scale)
                    values.append(1)
                }
            }
        }
        return try LUT3D(size: size, rgba: values)
    }

    /// `cube` is the Adobe/Resolve text format. `lut` is the binary format used by the original app:
    /// one byte holding the cube size, then size^3 RGBA8 entries.
    public static func parse(data: Data, fileExtension: String) throws -> LUT3D {
        switch fileExtension.lowercased() {
        case "cube":
            return try parseCube(data)
        case "lut":
            return try parseBinary(data)
        default:
            throw LUTError.unsupportedFormat(fileExtension)
        }
    }

    /// Byte-level parser: Resolve exports are 65^3 lines (about 6 MB), so this avoids per-line String work.
    static func parseCube(_ data: Data) throws -> LUT3D {
        var size: Int?
        var values: [Float] = []

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count
            var index = 0
            while index < count {
                var end = index
                while end < count, bytes[end] != 10, bytes[end] != 13 { end += 1 }
                var cursor = index
                while cursor < end, bytes[cursor] == 32 || bytes[cursor] == 9 { cursor += 1 }

                if cursor < end, bytes[cursor] != 35 {
                    let first = bytes[cursor]
                    if (first >= 48 && first <= 57) || first == 45 || first == 43 || first == 46 {
                        guard let r = parseFloat(bytes, &cursor, end),
                              let g = parseFloat(bytes, &cursor, end),
                              let b = parseFloat(bytes, &cursor, end)
                        else { throw LUTError.invalidData("bad data line") }
                        values.append(r)
                        values.append(g)
                        values.append(b)
                        values.append(1)
                    } else {
                        let line = String(decoding: UnsafeBufferPointer(rebasing: bytes[cursor ..< end]), as: UTF8.self)
                        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                        switch parts.first?.uppercased() {
                        case "LUT_3D_SIZE":
                            guard parts.count >= 2, let n = Int(parts[1]) else { throw LUTError.invalidData("bad LUT_3D_SIZE") }
                            size = n
                            if Self.sizeRange.contains(n) { values.reserveCapacity(n * n * n * 4) }
                        case "LUT_1D_SIZE":
                            throw LUTError.unsupported1DLUT
                        case "DOMAIN_MIN":
                            guard parts.dropFirst().compactMap({ Float($0) }) == [0, 0, 0] else { throw LUTError.unsupportedDomain }
                        case "DOMAIN_MAX":
                            guard parts.dropFirst().compactMap({ Float($0) }) == [1, 1, 1] else { throw LUTError.unsupportedDomain }
                        default:
                            break // TITLE and unknown keywords
                        }
                    }
                }
                index = end + 1
            }
        }
        guard let size else { throw LUTError.invalidData("missing LUT_3D_SIZE") }
        return try LUT3D(size: size, rgba: values)
    }

    private static func parseFloat(_ bytes: UnsafeBufferPointer<UInt8>, _ cursor: inout Int, _ end: Int) -> Float? {
        while cursor < end, bytes[cursor] == 32 || bytes[cursor] == 9 { cursor += 1 }
        guard cursor < end else { return nil }

        var negative = false
        if bytes[cursor] == 45 { negative = true; cursor += 1 } else if bytes[cursor] == 43 { cursor += 1 }

        var value = 0.0
        var digits = 0
        while cursor < end, bytes[cursor] >= 48, bytes[cursor] <= 57 {
            value = value * 10 + Double(bytes[cursor] - 48)
            cursor += 1
            digits += 1
        }
        if cursor < end, bytes[cursor] == 46 {
            cursor += 1
            var divisor = 1.0
            while cursor < end, bytes[cursor] >= 48, bytes[cursor] <= 57 {
                divisor *= 10
                value += Double(bytes[cursor] - 48) / divisor
                cursor += 1
                digits += 1
            }
        }
        guard digits > 0 else { return nil }

        if cursor < end, bytes[cursor] == 101 || bytes[cursor] == 69 {
            var probe = cursor + 1
            var negativeExponent = false
            if probe < end, bytes[probe] == 45 { negativeExponent = true; probe += 1 } else if probe < end, bytes[probe] == 43 { probe += 1 }
            var exponent = 0
            var exponentDigits = 0
            while probe < end, bytes[probe] >= 48, bytes[probe] <= 57 {
                exponent = exponent * 10 + Int(bytes[probe] - 48)
                probe += 1
                exponentDigits += 1
            }
            if exponentDigits > 0 {
                value *= pow(10, Double(negativeExponent ? -exponent : exponent))
                cursor = probe
            }
        }
        return Float(negative ? -value : value)
    }

    static func parseBinary(_ data: Data) throws -> LUT3D {
        guard let first = data.first else { throw LUTError.invalidData("empty file") }
        let size = Int(first)
        guard sizeRange.contains(size) else { throw LUTError.invalidSize(size) }
        let entries = size * size * size
        guard data.count == 1 + entries * 4 else {
            throw LUTError.invalidData("expected \(1 + entries * 4) bytes, got \(data.count)")
        }
        var values: [Float] = []
        values.reserveCapacity(entries * 4)
        let bytes = [UInt8](data.dropFirst())
        for index in 0 ..< entries {
            values.append(Float(bytes[index * 4]) / 255)
            values.append(Float(bytes[index * 4 + 1]) / 255)
            values.append(Float(bytes[index * 4 + 2]) / 255)
            values.append(1)
        }
        return try LUT3D(size: size, rgba: values)
    }

    /// Trilinear lookup, used for tests and CPU fallbacks. Inputs and outputs are 0...1.
    public func apply(r: Float, g: Float, b: Float) -> (r: Float, g: Float, b: Float) {
        let maxIndex = Float(size - 1)
        func split(_ value: Float) -> (Int, Int, Float) {
            let scaled = min(max(value, 0), 1) * maxIndex
            let low = min(Int(scaled), size - 1)
            let high = min(low + 1, size - 1)
            return (low, high, scaled - Float(low))
        }
        let (r0, r1, rt) = split(r)
        let (g0, g1, gt) = split(g)
        let (b0, b1, bt) = split(b)

        func entry(_ ri: Int, _ gi: Int, _ bi: Int) -> (Float, Float, Float) {
            let base = ((bi * size + gi) * size + ri) * 4
            return (rgba[base], rgba[base + 1], rgba[base + 2])
        }
        func mix(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }

        let c00 = mix(entry(r0, g0, b0), entry(r1, g0, b0), rt)
        let c10 = mix(entry(r0, g1, b0), entry(r1, g1, b0), rt)
        let c01 = mix(entry(r0, g0, b1), entry(r1, g0, b1), rt)
        let c11 = mix(entry(r0, g1, b1), entry(r1, g1, b1), rt)
        let c0 = mix(c00, c10, gt)
        let c1 = mix(c01, c11, gt)
        let result = mix(c0, c1, bt)
        return (result.0, result.1, result.2)
    }

    /// Raw float32 bytes in the layout `CIColorCubeWithColorSpace` expects.
    public var float32Data: Data {
        rgba.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// The binary `.lut` layout: one byte holding the size, then RGBA8 entries. 8-bit precision.
    public func binaryLUTData() throws -> Data {
        guard size <= 255 else { throw LUTError.invalidSize(size) }
        var bytes = [UInt8]()
        bytes.reserveCapacity(1 + rgba.count)
        bytes.append(UInt8(size))
        for index in stride(from: 0, to: rgba.count, by: 4) {
            for channel in 0 ..< 3 {
                bytes.append(UInt8(min(max(rgba[index + channel], 0), 1) * 255 + 0.5))
            }
            bytes.append(1)
        }
        return Data(bytes)
    }

    /// The tone response along the neutral axis (black to white), averaged over R, G and B.
    /// Averaging keeps the curve neutral: it carries contrast and roll-off but not a color cast.
    public func neutralCurve() -> [Float] {
        (0 ..< size).map { step in
            let base = ((step * size + step) * size + step) * 4
            return (rgba[base] + rgba[base + 1] + rgba[base + 2]) / 3
        }
    }

    /// Piecewise-linear lookup into a curve sampled at evenly spaced points over 0...1.
    public static func evaluate(curve: [Float], at input: Float) -> Float {
        guard curve.count > 1 else { return input }
        let scaled = min(max(input, 0), 1) * Float(curve.count - 1)
        let low = min(Int(scaled), curve.count - 2)
        let t = scaled - Float(low)
        return curve[low] + (curve[low + 1] - curve[low]) * t
    }

    /// A LUT that first passes each channel through `curve`, then applies this LUT.
    public func composing(preCurve curve: [Float]) throws -> LUT3D {
        var values: [Float] = []
        values.reserveCapacity(rgba.count)
        let scale = Float(max(size - 1, 1))
        for b in 0 ..< size {
            for g in 0 ..< size {
                for r in 0 ..< size {
                    let mapped = apply(
                        r: Self.evaluate(curve: curve, at: Float(r) / scale),
                        g: Self.evaluate(curve: curve, at: Float(g) / scale),
                        b: Self.evaluate(curve: curve, at: Float(b) / scale)
                    )
                    values.append(mapped.r)
                    values.append(mapped.g)
                    values.append(mapped.b)
                    values.append(1)
                }
            }
        }
        return try LUT3D(size: size, rgba: values)
    }

    /// `.cube` text, handy for inspecting generated LUTs in other tools.
    public func cubeText(title: String) -> String {
        var text = "TITLE \"\(title)\"\nLUT_3D_SIZE \(size)\n"
        for index in stride(from: 0, to: rgba.count, by: 4) {
            text += "\(rgba[index]) \(rgba[index + 1]) \(rgba[index + 2])\n"
        }
        return text
    }
}
