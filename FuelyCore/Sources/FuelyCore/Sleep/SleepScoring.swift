import Foundation

/// Every constant of Fuely's sleep score in one place (DECISIONS S8). The scoring constants are a
/// model fitted to Apple's published Sleep Scores; the measurement rules follow the inputs Apple
/// shows on its Sleep Score screens (asleep time, bedtime deviation, wake-ups).
public struct SleepScoreConfig: Sendable, Hashable {
    // MARK: Duration (50 pts)

    /// The kink of the duration curve, in minutes asleep: 7 h. Apple likely scores against the
    /// length of the Health sleep schedule; Fuely can't read that schedule (no public API), so it is
    /// a constant here.
    public var durationReferenceMinutes = 420.0
    /// Raw points at exactly `durationReferenceMinutes`.
    public var durationPointsAtReference = 44.92
    /// Raw points gained per minute above the reference (50 at ~8 h 05).
    public var durationPointsPerMinuteAbove = 0.078
    /// Raw points lost per minute below the reference (0 at ~1 h 40).
    public var durationPointsPerMinuteBelow = 0.14

    // MARK: Bedtime consistency (30 pts)

    /// Falling asleep up to this many minutes later than average is free.
    public var bedtimeLateGraceMinutes = 15.0
    /// Points lost per minute later than average beyond the grace (0 at 165 min late).
    public var bedtimeLatePointsPerMinute = 0.2
    /// Falling asleep up to this many minutes earlier than average is free (only the ratio with
    /// the slope is pinned down by the fit).
    public var bedtimeEarlyGraceMinutes = 60.0
    /// Points lost per minute earlier than average beyond the grace.
    public var bedtimeEarlyPointsPerMinute = 0.1

    // MARK: Interruptions (20 pts)

    /// Wake-ups up to this count are free.
    public var freeWakeUps = 3.6
    /// Points lost per wake-up beyond `freeWakeUps`.
    public var pointsPerWakeUp = 5.0 / 3.0
    /// Each wake-up may last this many minutes for free.
    public var freeMinutesPerWakeUp = 5.0
    /// Points lost per wake-up minute beyond `freeMinutesPerWakeUp × wake-ups`.
    public var pointsPerExtraWakeUpMinute = 0.2

    // MARK: Measurement

    /// The bedtime average covers the sleep days this many days before the scored one (Apple: "the
    /// last 13 nights"); days without a real night (no data, or nap-only) are skipped, not replaced
    /// by older ones.
    public var bedtimeHistoryNights = 13
    /// A sleep day whose main sleep has less asleep time than this is "nap-only": it gets no score
    /// ("—", like a day without data, DECISIONS S7b) and its onset is not part of other days'
    /// bedtime average (Apple's averages leave nap-only days out). 3 h sits well above a typical
    /// nap and below a short night.
    public var minMainSleepForBedtimeHistory: TimeInterval = 3 * 3600
    /// With fewer history nights than this there is no average: full bedtime points (Apple shows
    /// "Fell asleep at …"). Hypothesis: one earlier night is enough.
    public var bedtimeMinHistoryNights = 1
    /// Apple scores whole clock minutes: each minute a session touches is asleep or awake, whichever
    /// covers more of it (gaps without samples are neither). This decides a minute split exactly in
    /// half; asleep is a guess (no observed case).
    public var tiedMinuteIsAsleep = true
    /// Asleep stretches more than this apart are separate sessions (e.g. the night and an afternoon
    /// nap). Gaps inside a session are neither asleep nor a wake-up.
    public var maxGapWithinSession: TimeInterval = 2 * 3600
    /// Sleep day D covers sessions that end in [D−1 at this time, D at this time). 18:00 puts a
    /// night ending in the morning and a nap that same afternoon on the same day.
    public var sleepDayStart = TimeOfDay(hour: 18)

    public init() {}

    public static let `default` = SleepScoreConfig()
}

/// What Fuely measured for one sleep day: the inputs of the score.
public struct SleepNight: Sendable, Hashable {
    /// Start of the sleep day (the day the night ends on).
    public let day: Date
    /// Every session of the sleep day, in order (the night plus any naps).
    public let sessions: [SleepSession]
    /// The longest session: its start is the onset.
    public let mainSleep: SleepSession
    /// Asleep clock minutes of all sessions together (naps included).
    public let asleepMinutes: Int
    /// Wake-ups inside the main sleep only (never before its first or after its last asleep sample;
    /// naps' wake-ups don't count).
    public let wakeUps: Int
    public let wakeUpMinutes: Int
    /// Clock minute of the onset, counted from 12:00 (22:00 = 600, 00:30 = 750).
    public let onsetMinutesAfterNoon: Int
    /// Mean onset over the history nights, or nil with too little history.
    public let averageOnsetMinutesAfterNoon: Double?
    /// Sleep days with data among the `bedtimeHistoryNights` before this one.
    public let historyNights: Int
    /// Onset minus average in whole minutes (+ = later), or nil without an average.
    public let bedtimeDeviationMinutes: Int?
    /// Sources of the asleep samples, in order of first appearance.
    public let sources: [SleepSampleSource]
    /// The main sleep is shorter than `minMainSleepForBedtimeHistory`: no real night that day. Not
    /// scored ("—", S7b) and left out of later days' bedtime average.
    public let isNapOnly: Bool

    /// When sleep began (start of the main sleep's first asleep sample).
    public var onset: Date { mainSleep.start }
    /// More than one session that day (e.g. an afternoon nap).
    public var includesNap: Bool { sessions.count > 1 }
}

/// A sleep day's score: Duration 50 + Bedtime 30 + Interruptions 20 (DECISIONS S2, S8).
public struct SleepScore: Sendable, Hashable {
    /// Sum of the three components, 0–100.
    public let total: Int
    public let durationPoints: Int
    public let bedtimePoints: Int
    public let interruptionPoints: Int
    public let night: SleepNight

    public func meets(goal: Int) -> Bool { total >= goal }
}

public enum SleepScoring {
    // MARK: Scores

    /// The score of the sleep day containing `day` (the night ending that morning plus naps that
    /// day), or nil ("—") when there is no asleep sample at all (DECISIONS S7) or only naps, no real
    /// night (S7b). Pass samples from at least `bedtimeHistoryNights` + 1 days before for the
    /// bedtime average.
    public static func score(forNightEndingOn day: Date, samples: [SleepSample], calendar: Calendar,
                             config: SleepScoreConfig = .default) -> SleepScore? {
        let sessions = sessionsBySleepDay(samples, calendar: calendar, config: config)
        return score(day: calendar.startOfDay(for: day), sessions: sessions, calendar: calendar, config: config)
    }

    /// Scores for many sleep days at once (week history), keyed by start of day.
    /// Days without data and nap-only days are left out.
    public static func scores(forSleepDays days: [Date], samples: [SleepSample], calendar: Calendar,
                              config: SleepScoreConfig = .default) -> [Date: SleepScore] {
        let sessions = sessionsBySleepDay(samples, calendar: calendar, config: config)
        var result: [Date: SleepScore] = [:]
        for day in days {
            let start = calendar.startOfDay(for: day)
            if let score = score(day: start, sessions: sessions, calendar: calendar, config: config) {
                result[start] = score
            }
        }
        return result
    }

    // MARK: Components (whole-minute inputs, round half up, then clamp)

    /// 0–50 from minutes asleep: linear on both sides of a kink at `durationReferenceMinutes`.
    public static func durationPoints(asleepMinutes: Int, config: SleepScoreConfig = .default) -> Int {
        let m = Double(asleepMinutes)
        let reference = config.durationReferenceMinutes
        let raw = m >= reference
            ? config.durationPointsAtReference + config.durationPointsPerMinuteAbove * (m - reference)
            : config.durationPointsAtReference - config.durationPointsPerMinuteBelow * (reference - m)
        return clamp(roundHalfUp(raw), 0, 50)
    }

    /// 0–30 from the onset's deviation from the average (+ later, − earlier); nil (no average) = 30.
    public static func bedtimePoints(deviationMinutes: Int?, config: SleepScoreConfig = .default) -> Int {
        guard let deviationMinutes else { return 30 }
        let deviation = Double(deviationMinutes)
        let lost = deviation >= 0
            ? config.bedtimeLatePointsPerMinute * max(0, deviation - config.bedtimeLateGraceMinutes)
            : config.bedtimeEarlyPointsPerMinute * max(0, -deviation - config.bedtimeEarlyGraceMinutes)
        return clamp(roundHalfUp(30 - lost), 0, 30)
    }

    /// 0–20 from the wake-up count and their total minutes.
    public static func interruptionPoints(wakeUps: Int, minutes: Int, config: SleepScoreConfig = .default) -> Int {
        let n = Double(wakeUps)
        let lost = config.pointsPerWakeUp * max(0, n - config.freeWakeUps)
            + config.pointsPerExtraWakeUpMinute * max(0, Double(minutes) - config.freeMinutesPerWakeUp * n)
        return clamp(roundHalfUp(20 - lost), 0, 20)
    }

    /// 47.5 → 48, 2.5 → 3 (not banker's rounding).
    static func roundHalfUp(_ value: Double) -> Int {
        Int((value + 0.5).rounded(.down))
    }

    // MARK: Measurement

    private static func score(day: Date, sessions: [Date: [SleepSession]], calendar: Calendar,
                              config: SleepScoreConfig) -> SleepScore? {
        guard let night = night(day: day, sessions: sessions, calendar: calendar, config: config),
              !night.isNapOnly else { return nil }
        let duration = durationPoints(asleepMinutes: night.asleepMinutes, config: config)
        let bedtime = bedtimePoints(deviationMinutes: night.bedtimeDeviationMinutes, config: config)
        let interruptions = interruptionPoints(wakeUps: night.wakeUps, minutes: night.wakeUpMinutes, config: config)
        return SleepScore(total: duration + bedtime + interruptions, durationPoints: duration,
                          bedtimePoints: bedtime, interruptionPoints: interruptions, night: night)
    }

    private static func night(day: Date, sessions: [Date: [SleepSession]], calendar: Calendar,
                              config: SleepScoreConfig) -> SleepNight? {
        guard let daySessions = sessions[day], let main = mainSleep(daySessions) else { return nil }

        let historyOnsets: [Int] = (0..<max(config.bedtimeHistoryNights, 0)).compactMap { index in
            guard let earlier = calendar.date(byAdding: .day, value: -(index + 1), to: day),
                  let earlierMain = sessions[calendar.startOfDay(for: earlier)].flatMap(mainSleep),
                  !isNapOnly(earlierMain, config) else { return nil }
            return minutesAfterNoon(earlierMain.start, calendar)
        }
        let onset = minutesAfterNoon(main.start, calendar)
        let average: Double? = historyOnsets.count >= max(config.bedtimeMinHistoryNights, 1)
            ? Double(historyOnsets.reduce(0, +)) / Double(historyOnsets.count)
            : nil
        let deviation = average.map { Int((Double(onset) - $0).rounded(.toNearestOrAwayFromZero)) }

        let asleep = daySessions.reduce(0) { $0 + $1.asleepMinutes }
        var sources: [SleepSampleSource] = []
        for source in daySessions.flatMap(\.sources) where !sources.contains(source) { sources.append(source) }

        return SleepNight(day: day, sessions: daySessions, mainSleep: main,
                          asleepMinutes: asleep, wakeUps: main.wakeUps, wakeUpMinutes: main.wakeUpMinutes,
                          onsetMinutesAfterNoon: onset, averageOnsetMinutesAfterNoon: average,
                          historyNights: historyOnsets.count, bedtimeDeviationMinutes: deviation, sources: sources,
                          isNapOnly: isNapOnly(main, config))
    }

    /// Sessions grouped by sleep day (start of day), each list in time order.
    private static func sessionsBySleepDay(_ samples: [SleepSample], calendar: Calendar,
                                           config: SleepScoreConfig) -> [Date: [SleepSession]] {
        let sessions = SleepSession.sessions(from: samples, config: config)
        return Dictionary(grouping: sessions) { sleepDay(ending: $0.end, calendar: calendar, config: config) }
    }

    /// The sleep day a session belongs to: ending before `sleepDayStart` → that day, else the next.
    static func sleepDay(ending end: Date, calendar: Calendar, config: SleepScoreConfig) -> Date {
        let dayStart = calendar.startOfDay(for: end)
        guard end >= config.sleepDayStart.date(on: dayStart, calendar: calendar) else { return dayStart }
        return calendar.date(byAdding: .day, value: 1, to: dayStart).map(calendar.startOfDay) ?? dayStart
    }

    /// A main sleep too short to be a night (see `minMainSleepForBedtimeHistory`).
    private static func isNapOnly(_ main: SleepSession, _ config: SleepScoreConfig) -> Bool {
        TimeInterval(main.asleepMinutes) * 60 < config.minMainSleepForBedtimeHistory
    }

    /// The longest session (earliest on a tie).
    private static func mainSleep(_ sessions: [SleepSession]) -> SleepSession? {
        sessions.reduce(nil) { best, session in
            guard let best else { return session }
            return session.asleepMinutes > best.asleepMinutes ? session : best
        }
    }

    /// Wall-clock minute after 12:00 (seconds dropped), so bedtimes around midnight compare
    /// linearly (22:00 = 600, 00:30 = 750).
    static func minutesAfterNoon(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return ((c.hour ?? 0) * 60 + (c.minute ?? 0) - 720 + 1440) % 1440
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }
}
