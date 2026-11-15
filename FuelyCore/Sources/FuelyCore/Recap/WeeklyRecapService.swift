import Foundation

/// Loads one week of history. `WeekHistoryLoader` is the real one; tests use a fake.
public protocol WeekHistoryLoading: Sendable {
    /// The week containing `date`, and why HealthKit couldn't be read (nil when it was, or when
    /// there is no HealthKit client).
    func load(weekContaining date: Date, now: Date) async throws -> (week: WeekHistory, issue: HealthSyncIssue?)
}

extension WeekHistoryLoader: WeekHistoryLoading {}

/// The weekly recap for the app (DECISIONS §11): makes and saves the missing recaps, says which
/// one to pop up, and finds a saved one for the Week view.
public struct WeeklyRecapService: Sendable {
    public let store: FuelyStore
    public let loader: any WeekHistoryLoading
    public let calendar: Calendar
    public let locale: Locale
    public let config: WeeklyRecapConfig

    public init(store: FuelyStore, loader: any WeekHistoryLoading, calendar: Calendar = .current,
                locale: Locale = .autoupdatingCurrent, config: WeeklyRecapConfig = .default) {
        self.store = store
        self.loader = loader
        self.calendar = calendar
        self.locale = locale
        self.config = config
    }

    /// Call on every open, after the Health refresh (WR7). Makes a recap for each finished week
    /// that has none (WR8, oldest first, with the goals in force now) and returns the one to pop up:
    /// the newest finished week's, if it has not been shown. Call `markShown` once it is on screen.
    ///
    /// A week HealthKit couldn't be read for (e.g. phone locked) is skipped, not frozen with
    /// missing data; it is made on a later open. Nothing happens before onboarding is finished.
    public func refresh(now: Date) async throws -> WeeklyRecap? {
        guard let startDate = try resolveStartDate(now: now) else { return nil }
        let plan = WeeklyRecapPlanner.plan(startDate: startDate, archive: try store.weeklyRecaps(), now: now,
                                           calendar: calendar, config: config)
        for week in plan.weeksToGenerate {
            let monday = week.start(calendar: calendar)
            let (history, issue) = try await loader.load(weekContaining: monday.addingTimeInterval(12 * 3600), now: now)
            guard issue == nil else { continue }
            let recap = WeeklyRecap.make(from: history, createdAt: now, calendar: calendar, locale: locale,
                                         config: config)
            try store.updateWeeklyRecaps { $0.save(recap, keeping: config.keptRecaps) }
        }
        guard let week = plan.weekToPresent else { return nil }
        return try store.weeklyRecaps().recap(for: week)
    }

    /// Records that this recap popped up, so it never does again (WR7).
    public func markShown(_ recap: WeeklyRecap) throws {
        try store.updateWeeklyRecaps { $0.markShown(recap.week) }
    }

    /// The saved recap of the week containing `date`, for the Week view's button (WR9).
    public func recap(forWeekContaining date: Date) throws -> WeeklyRecap? {
        try store.weeklyRecaps().recap(for: RecapWeek(containing: date, calendar: calendar))
    }

    /// The start date (WR10), saved on first use so it never moves: the onboarding date, else the
    /// day of the earliest Fuely water entry, else `now`. nil until onboarding is finished.
    @discardableResult
    public func resolveStartDate(now: Date) throws -> Date? {
        let settings = try store.settings()
        guard settings.hasCompletedOnboarding else { return nil }
        if let stored = settings.onboardingCompletedAt { return stored }
        let derived = WeeklyRecapStart.startDate(settings: settings, waterLog: try store.waterLog(),
                                                 calendar: calendar) ?? now
        return try store.updateSettings { settings in
            if settings.onboardingCompletedAt == nil { settings.onboardingCompletedAt = derived }
            return settings.onboardingCompletedAt
        }
    }
}
