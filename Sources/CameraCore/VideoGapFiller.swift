/// Decides which frames to repeat when the camera drops frames while recording.
///
/// Mirrors the behavior recovered from Lampa: once a frame arrives more than four frame intervals
/// after the previous one, the last frame is repeated at regular intervals up to the new frame.
public enum VideoGapFiller {
    public static let thresholdIntervals: Int64 = 4
    public static let maxInsertedFrames = 30

    /// Timestamps (in `timescale` ticks) at which the previous frame should be repeated.
    /// Empty when the gap is small enough to leave alone.
    public static func fillTimes(last: Int64, current: Int64, timescale: Int32, fps: Int) -> [Int64] {
        guard fps > 0, timescale > 0 else { return [] }
        let interval = Int64(timescale) / Int64(fps)
        guard interval > 0, current > last + thresholdIntervals * interval else { return [] }

        var times: [Int64] = []
        var next = last + interval
        // Stop half an interval short so the repeated frame never collides with the real one.
        while next < current - interval / 2, times.count < maxInsertedFrames {
            times.append(next)
            next += interval
        }
        return times
    }
}
