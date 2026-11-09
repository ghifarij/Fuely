import Foundation

/// The last values read from HealthKit, cached in the App Group for the widget, which cannot
/// read HealthKit itself (DECISIONS W4). Fuely's own water is not in here: it comes from `WaterLog`,
/// so a widget (+) shows up immediately.
public struct HealthSnapshot: Codable, Sendable, Hashable {
    /// When HealthKit was read. The values below describe that calendar day / week.
    public var refreshedAt: Date
    /// Water logged by other apps on the day of `refreshedAt`.
    public var externalWaterML: Int
    /// Fuely's score for the night ending on the day of `refreshedAt`; nil = no data ("—", S7).
    public var sleepScore: Int?
    /// Workouts of the Monday–Sunday week containing `refreshedAt`.
    public var workouts: [WorkoutSample]

    public init(refreshedAt: Date, externalWaterML: Int, sleepScore: Int?, workouts: [WorkoutSample]) {
        self.refreshedAt = refreshedAt
        self.externalWaterML = externalWaterML
        self.sleepScore = sleepScore
        self.workouts = workouts
    }

    private enum CodingKeys: String, CodingKey {
        case refreshedAt, externalWaterML, sleepScore, workouts
    }

    /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(refreshedAt: try c.decodeIfPresent(Date.self, forKey: .refreshedAt) ?? .distantPast,
                  externalWaterML: try c.decodeIfPresent(Int.self, forKey: .externalWaterML) ?? 0,
                  sleepScore: try c.decodeIfPresent(Int.self, forKey: .sleepScore),
                  workouts: try c.decodeIfPresent([WorkoutSample].self, forKey: .workouts) ?? [])
    }
}

/// Everything the Today screen and the widgets show, combined from settings, the local water log
/// and the HealthKit snapshot. Values from a stale snapshot roll over: other apps' water and the
/// sleep score count only on the snapshot's own day, workouts only in its own week.
public struct TodaySummary: Sendable, Hashable {
    public let date: Date
    /// Total (Fuely + other apps) against the goal and the drinking-window pace (W3, W8).
    public let water: WaterProgress
    public let fuelyWaterML: Int
    public let externalWaterML: Int
    /// nil = no data for last night ("—", S7).
    public let sleepScore: Int?
    public let sleepGoal: Int
    public let workoutWeek: WorkoutWeek
    /// HealthKit changes still waiting to sync.
    public let pendingSyncCount: Int
    /// Why the last push failed a job (e.g. `.notAuthorized` = "Health access off"); nil if fine.
    public let syncIssue: HealthSyncIssue?
    /// When HealthKit was last read; nil if never.
    public let healthRefreshedAt: Date?

    /// nil when there is no score (the day doesn't count toward the sleep goal, S7).
    public var sleepGoalMet: Bool? { sleepScore.map { $0 >= sleepGoal } }

    public static func make(settings: FuelySettings, waterLog: WaterLog, snapshot: HealthSnapshot?,
                            now: Date, calendar: Calendar) -> TodaySummary {
        let fuely = waterLog.entries(onDayOf: now, calendar: calendar).reduce(0) { $0 + $1.amountML }
        let sameDay = snapshot.map { calendar.isDate($0.refreshedAt, inSameDayAs: now) } ?? false
        let external = sameDay ? max(snapshot?.externalWaterML ?? 0, 0) : 0
        let total = fuely + external
        return TodaySummary(
            date: now,
            water: WaterPace.progress(totalML: total, goalML: settings.waterGoalML,
                                      window: settings.drinkingWindow, at: now, calendar: calendar),
            fuelyWaterML: fuely,
            externalWaterML: external,
            sleepScore: sameDay ? snapshot?.sleepScore : nil,
            sleepGoal: settings.sleepGoalScore,
            workoutWeek: WorkoutAggregation.week(containing: now, samples: snapshot?.workouts ?? [],
                                                 goal: settings.workoutGoal, calendar: calendar),
            pendingSyncCount: waterLog.pending.count,
            syncIssue: waterLog.lastSyncIssue,
            healthRefreshedAt: snapshot?.refreshedAt
        )
    }
}
