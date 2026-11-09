import Foundation

/// One day in the week view (DECISIONS T3): water vs goal, the night's sleep score and workout
/// minutes, plus the drinks for the day detail (W7).
public struct HistoryDay: Sendable, Hashable, Identifiable {
    /// Start of the day.
    public let date: Date
    public var id: Date { date }
    public let isToday: Bool
    /// After today: nothing to show yet.
    public let isFuture: Bool
    /// Fuely's own drinks, newest first. Deletable.
    public let fuelyEntries: [WaterEntry]
    /// Other apps' drinks, newest first. Read-only (W7). Empty when only a total is known.
    public let externalEntries: [WaterEntry]
    /// Other apps' water this day (the sum of `externalEntries`, or the cached total).
    public let externalWaterML: Int
    public let waterGoalML: Int
    /// The score of the night that ended this day; nil = no data ("—", S7).
    public let sleepScore: Int?
    public let sleepGoal: Int
    /// Summed workout minutes (K3) and whether they reach the daily minimum.
    public let workoutMinutes: Double
    public let isWorkoutDay: Bool

    public var fuelyWaterML: Int { fuelyEntries.reduce(0) { $0 + $1.amountML } }
    public var waterTotalML: Int { fuelyWaterML + externalWaterML }
    /// total / goal; can exceed 1 (W3). 0 when the goal is 0.
    public var waterFraction: Double { waterGoalML > 0 ? Double(waterTotalML) / Double(waterGoalML) : 0 }
    public var isWaterGoalMet: Bool { waterTotalML >= waterGoalML }
    /// nil when there is no score: the night doesn't count toward the sleep goal (S7).
    public var sleepGoalMet: Bool? { sleepScore.map { $0 >= sleepGoal } }
}

/// The raw HealthKit data behind a week, read by `WeekHistoryLoader`.
public struct WeekHealthData: Sendable, Hashable {
    /// Water samples of every source that started in the week.
    public var water: [WaterEntry]
    /// Sleep samples from before the week (bedtime history) through its end.
    public var sleep: [SleepSample]
    /// Workouts that started in the week.
    public var workouts: [WorkoutSample]

    public init(water: [WaterEntry], sleep: [SleepSample], workouts: [WorkoutSample]) {
        self.water = water
        self.sleep = sleep
        self.workouts = workouts
    }
}

/// A Monday–Sunday week (DECISIONS K2, T3) of water, sleep scores and workout days.
/// Past days use today's goals: Fuely doesn't keep a history of goal changes.
public struct WeekHistory: Sendable, Hashable {
    /// Monday 00:00.
    public let start: Date
    /// Monday through Sunday, always 7.
    public let days: [HistoryDay]
    public let workoutWeek: WorkoutWeek
    /// False when HealthKit couldn't be read: the week then shows Fuely's own water plus the cached
    /// snapshot (today's other-apps water and sleep score, this week's workouts).
    public let usesHealthData: Bool

    /// Days so far (today and earlier).
    public var elapsedDays: [HistoryDay] { days.filter { !$0.isFuture } }
    public var waterGoalDays: Int { elapsedDays.filter(\.isWaterGoalMet).count }
    /// Nights with a score (S7: nights without data are left out).
    public var scoredNights: [Int] { elapsedDays.compactMap(\.sleepScore) }
    public var averageSleepScore: Int? {
        let scores = scoredNights
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }
    public var isCurrentWeek: Bool { days.contains(where: \.isToday) }

    public func day(containing date: Date, calendar: Calendar) -> HistoryDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Builds the week containing `date`.
    /// - `health`: what HealthKit returned for the week, or nil when it couldn't be read.
    /// - Fuely's drinks are the local log plus Fuely samples found only in HealthKit (older than
    ///   the local retention or restored), minus deleted (tombstoned) ones. The local copy wins.
    public static func make(weekContaining date: Date, now: Date, settings: FuelySettings, waterLog: WaterLog,
                            health: WeekHealthData?, snapshot: HealthSnapshot?, calendar: Calendar,
                            sleepConfig: SleepScoreConfig = .default) -> WeekHistory {
        let monday = WorkoutAggregation.weekStart(containing: date, calendar: calendar)
        let dayStarts = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday) ?? monday }
        let today = calendar.startOfDay(for: now)

        var fuely = waterLog.entries
        if let health {
            let local = Set(fuely.map(\.id))
            fuely += health.water.filter {
                $0.source == .fuely && !local.contains($0.id) && !waterLog.isDeleted($0.id)
            }
        }
        let external = health?.water.filter { $0.source != .fuely } ?? []
        let workouts = health?.workouts ?? snapshot?.workouts ?? []
        let workoutWeek = WorkoutAggregation.week(containing: monday, samples: workouts,
                                                  goal: settings.workoutGoal, calendar: calendar)

        // Same scoring as Today, per past sleep day (DECISIONS S8).
        let sleepScores = health.map {
            SleepScoring.scores(forSleepDays: dayStarts.filter { $0 <= today }, samples: $0.sleep,
                                calendar: calendar, config: sleepConfig)
        } ?? [:]

        let days = dayStarts.map { day -> HistoryDay in
            let isFuture = day > today
            let dayFuely = fuely.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date > $1.date }
            let dayExternal = external.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date > $1.date }
            let externalML: Int
            let sleep: Int?
            if health != nil {
                externalML = dayExternal.reduce(0) { $0 + $1.amountML }
                sleep = isFuture ? nil : sleepScores[calendar.startOfDay(for: day)]?.total
            } else {
                let snapshotDay = snapshot.map { calendar.isDate($0.refreshedAt, inSameDayAs: day) } ?? false
                externalML = snapshotDay ? max(snapshot?.externalWaterML ?? 0, 0) : 0
                sleep = snapshotDay ? snapshot?.sleepScore : nil
            }
            let workoutDay = workoutWeek.day(containing: day, calendar: calendar)
            return HistoryDay(date: day, isToday: day == today, isFuture: isFuture,
                              fuelyEntries: dayFuely, externalEntries: dayExternal, externalWaterML: externalML,
                              waterGoalML: settings.waterGoalML, sleepScore: sleep, sleepGoal: settings.sleepGoalScore,
                              workoutMinutes: workoutDay?.minutes ?? 0, isWorkoutDay: workoutDay?.isWorkoutDay ?? false)
        }
        return WeekHistory(start: monday, days: days, workoutWeek: workoutWeek, usesHealthData: health != nil)
    }
}

/// Reads a week from the store and, when available, HealthKit (DECISIONS T3). HealthKit errors
/// (e.g. locked, no access) fall back to the stored data instead of failing.
public struct WeekHistoryLoader: Sendable {
    public let store: FuelyStore
    public let healthKit: (any HealthKitClient)?
    public let calendar: Calendar
    public let sleepConfig: SleepScoreConfig

    public init(store: FuelyStore, healthKit: (any HealthKitClient)?, calendar: Calendar = .current,
                sleepConfig: SleepScoreConfig = .default) {
        self.store = store
        self.healthKit = healthKit
        self.calendar = calendar
        self.sleepConfig = sleepConfig
    }

    /// The week containing `date`, and why HealthKit couldn't be read (nil when it was, or when
    /// there is no HealthKit client).
    public func load(weekContaining date: Date, now: Date) async throws -> (week: WeekHistory, issue: HealthSyncIssue?) {
        var health: WeekHealthData?
        var issue: HealthSyncIssue?
        if let healthKit {
            do {
                health = try await read(healthKit, weekContaining: date)
            } catch {
                issue = HealthSyncIssue(error)
            }
        }
        let week = WeekHistory.make(weekContaining: date, now: now, settings: try store.settings(),
                                    waterLog: try store.waterLog(), health: health,
                                    snapshot: try store.healthSnapshot(), calendar: calendar, sleepConfig: sleepConfig)
        return (week, issue)
    }

    private func read(_ healthKit: any HealthKitClient, weekContaining date: Date) async throws -> WeekHealthData {
        let monday = WorkoutAggregation.weekStart(containing: date, calendar: calendar)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let week = DateInterval(start: monday, end: max(nextMonday, monday))
        let historyDays = max(sleepConfig.bedtimeHistoryNights, 1) + 2
        let sleepStart = calendar.date(byAdding: .day, value: -historyDays, to: monday) ?? monday
        let sleepInterval = DateInterval(start: sleepStart, end: max(nextMonday, sleepStart))
        async let water = healthKit.waterEntries(in: week)
        async let sleep = healthKit.sleepSamples(in: sleepInterval)
        async let workouts = healthKit.workouts(in: week)
        let (w, s, k) = try await (water, sleep, workouts)
        return WeekHealthData(water: w, sleep: s, workouts: k)
    }
}
