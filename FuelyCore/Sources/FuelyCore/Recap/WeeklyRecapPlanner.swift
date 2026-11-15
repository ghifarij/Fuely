import Foundation

/// What to do about recaps on this open of the app (DECISIONS WR7, WR8).
public struct WeeklyRecapPlan: Sendable, Hashable {
    /// Finished weeks that still need a recap, oldest first. Made quietly.
    public var weeksToGenerate: [RecapWeek]
    /// The newest finished week when its recap has not popped up yet; nil = show nothing.
    public var weekToPresent: RecapWeek?

    public init(weeksToGenerate: [RecapWeek] = [], weekToPresent: RecapWeek? = nil) {
        self.weeksToGenerate = weeksToGenerate
        self.weekToPresent = weekToPresent
    }
}

/// Decides which weeks get a recap and which one pops up (DECISIONS WR7, WR8, WR10). Pure.
public enum WeeklyRecapPlanner {
    /// - `startDate`: when the user started (WR10); nil = not started, nothing to do.
    ///
    /// Only finished Monday–Sunday weeks whose Monday is on or after the start date's day count
    /// (no partial first week), and only the newest `config.keptRecaps` of them. The week before
    /// the current one pops up, once, whatever the day of the first open.
    public static func plan(startDate: Date?, archive: WeeklyRecapArchive, now: Date, calendar: Calendar,
                            config: WeeklyRecapConfig = .default) -> WeeklyRecapPlan {
        guard let startDate else { return WeeklyRecapPlan() }
        let eligible = eligibleWeeks(startDate: startDate, now: now, calendar: calendar, config: config)
        let saved = archive.weeks
        let present = eligible.last.flatMap { archive.hasBeenShown($0) ? nil : $0 }
        return WeeklyRecapPlan(weeksToGenerate: eligible.filter { !saved.contains($0) }, weekToPresent: present)
    }

    /// The finished weeks that may have a recap, oldest first.
    public static func eligibleWeeks(startDate: Date, now: Date, calendar: Calendar,
                                     config: WeeklyRecapConfig = .default) -> [RecapWeek] {
        let startDay = calendar.startOfDay(for: startDate)
        let current = RecapWeek(containing: now, calendar: calendar)
        var weeks: [RecapWeek] = []
        for back in stride(from: 1, through: max(config.keptRecaps, 0), by: 1) {
            let week = current.advanced(by: -back, calendar: calendar)
            guard week.start(calendar: calendar) >= startDay else { break }
            weeks.append(week)
        }
        return weeks.reversed()
    }
}

/// When the user started with Fuely (DECISIONS WR10).
public enum WeeklyRecapStart {
    /// The saved onboarding date; for an install that finished onboarding before the date was
    /// saved, the day of the earliest Fuely water entry still in the store; else nil.
    public static func startDate(settings: FuelySettings, waterLog: WaterLog, calendar: Calendar) -> Date? {
        if let stored = settings.onboardingCompletedAt { return stored }
        let earliest = waterLog.entries.lazy.filter { $0.source == .fuely && $0.date > .distantPast }
            .map(\.date).min()
        return earliest.map { calendar.startOfDay(for: $0) }
    }
}
