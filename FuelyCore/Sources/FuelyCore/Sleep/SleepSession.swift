import Foundation

/// One continuous stretch of sleep built from (possibly overlapping) samples of any source, measured
/// the way Apple's Sleep Score measures it: on the grid of clock minutes. Every minute the session touches is one whole minute, asleep or awake, whichever
/// covers more of it; minutes no sample covers (gaps) are neither.
public struct SleepSession: Sendable, Hashable {
    /// Start of the first asleep sample (the onset used for bedtime consistency).
    public let start: Date
    /// End of the last asleep sample.
    public let end: Date
    /// Clock minutes between `start` and `end` where asleep samples (any source, overlaps once)
    /// cover more than awake ones. A minute only partly covered by sleep (e.g. the first and last
    /// minute) counts whole.
    public let asleepMinutes: Int
    /// Runs of consecutive awake minutes between `start` and `end` (pre-sleep and post-wake awake
    /// are outside the session). An awake sample that wins no minute is no wake-up.
    public let wakeUps: Int
    /// The awake minutes of those runs.
    public let wakeUpMinutes: Int
    /// Sources of the asleep samples in this session, in order of first appearance.
    public let sources: [SleepSampleSource]
}

extension SleepSession {
    /// Merges samples of every source into sessions. Asleep stretches more than
    /// `config.maxGapWithinSession` apart are separate sessions.
    static func sessions(from samples: [SleepSample], config: SleepScoreConfig) -> [SleepSession] {
        let asleep = mergedAsleepIntervals(samples)
        let awake = union(samples.filter { $0.stage == .awake && $0.end > $0.start }
            .map { Span(start: $0.start.timeIntervalSinceReferenceDate, end: $0.end.timeIntervalSinceReferenceDate) })
        var sessions: [SleepSession] = []
        var group: [AsleepInterval] = []

        func flush() {
            guard let first = group.first, let last = group.last else { return }
            let asleepSpans = group.map { Span(start: $0.start.timeIntervalSinceReferenceDate, end: $0.end.timeIntervalSinceReferenceDate) }
            let grid = minuteGrid(asleep: asleepSpans, awake: awake, config: config)
            var sources: [SleepSampleSource] = []
            for source in group.flatMap(\.sources) where !sources.contains(source) { sources.append(source) }
            sessions.append(SleepSession(start: first.start, end: last.end, asleepMinutes: grid.asleep,
                                         wakeUps: grid.wakeUps, wakeUpMinutes: grid.awake, sources: sources))
            group.removeAll()
        }

        for interval in asleep {
            if let last = group.last, interval.start.timeIntervalSince(last.end) > config.maxGapWithinSession { flush() }
            group.append(interval)
        }
        flush()
        return sessions
    }

    /// Labels every clock minute from the first to the last asleep instant. `asleep` is sorted and
    /// non-overlapping; `awake` likewise (it may overlap `asleep`: another source's sleep wins).
    private static func minuteGrid(asleep: [Span], awake: [Span], config: SleepScoreConfig)
        -> (asleep: Int, awake: Int, wakeUps: Int) {
        guard let first = asleep.first, let last = asleep.last else { return (0, 0, 0) }
        let minute = 60.0
        // Awake time inside the session that no asleep sample covers.
        let awakeOnly = subtract(asleep, from: clip(awake, to: Span(start: first.start, end: last.end)))

        var asleepMinutes = 0, awakeMinutes = 0, wakeUps = 0
        var previousAwakeMinute: Int?
        var asleepCursor = 0, awakeCursor = 0
        let firstMinute = Int((first.start / minute).rounded(.down))
        let lastMinute = Int((last.end / minute).rounded(.up))
        for index in firstMinute..<lastMinute {
            let bucket = Span(start: Double(index) * minute, end: Double(index + 1) * minute)
            let asleepCover = coverage(asleep, in: bucket, cursor: &asleepCursor)
            let awakeCover = coverage(awakeOnly, in: bucket, cursor: &awakeCursor)
            guard asleepCover > 0 || awakeCover > 0 else { continue } // a gap: neither
            let isAsleep = asleepCover > awakeCover || (asleepCover == awakeCover && config.tiedMinuteIsAsleep)
            if isAsleep {
                asleepMinutes += 1
            } else {
                awakeMinutes += 1
                if previousAwakeMinute != index - 1 { wakeUps += 1 }
                previousAwakeMinute = index
            }
        }
        return (asleepMinutes, awakeMinutes, wakeUps)
    }

    // MARK: Intervals (seconds since the reference date, so minutes line up with the clock)

    private struct Span {
        var start: TimeInterval
        var end: TimeInterval
    }

    /// Seconds of `spans` (sorted, non-overlapping) inside `bucket`. `cursor` skips spans that end
    /// before the bucket; buckets must be visited in time order.
    private static func coverage(_ spans: [Span], in bucket: Span, cursor: inout Int) -> TimeInterval {
        while cursor < spans.count, spans[cursor].end <= bucket.start { cursor += 1 }
        var total: TimeInterval = 0
        var index = cursor
        while index < spans.count, spans[index].start < bucket.end {
            total += max(0, min(spans[index].end, bucket.end) - max(spans[index].start, bucket.start))
            index += 1
        }
        return total
    }

    private static func union(_ spans: [Span]) -> [Span] {
        var merged: [Span] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func clip(_ spans: [Span], to range: Span) -> [Span] {
        spans.compactMap { span in
            let clipped = Span(start: max(span.start, range.start), end: min(span.end, range.end))
            return clipped.end > clipped.start ? clipped : nil
        }
    }

    /// `spans` minus `holes` (both sorted, non-overlapping).
    private static func subtract(_ holes: [Span], from spans: [Span]) -> [Span] {
        var result: [Span] = []
        var holeIndex = 0
        for span in spans {
            var start = span.start
            while holeIndex < holes.count, holes[holeIndex].end <= start { holeIndex += 1 }
            var index = holeIndex
            while index < holes.count, holes[index].start < span.end {
                if holes[index].start > start { result.append(Span(start: start, end: holes[index].start)) }
                start = max(start, holes[index].end)
                index += 1
            }
            if span.end > start { result.append(Span(start: start, end: span.end)) }
        }
        return result
    }

    private struct AsleepInterval {
        var start: Date
        var end: Date
        var sources: [SleepSampleSource]
    }

    /// Sorted, non-overlapping union of all asleep samples. Touching intervals are merged, so
    /// back-to-back stages (core → deep → REM) form one stretch.
    private static func mergedAsleepIntervals(_ samples: [SleepSample]) -> [AsleepInterval] {
        let sorted = samples
            .filter { $0.stage.isAsleep && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [AsleepInterval] = []
        for sample in sorted {
            if let last = merged.last, sample.start <= last.end {
                merged[merged.count - 1].end = max(last.end, sample.end)
                if !last.sources.contains(sample.source) { merged[merged.count - 1].sources.append(sample.source) }
            } else {
                merged.append(AsleepInterval(start: sample.start, end: sample.end, sources: [sample.source]))
            }
        }
        return merged
    }
}
