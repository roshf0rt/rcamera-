@testable import CameraCore
import XCTest

/// Every built-in preset finds its shipped LUT the way the app does (`PresetLibrary` over App/Resources/LUTs),
/// the file parses, and it actually changes colours.
final class BundledLUTTests: XCTestCase {
    private var bundled: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/LUTs", isDirectory: true)
    }

    /// Mean distance from identity over a coarse grid, 0 for a LUT that does nothing.
    private func change(_ lut: LUT3D) -> Float {
        var total: Float = 0
        var count: Float = 0
        for r in stride(from: Float(0.05), through: 0.95, by: 0.15) {
            for g in stride(from: Float(0.05), through: 0.95, by: 0.15) {
                for b in stride(from: Float(0.05), through: 0.95, by: 0.15) {
                    let out = lut.apply(r: r, g: g, b: b)
                    total += abs(out.r - r) + abs(out.g - g) + abs(out.b - b)
                    count += 3
                }
            }
        }
        return total / count
    }

    func testEveryNewBuiltInPresetHasAWorkingLUT() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bundled-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try PresetLibrary(storageDirectory: directory, bundledLUTDirectory: bundled)
        var checked = 0
        for preset in library.presets where FilmCollection.isFilm(preset.id) || VideoCollection.isVideo(preset.id) {
            let video = VideoCollection.entry(id: preset.id)
            // Photos and Rec.709 video use the photo slot (falling back to video); Apple Log-only looks have none.
            if video == nil || video?.hasVideo == true {
                let lut = try XCTUnwrap(try library.loadLUT(for: preset.id, slot: .photo), "\(preset.id): no photo LUT")
                XCTAssertGreaterThan(change(lut), 0.002, "\(preset.id): the LUT changes nothing")
                checked += 1
            }
            if let video, video.hasAppleLog {
                let loaded = video.appleLog2
                    ? try library.loadAppleLog2LUT(for: preset.id)
                    : try library.loadLUT(for: preset.id, slot: .appleLog)
                let lut = try XCTUnwrap(loaded, "\(preset.id): no Log LUT")
                XCTAssertGreaterThan(change(lut), 0.002, "\(preset.id): the Log LUT changes nothing")
            }
        }
        XCTAssertEqual(checked, FilmCollection.entries.count + VideoCollection.entries.filter(\.hasVideo).count)
    }

    func testJaneSuCarriesBothAppleLogVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("janesu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try PresetLibrary(storageDirectory: directory, bundledLUTDirectory: bundled)
        let log1 = try XCTUnwrap(try library.loadLUT(for: "preset-1", slot: .appleLog))
        let log2 = try XCTUnwrap(try library.loadAppleLog2LUT(for: "preset-1"))
        XCTAssertNotEqual(log1, log2, "two files, one per Log version")
        XCTAssertNil(library.appleLog2URL(for: "preset-3"))
        XCTAssertTrue(library.hasAnyLUT(for: "video-ivakin-j200"))
        XCTAssertNil(library.lutURL(for: "video-ivakin-j200", slot: .appleLog))
    }
}
