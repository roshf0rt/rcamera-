import XCTest
@testable import CameraCore

final class PhotoTextureTests: XCTestCase {
    func testLevelsBecomeTheSameTextureTheyAlwaysMeant() {
        var adjustments = LookAdjustments()
        let medium = PhotoTexture(grain: .medium, halation: .medium)
        let strength = medium.resolve(grain: 0.5, halation: 0.6, adjustments: &adjustments)
        XCTAssertEqual(strength.grain, 0.5, accuracy: 1e-9)
        XCTAssertEqual(strength.halation, 0.6, accuracy: 1e-9)
        XCTAssertEqual(adjustments, LookAdjustments(), "levels change neither grain size nor glow")

        let high = PhotoTexture(grain: .high, halation: .low).resolve(grain: 0.5, halation: 0.6, adjustments: &adjustments)
        XCTAssertEqual(high.grain, min(1, 0.5 * 1.7), accuracy: 1e-9)
        XCTAssertEqual(high.halation, 0.3, accuracy: 1e-9)

        let off = PhotoTexture(grain: .off, halation: .off).resolve(grain: 0.5, halation: 0.6, adjustments: &adjustments)
        XCTAssertEqual(off.grain, 0)
        XCTAssertEqual(off.halation, 0)
    }

    func testGrainSizeAndAmountsAreClampedIntoRange() {
        var adjustments = LookAdjustments()
        let texture = PhotoTexture(grainAmount: 5, grainSize: 9, halationAmount: -1)
        let strength = texture.resolve(grain: 0.4, halation: 0.6, adjustments: &adjustments)
        XCTAssertEqual(strength.grain, 0.8, accuracy: 1e-9, "amount stops at 2x")
        XCTAssertEqual(adjustments.grainSize, 4)
        XCTAssertEqual(strength.halation, 0)
    }

    func testOpticalHalationIsANeutralGlowInstead() {
        var adjustments = LookAdjustments()
        adjustments.bloom = 0.1
        let texture = PhotoTexture(halationAmount: 1.5, halation: .optical)
        let strength = texture.resolve(grain: 0.4, halation: 0.6, adjustments: &adjustments)
        XCTAssertEqual(strength.halation, 0, "no red film halation")
        XCTAssertEqual(adjustments.bloom, 0.9, accuracy: 1e-9)

        var capped = LookAdjustments()
        _ = PhotoTexture(halationAmount: 2, halation: .optical).resolve(grain: 0, halation: 0.8, adjustments: &capped)
        XCTAssertEqual(capped.bloom, 1)
    }

    func testNearestLevelsFollowTheAmounts() {
        XCTAssertEqual(PhotoTexture(grainAmount: 0.6).nearestGrainLevel, .low)
        XCTAssertEqual(PhotoTexture(grainAmount: 1.5).nearestGrainLevel, .high)
        XCTAssertEqual(PhotoTexture(grainAmount: 0.1).nearestGrainLevel, .off)
        XCTAssertEqual(PhotoTexture(halationOn: false).nearestHalationLevel, .off)
        XCTAssertEqual(PhotoTexture(halationAmount: 0.05).nearestHalationLevel, .low, "on stays on")
    }

    func testRecordsKeepTextureAndCrossoverAndOldOnesLoadWithout() throws {
        var record = CaptureRecord(kind: .photo, presetID: ArriLook.presetID, grainLevel: .low, crossover: 0.3)
        XCTAssertEqual(record.resolvedTexture, PhotoTexture(grain: .low, halation: .medium))
        record.texture = PhotoTexture(grainAmount: 1.2, grainSize: 2.5, halationOn: true, halationAmount: 0.4, halation: .optical)
        let decoded = try JSONDecoder().decode(CaptureRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.resolvedTexture.halation, .optical)
        XCTAssertEqual(decoded.crossover, 0.3)

        let old = #"{"id":"8D2C1E3A-7A64-4C4E-9E7E-3C1B2A0F5D11","date":0,"kind":"photo","presetID":"preset-1","grainLevel":"high"}"#
        let legacy = try JSONDecoder().decode(CaptureRecord.self, from: Data(old.utf8))
        XCTAssertNil(legacy.texture)
        XCTAssertNil(legacy.crossover)
        XCTAssertEqual(legacy.resolvedTexture.grainAmount, 1.7)
    }
}
