import XCTest
import CameraCore

final class CameraStateMachineTests: XCTestCase {
    private func makeMachine() -> CameraStateMachine {
        CameraStateMachine(configuration: CameraConfiguration(mode: .photo, format: .hd1080p30, lens: .wide))
    }

    private func machine(after events: [CameraEvent]) throws -> CameraStateMachine {
        var machine = makeMachine()
        for event in events {
            _ = try machine.handle(event)
        }
        return machine
    }

    private let newFormat = VideoFormat(width: 3840, height: 2160, fps: 60)

    // Paths that reach each phase from idle.
    private let toReconfiguringMode: [CameraEvent] = [.switchMode(.video)]
    private let toReconfiguringVideoFormat: [CameraEvent] = [.updateVideoConfiguration(VideoFormat(width: 3840, height: 2160, fps: 60))]
    private let toReconfiguringLens: [CameraEvent] = [.switchDevice(.ultraWide)]
    private let toStartingRecording: [CameraEvent] = [.startRecordingTap]
    private let toVideoRecording: [CameraEvent] = [.startRecordingTap, .videoRecordingDidStart]
    private let toFinishingRecording: [CameraEvent] = [.startRecordingTap, .videoRecordingDidStart, .stopRecordingTap]
    private let toLensInRecording: [CameraEvent] = [.startRecordingTap, .videoRecordingDidStart, .switchDevice(.telephoto)]

    // MARK: switchMode

    func testSwitchModeFromIdleReconfiguresMode() throws {
        var m = makeMachine()
        let effects = try m.handle(.switchMode(.video))
        XCTAssertEqual(effects, [.reconfigureSessionToMode(.video)])
        XCTAssertEqual(m.phase, .reconfiguringMode)
        XCTAssertEqual(m.configuration.mode, .video)
    }

    func testSwitchModeToCurrentModeIsNoOp() throws {
        var m = makeMachine()
        let effects = try m.handle(.switchMode(.photo))
        XCTAssertEqual(effects, [])
        XCTAssertEqual(m.phase, .idle)
    }

    func testSwitchModeFromReconfiguringModeToSameModeIsNoOp() throws {
        var m = try machine(after: toReconfiguringMode)
        let effects = try m.handle(.switchMode(.video))
        XCTAssertEqual(effects, [])
        XCTAssertEqual(m.phase, .reconfiguringMode)
    }

    func testSwitchModeFromVideoFormatReconfigurationIsAccepted() throws {
        var m = try machine(after: toReconfiguringVideoFormat)
        let effects = try m.handle(.switchMode(.video))
        XCTAssertEqual(effects, [.reconfigureSessionToMode(.video)])
        XCTAssertEqual(m.phase, .reconfiguringMode)
    }

    func testSwitchModeFromLensReconfigurationIsAccepted() throws {
        var m = try machine(after: toReconfiguringLens)
        let effects = try m.handle(.switchMode(.video))
        XCTAssertEqual(effects, [.reconfigureSessionToMode(.video)])
        XCTAssertEqual(m.phase, .reconfiguringMode)
    }

    func testSwitchModeFromLensInRecordingIsAccepted() throws {
        var m = try machine(after: toLensInRecording)
        let effects = try m.handle(.switchMode(.photo))
        XCTAssertEqual(effects.count, 1)
        XCTAssertEqual(m.phase, .reconfiguringMode)
    }

    func testSwitchModeFromFinishingRecordingIsAccepted() throws {
        var m = try machine(after: toFinishingRecording)
        let effects = try m.handle(.switchMode(.photo))
        XCTAssertEqual(effects, [.reconfigureSessionToMode(.photo)])
        XCTAssertEqual(m.phase, .reconfiguringMode)
    }

    func testSwitchModeWhileStartingRecordingThrows() throws {
        var m = try machine(after: toStartingRecording)
        XCTAssertThrowsError(try m.handle(.switchMode(.video))) { error in
            XCTAssertEqual(error as? CameraStateMachineError,
                           .insufficientTransition(from: .startingRecording, event: .switchMode(.video)))
        }
        XCTAssertEqual(m.phase, .startingRecording)
    }

    func testSwitchModeWhileVideoRecordingThrows() throws {
        var m = try machine(after: toVideoRecording)
        XCTAssertThrowsError(try m.handle(.switchMode(.photo)))
        XCTAssertEqual(m.phase, .videoRecording)
    }

    // MARK: switchDevice

    func testSwitchDeviceFromIdleReconfiguresLens() throws {
        var m = makeMachine()
        let effects = try m.handle(.switchDevice(.ultraWide))
        XCTAssertEqual(effects, [.reconfigureSessionToDevice(.ultraWide)])
        XCTAssertEqual(m.phase, .reconfiguringLens)
        XCTAssertEqual(m.configuration.lens, .ultraWide)
    }

    func testSwitchDeviceFromVideoFormatReconfigurationKeepsPhase() throws {
        var m = try machine(after: toReconfiguringVideoFormat)
        let effects = try m.handle(.switchDevice(.front))
        XCTAssertEqual(effects, [.reconfigureSessionToDevice(.front)])
        XCTAssertEqual(m.phase, .reconfiguringVideoFormat)
        XCTAssertEqual(m.configuration.lens, .front)
    }

    func testSwitchDeviceFromLensReconfigurationKeepsPhase() throws {
        var m = try machine(after: toReconfiguringLens)
        _ = try m.handle(.switchDevice(.telephoto))
        XCTAssertEqual(m.phase, .reconfiguringLens)
    }

    func testSwitchDeviceFromVideoRecordingEntersLensInRecording() throws {
        var m = try machine(after: toVideoRecording)
        let effects = try m.handle(.switchDevice(.telephoto))
        XCTAssertEqual(effects, [.reconfigureSessionToDevice(.telephoto)])
        XCTAssertEqual(m.phase, .reconfiguringLensInRecording)
    }

    func testSwitchDeviceFromLensInRecordingKeepsPhase() throws {
        var m = try machine(after: toLensInRecording)
        _ = try m.handle(.switchDevice(.wide))
        XCTAssertEqual(m.phase, .reconfiguringLensInRecording)
    }

    func testSwitchDeviceWhileStartingOrFinishingRecordingThrows() throws {
        var starting = try machine(after: toStartingRecording)
        XCTAssertThrowsError(try starting.handle(.switchDevice(.ultraWide)))
        var finishing = try machine(after: toFinishingRecording)
        XCTAssertThrowsError(try finishing.handle(.switchDevice(.ultraWide)))
    }

    // MARK: updateVideoConfiguration

    func testUpdateVideoConfigurationFromIdle() throws {
        var m = makeMachine()
        let effects = try m.handle(.updateVideoConfiguration(newFormat))
        XCTAssertEqual(effects, [.reconfigureSessionToVideoFormat(newFormat)])
        XCTAssertEqual(m.phase, .reconfiguringVideoFormat)
        XCTAssertEqual(m.configuration.format, newFormat)
    }

    func testUpdateVideoConfigurationFromVideoRecordingIsAcceptedAsInTable() throws {
        var m = try machine(after: toVideoRecording)
        _ = try m.handle(.updateVideoConfiguration(newFormat))
        XCTAssertEqual(m.phase, .reconfiguringVideoFormat)
    }

    // MARK: recording start / stop

    func testStartRecordingFromIdleEntersStartingRecording() throws {
        var m = makeMachine()
        let effects = try m.handle(.startRecordingTap)
        XCTAssertEqual(effects, [.startVideoRecording])
        XCTAssertEqual(m.phase, .startingRecording)
    }

    func testStartRecordingFromReconfiguringLensIsAccepted() throws {
        var m = try machine(after: toReconfiguringLens)
        _ = try m.handle(.startRecordingTap)
        XCTAssertEqual(m.phase, .startingRecording)
    }

    func testStartRecordingFromVideoFormatReconfigurationThrows() throws {
        var m = try machine(after: toReconfiguringVideoFormat)
        XCTAssertThrowsError(try m.handle(.startRecordingTap))
    }

    func testStartRecordingWhileVideoRecordingThrows() throws {
        var m = try machine(after: toVideoRecording)
        XCTAssertThrowsError(try m.handle(.startRecordingTap))
    }

    func testStopRecordingFromVideoRecordingEntersFinishingRecording() throws {
        var m = try machine(after: toVideoRecording)
        let effects = try m.handle(.stopRecordingTap)
        XCTAssertEqual(effects, [.stopVideoRecording])
        XCTAssertEqual(m.phase, .finishingRecording)
    }

    func testStopRecordingFromIdleThrows() throws {
        var m = makeMachine()
        XCTAssertThrowsError(try m.handle(.stopRecordingTap))
        XCTAssertEqual(m.phase, .idle)
    }

    func testStopRecordingWhileStartingThrows() throws {
        var m = try machine(after: toStartingRecording)
        XCTAssertThrowsError(try m.handle(.stopRecordingTap))
    }

    // MARK: reconfigurationSession events

    func testReconfigurationSessionDidStartIsNoOpEverywhere() throws {
        var m = try machine(after: toVideoRecording)
        let effects = try m.handle(.reconfigurationSessionDidStart)
        XCTAssertEqual(effects, [])
        XCTAssertEqual(m.phase, .videoRecording)
    }

    func testReconfigurationSessionDidFinishReturnsReconfiguringPhasesToIdle() throws {
        for path in [toReconfiguringMode, toReconfiguringVideoFormat, toReconfiguringLens] {
            var m = try machine(after: path)
            let effects = try m.handle(.reconfigurationSessionDidFinish)
            XCTAssertEqual(effects, [])
            XCTAssertEqual(m.phase, .idle)
        }
    }

    func testReconfigurationSessionDidFinishInLensInRecordingReturnsToVideoRecording() throws {
        var m = try machine(after: toLensInRecording)
        _ = try m.handle(.reconfigurationSessionDidFinish)
        XCTAssertEqual(m.phase, .videoRecording)
    }

    func testReconfigurationSessionDidFinishIsIgnoredInRecordingPhases() throws {
        var starting = try machine(after: toStartingRecording)
        _ = try starting.handle(.reconfigurationSessionDidFinish)
        XCTAssertEqual(starting.phase, .startingRecording)

        var finishing = try machine(after: toFinishingRecording)
        _ = try finishing.handle(.reconfigurationSessionDidFinish)
        XCTAssertEqual(finishing.phase, .finishingRecording)

        var recording = try machine(after: toVideoRecording)
        _ = try recording.handle(.reconfigurationSessionDidFinish)
        XCTAssertEqual(recording.phase, .videoRecording)
    }

    // MARK: recording callbacks

    func testVideoRecordingDidStartEntersVideoRecordingFromAnyPhase() throws {
        var m = try machine(after: toStartingRecording)
        _ = try m.handle(.videoRecordingDidStart)
        XCTAssertEqual(m.phase, .videoRecording)
    }

    func testVideoRecordingDidFinishReturnsToIdleKeepingMode() throws {
        for path in [toStartingRecording, toFinishingRecording, toVideoRecording] {
            var m = try machine(after: path)
            let effects = try m.handle(.videoRecordingDidFinish)
            XCTAssertEqual(effects, [])
            XCTAssertEqual(m.phase, .idle)
        }
    }

    func testVideoRecordingDidFinishIsIgnoredInLensInRecording() throws {
        var m = try machine(after: toLensInRecording)
        _ = try m.handle(.videoRecordingDidFinish)
        XCTAssertEqual(m.phase, .reconfiguringLensInRecording)
    }

    // MARK: full cycle

    func testFullRecordingCycleReturnsToIdle() throws {
        var m = makeMachine()
        let script: [(CameraEvent, [CameraEffect])] = [
            (.startRecordingTap, [.startVideoRecording]),
            (.videoRecordingDidStart, []),
            (.stopRecordingTap, [.stopVideoRecording]),
            (.videoRecordingDidFinish, []),
        ]
        for (event, expected) in script {
            XCTAssertEqual(try m.handle(event), expected)
        }
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(m.configuration.mode, .photo)
    }
}
