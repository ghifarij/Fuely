import Foundation

/// How the water goal went over one finished week (DECISIONS WR4): days at the goal out of 7.
public struct WaterWeekJudgement: Sendable, Hashable {
    public enum Tier: String, Sendable, Hashable, CaseIterable {
        /// 7 of 7.
        case perfect
        /// 5–6 days.
        case strong
        /// 3–4 days.
        case mixed
        /// 0–2 days.
        case low
    }

    public let goalML: Int
    /// Each day's total (every source), Monday first, always 7.
    public let dayTotalsML: [Int]
    /// Days at or above the goal, 0 = Monday … 6 = Sunday.
    public let reachedDays: [Int]
    /// Days below the goal.
    public let slippedDays: [Int]
    /// The day with the highest total (the earliest on a tie); nil when nothing was logged.
    public let bestDay: Int?
    public let tier: Tier

    public init(goalML: Int, dayTotalsML: [Int], config: WeeklyRecapConfig = .default) {
        let totals = (0..<7).map { $0 < dayTotalsML.count ? max(dayTotalsML[$0], 0) : 0 }
        self.goalML = goalML
        self.dayTotalsML = totals
        reachedDays = totals.indices.filter { totals[$0] >= goalML }
        slippedDays = totals.indices.filter { totals[$0] < goalML }
        let best = totals.max() ?? 0
        bestDay = best > 0 ? totals.firstIndex(of: best) : nil
        let reached = reachedDays.count
        tier = if reached >= config.waterPerfectDays { .perfect }
            else if reached >= config.waterStrongDays { .strong }
            else if reached >= config.waterMixedDays { .mixed }
            else { .low }
    }

    public var daysReached: Int { reachedDays.count }
    public var bestDayML: Int { bestDay.map { dayTotalsML[$0] } ?? 0 }
    /// Any water at all this week.
    public var hasData: Bool { bestDay != nil }
    /// WR4a: at least 5 of 7 days.
    public var isStrong: Bool { tier == .perfect || tier == .strong }
    /// Ring fill: days at the goal / 7.
    public var fraction: Double { Double(daysReached) / 7 }
}

/// How sleep went over one finished week (DECISIONS WR4): the average score and the nights at or
/// above the goal, over tracked nights only (S7, S7b).
public struct SleepWeekJudgement: Sendable, Hashable {
    public enum State: String, Sendable, Hashable, CaseIterable {
        /// Enough tracked nights for a verdict.
        case judged
        /// Fewer than 3 tracked nights: no verdict, Watch hint.
        case tooFewNights
        /// No tracked night at all: "No sleep tracked".
        case noneTracked
    }

    public enum Tier: String, Sendable, Hashable, CaseIterable {
        /// Average at or above the goal.
        case strong
        /// Average up to `WeeklyRecapConfig.sleepMidMargin` points below the goal.
        case mid
        case low
    }

    public let goal: Int
    public let trackedNights: Int
    /// Rounded average of the tracked nights; nil without any.
    public let average: Int?
    public let nightsAtGoal: Int
    public let state: State
    /// nil when there is no verdict.
    public let tier: Tier?

    /// - `scores`: the tracked nights' scores (nights without data left out).
    public init(goal: Int, scores: [Int], config: WeeklyRecapConfig = .default) {
        self.goal = goal
        trackedNights = scores.count
        nightsAtGoal = scores.filter { $0 >= goal }.count
        let mean = scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        average = mean
        if let mean, scores.count >= max(config.minimumSleepNights, 1) {
            state = .judged
            tier = if mean >= goal { .strong } else if mean >= goal - config.sleepMidMargin { .mid } else { .low }
        } else {
            state = scores.isEmpty ? .noneTracked : .tooFewNights
            tier = nil
        }
    }

    public var isJudged: Bool { state == .judged }
    /// WR4a: average at or above the goal over at least 3 tracked nights.
    public var isStrong: Bool { tier == .strong }
    /// Ring fill: average / goal, at most 1; 0 without a verdict.
    public var fraction: Double {
        guard isJudged, let average, goal > 0 else { return 0 }
        return min(Double(average) / Double(goal), 1)
    }
}

/// How the workout goal went over one finished week (DECISIONS WR4, K2, K3).
public struct WorkoutWeekJudgement: Sendable, Hashable {
    public enum Tier: String, Sendable, Hashable, CaseIterable {
        /// More workout days than the goal.
        case beyond
        /// Exactly the goal.
        case met
        /// One day short (with at least one workout day).
        case oneShort
        case missed
    }

    /// Workout days wanted per week, and the minutes that make a day count.
    public let goalDays: Int
    public let minMinutesPerDay: Int
    /// Days that counted (K3).
    public let workoutDays: Int
    /// Any workout at all this week, also one too short to count.
    public let hasData: Bool
    public let tier: Tier

    public init(goal: WorkoutGoal, workoutDays: Int, hasData: Bool? = nil) {
        let days = min(max(workoutDays, 0), 7)
        goalDays = goal.daysPerWeek
        minMinutesPerDay = goal.minMinutesPerDay
        self.workoutDays = days
        self.hasData = days > 0 || (hasData ?? false)
        tier = if days > goal.daysPerWeek { .beyond }
            else if days == goal.daysPerWeek { .met }
            else if days > 0, days == goal.daysPerWeek - 1 { .oneShort }
            else { .missed }
    }

    public var extraDays: Int { max(workoutDays - goalDays, 0) }
    public var daysShort: Int { max(goalDays - workoutDays, 0) }
    /// WR4a: at least the weekly goal.
    public var isStrong: Bool { tier == .beyond || tier == .met }
    /// Ring fill: workout days / goal; above 1 with extra days.
    public var fraction: Double { goalDays > 0 ? Double(workoutDays) / Double(goalDays) : 0 }
}

/// One finished Monday–Sunday week, judged (DECISIONS WR4, WR4a, WR6).
public struct WeekJudgement: Sendable, Hashable {
    public let week: RecapWeek
    public let water: WaterWeekJudgement
    public let sleep: SleepWeekJudgement
    public let workouts: WorkoutWeekJudgement

    public init(week: RecapWeek, water: WaterWeekJudgement, sleep: SleepWeekJudgement,
                workouts: WorkoutWeekJudgement) {
        self.week = week
        self.water = water
        self.sleep = sleep
        self.workouts = workouts
    }

    /// Judges a finished week with the goals it was built with (the ones in force now, WR8).
    public init(_ history: WeekHistory, calendar: Calendar, config: WeeklyRecapConfig = .default) {
        let days = history.days
        self.init(week: RecapWeek(containing: history.start, calendar: calendar),
                  water: WaterWeekJudgement(goalML: days.first?.waterGoalML ?? 0,
                                            dayTotalsML: days.map(\.waterTotalML), config: config),
                  sleep: SleepWeekJudgement(goal: days.first?.sleepGoal ?? 0,
                                            scores: days.compactMap(\.sleepScore), config: config),
                  workouts: WorkoutWeekJudgement(goal: history.workoutWeek.goal,
                                                 workoutDays: days.filter(\.isWorkoutDay).count,
                                                 hasData: days.contains { $0.workoutMinutes > 0 }))
    }

    /// WR4a: false when no water was logged, no night tracked and no workout found.
    public var hasEnoughData: Bool {
        water.hasData || sleep.trackedNights > 0 || workouts.hasData
    }

    /// The rings with a verdict: water and workouts always, sleep with enough tracked nights.
    public var judgedRings: [WeeklyRecap.Ring] {
        sleep.isJudged ? [.water, .sleep, .workouts] : [.water, .workouts]
    }

    public func isStrong(_ ring: WeeklyRecap.Ring) -> Bool {
        switch ring {
        case .water: water.isStrong
        case .sleep: sleep.isStrong
        case .workouts: workouts.isStrong
        }
    }

    /// Not strong, but close: water on 3–4 days, sleep just under the goal, workouts one day short.
    public func isMidTier(_ ring: WeeklyRecap.Ring) -> Bool {
        switch ring {
        case .water: water.tier == .mixed
        case .sleep: sleep.tier == .mid
        case .workouts: workouts.tier == .oneShort
        }
    }

    public var strongRings: [WeeklyRecap.Ring] { judgedRings.filter(isStrong) }
    /// Judged rings that are not strong.
    public var weakRings: [WeeklyRecap.Ring] { judgedRings.filter { !isStrong($0) } }

    /// The one emoji of the week (WR6).
    public var mood: WeeklyRecap.Mood {
        guard hasEnoughData else { return .notEnoughData }
        let judged = judgedRings.count, strong = strongRings.count
        if strong == judged { return .allStrong }
        if strong == 2 { return .twoStrong }
        if strong == 1 { return .oneStrong }
        return judgedRings.contains(where: isMidTier) ? .mixed : .low
    }

    /// The ring the suggestion is about (WR5); nil when every judged ring is strong. Low tiers come
    /// before mid tiers, then the emptier ring, then water, workouts, sleep.
    public var weakestRing: WeeklyRecap.Ring? {
        let order: [WeeklyRecap.Ring] = [.water, .workouts, .sleep]
        return weakRings.min { a, b in
            let ka = (isMidTier(a) ? 1 : 0, fraction(a), order.firstIndex(of: a) ?? 0)
            let kb = (isMidTier(b) ? 1 : 0, fraction(b), order.firstIndex(of: b) ?? 0)
            return ka < kb
        }
    }

    /// The ring's fill (see each judgement).
    public func fraction(_ ring: WeeklyRecap.Ring) -> Double {
        switch ring {
        case .water: water.fraction
        case .sleep: sleep.fraction
        case .workouts: workouts.fraction
        }
    }
}
