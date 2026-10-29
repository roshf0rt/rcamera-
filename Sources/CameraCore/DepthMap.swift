import Foundation

/// The depth map saved with a portrait photo: disparity (larger is nearer), in the sensor's landscape
/// orientation. Redevelop turns it back into the photo's portrait orientation and blurs the background
/// with it, so the lens and aperture can change after the shot.
public struct DepthMap: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// Row by row, `width` values to a row.
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        self.width = width
        self.height = height
        self.values = values
    }

    private static let magic = Array("DPTH".utf8)

    /// "DPTH", then width and height as 32-bit little-endian integers, then the values as 32-bit floats.
    public func encoded() -> Data {
        var data = Data(Self.magic)
        for number in [UInt32(width), UInt32(height)] {
            withUnsafeBytes(of: number.littleEndian) { data.append(contentsOf: $0) }
        }
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Nil for anything that is not a map written by `encoded()`.
    public init?(encoded data: Data) {
        guard data.count >= 12, Array(data.prefix(4)) == Self.magic else { return nil }
        let width = Int(Self.readUInt32(data, at: 4))
        let height = Int(Self.readUInt32(data, at: 8))
        guard width > 0, height > 0, data.count == 12 + width * height * 4 else { return nil }
        var values = [Float](repeating: 0, count: width * height)
        for index in values.indices {
            values[index] = Float(bitPattern: Self.readUInt32(data, at: 12 + index * 4))
        }
        self.init(width: width, height: height, values: values)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    /// The map as the photo is: turned a quarter clockwise, as `CIImage.oriented(.right)` turns it, cropped
    /// to `aspect`, and sampled to `outWidth` × `outHeight` (nearest neighbour), row by row.
    public func portrait(aspect: AspectOption, outWidth: Int, outHeight: Int) -> [Float] {
        var result = [Float](repeating: 0, count: max(0, outWidth * outHeight))
        guard outWidth > 0, outHeight > 0, width > 0, height > 0, values.count == width * height else { return result }
        // Turned clockwise, a portrait point (px, py) is the landscape point (py, height - px).
        let crop = aspect.cropRect(sourceWidth: height, sourceHeight: width)
        for y in 0 ..< outHeight {
            let py = Double(crop.y) + (Double(y) + 0.5) * Double(crop.height) / Double(outHeight)
            let bx = min(width - 1, max(0, Int(py)))
            for x in 0 ..< outWidth {
                let px = Double(crop.x) + (Double(x) + 0.5) * Double(crop.width) / Double(outWidth)
                let by = min(height - 1, max(0, Int(Double(height) - px)))
                result[y * outWidth + x] = values[by * width + bx]
            }
        }
        return result
    }

    /// Mean of the middle fifth of the map, where a portrait subject usually is. Nil without usable values.
    public var middleDisparity: Float? {
        guard width > 0, height > 0, values.count == width * height else { return nil }
        var sum: Float = 0
        var count = 0
        for y in stride(from: height * 2 / 5, to: height * 3 / 5, by: 2) {
            for x in stride(from: width * 2 / 5, to: width * 3 / 5, by: 2) {
                let value = values[y * width + x]
                if value.isFinite, value > 0 {
                    sum += value
                    count += 1
                }
            }
        }
        return count > 0 ? sum / Float(count) : nil
    }
}
