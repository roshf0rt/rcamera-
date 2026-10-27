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
            guard let text = String(data: data, encoding: .utf8) else {
                throw LUTError.invalidData("not UTF-8 text")
            }
            return try parseCube(text)
        case "lut":
            return try parseBinary(data)
        default:
            throw LUTError.unsupportedFormat(fileExtension)
        }
    }

    static func parseCube(_ text: String) throws -> LUT3D {
        var size: Int?
        var values: [Float] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = parts.first else { continue }

            if Float(first) != nil {
                guard parts.count >= 3,
                      let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2])
                else { throw LUTError.invalidData("bad data line: \(line)") }
                values.append(contentsOf: [r, g, b, 1])
                continue
            }

            switch first.uppercased() {
            case "LUT_3D_SIZE":
                guard parts.count >= 2, let n = Int(parts[1]) else { throw LUTError.invalidData("bad LUT_3D_SIZE") }
                size = n
            case "LUT_1D_SIZE":
                throw LUTError.unsupported1DLUT
            case "DOMAIN_MIN":
                guard parts.dropFirst().compactMap({ Float($0) }) == [0, 0, 0] else { throw LUTError.unsupportedDomain }
            case "DOMAIN_MAX":
                guard parts.dropFirst().compactMap({ Float($0) }) == [1, 1, 1] else { throw LUTError.unsupportedDomain }
            default:
                continue // TITLE and unknown keywords
            }
        }
        guard let size else { throw LUTError.invalidData("missing LUT_3D_SIZE") }
        return try LUT3D(size: size, rgba: values)
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
}
