public enum CameraPhase: Equatable, Sendable {
    case idle
    case reconfiguringMode
    case reconfiguringVideoFormat
    case reconfiguringLens
    case reconfiguringLensInRecording
    case startingRecording
    case finishingRecording
    case videoRecording
}

public enum CameraEvent: Equatable, Sendable {
    case switchMode(CaptureMode)
    case switchDevice(LensID)
    case updateVideoConfiguration(VideoFormat)
    case startRecordingTap
    case stopRecordingTap
    case reconfigurationSessionDidStart
    case reconfigurationSessionDidFinish
    case videoRecordingDidStart
    case videoRecordingDidFinish
}

public enum CameraEffect: Equatable, Sendable {
    case reconfigureSessionToMode(CaptureMode)
    case reconfigureSessionToVideoFormat(VideoFormat)
    case reconfigureSessionToDevice(LensID)
    case startVideoRecording
    case stopVideoRecording
}

public enum CameraStateMachineError: Error, Equatable, Sendable {
    case insufficientTransition(from: CameraPhase, event: CameraEvent)
}

/// Pure transition logic. Feed events in, get effects out; the caller runs the effects.
///
/// The table follows the transitions recovered from the Lampa 2.1.5 binary
/// (see CAMERA_FSM_TABLE.md). Where that table is unverified, the behavior chosen
/// here is noted inline.
public struct CameraStateMachine: Sendable {
    public private(set) var phase: CameraPhase
    public private(set) var configuration: CameraConfiguration

    public init(configuration: CameraConfiguration) {
        self.phase = .idle
        self.configuration = configuration
    }

    public mutating func handle(_ event: CameraEvent) throws -> [CameraEffect] {
        switch event {
        case .switchMode(let mode):
            return try switchMode(to: mode, event: event)
        case .switchDevice(let lens):
            return try switchDevice(to: lens, event: event)
        case .updateVideoConfiguration(let format):
            // Accepted from any phase, including recording. The table shows no guard here.
            configuration.format = format
            phase = .reconfiguringVideoFormat
            return [.reconfigureSessionToVideoFormat(format)]
        case .startRecordingTap:
            guard [.idle, .reconfiguringMode, .reconfiguringLens].contains(phase) else {
                throw CameraStateMachineError.insufficientTransition(from: phase, event: event)
            }
            phase = .startingRecording
            return [.startVideoRecording]
        case .stopRecordingTap:
            guard phase == .videoRecording else {
                throw CameraStateMachineError.insufficientTransition(from: phase, event: event)
            }
            phase = .finishingRecording
            return [.stopVideoRecording]
        case .reconfigurationSessionDidStart:
            return []
        case .reconfigurationSessionDidFinish:
            switch phase {
            case .reconfiguringMode, .reconfiguringVideoFormat, .reconfiguringLens:
                phase = .idle
            case .reconfiguringLensInRecording:
                phase = .videoRecording
            default:
                break
            }
            return []
        case .videoRecordingDidStart:
            phase = .videoRecording
            return []
        case .videoRecordingDidFinish:
            // The table sends these phases to idle. The last mode stays in configuration.
            switch phase {
            case .startingRecording, .finishingRecording, .videoRecording:
                phase = .idle
            default:
                break
            }
            return []
        }
    }

    private mutating func switchMode(to mode: CaptureMode, event: CameraEvent) throws -> [CameraEffect] {
        switch phase {
        case .idle, .reconfiguringMode:
            guard mode != configuration.mode else { return [] }
        case .reconfiguringVideoFormat, .reconfiguringLens, .reconfiguringLensInRecording, .finishingRecording:
            break
        case .startingRecording, .videoRecording:
            throw CameraStateMachineError.insufficientTransition(from: phase, event: event)
        }
        configuration.mode = mode
        phase = .reconfiguringMode
        return [.reconfigureSessionToMode(mode)]
    }

    private mutating func switchDevice(to lens: LensID, event: CameraEvent) throws -> [CameraEffect] {
        switch phase {
        case .idle, .reconfiguringMode:
            configuration.lens = lens
            phase = .reconfiguringLens
        case .reconfiguringVideoFormat, .reconfiguringLens, .reconfiguringLensInRecording:
            configuration.lens = lens
        case .videoRecording:
            configuration.lens = lens
            phase = .reconfiguringLensInRecording
        case .startingRecording, .finishingRecording:
            throw CameraStateMachineError.insufficientTransition(from: phase, event: event)
        }
        return [.reconfigureSessionToDevice(lens)]
    }
}
