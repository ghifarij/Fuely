import Foundation

/// The words on the Today screen, derived from a `TodaySummary` (DECISIONS T1, T2, S7, K2).
/// Kept out of the views so it can be tested and reused by the widgets.
public enum TodayCopy {
    /// The friendly, motivational line under the date (DECISIONS T2). Encouraging, never nagging.
    public static func headline(for summary: TodaySummary) -> String {
        let hydrated = summary.water.status != .behind
        switch (summary.sleepGoalMet, hydrated) {
        case (true?, true):
            if summary.workoutWeek.isGoalReached {
                return "Rested, hydrated and your workout goal is done. Fully fueled."
            }
            return "Sleep ✓ and hydrated — you're set for a sharp day."
        case (true?, false):
            return "Well rested. A glass of water now keeps you on pace."
        case (false?, true):
            return "Short night, but you're hydrated. Keep sipping to stay sharp."
        case (false?, false):
            return "Go easy today. A glass of water now helps after a short night."
        case (nil, true):
            return "Hydrated and on track. Keep it flowing."
        case (nil, false):
            return "A glass of water now gets you back on pace."
        }
    }

    // MARK: Water

    /// Millilitres still needed to be back on pace, rounded up to 10 ml; 0 when not behind.
    public static func catchUpML(_ water: WaterProgress) -> Int {
        guard water.status == .behind else { return 0 }
        let gap = max(water.expectedML - Double(water.totalML), 0)
        return Int((gap / 10).rounded(.up)) * 10
    }

    /// "Goal reached", "On track" or "350 ml behind pace" (DECISIONS W8).
    public static func paceText(_ water: WaterProgress) -> String {
        switch water.status {
        case .goalMet: "Goal reached"
        case .onTrack: "On track"
        case .behind: "\(FuelyFormat.water(catchUpML(water))) behind pace"
        }
    }

    /// "Includes 300 ml from other apps", or nil when there is none (DECISIONS W4).
    public static func otherAppsNote(_ summary: TodaySummary) -> String? {
        summary.externalWaterML > 0 ? "Includes \(FuelyFormat.water(summary.externalWaterML)) from other apps" : nil
    }

    /// VoiceOver: "Water, 1.2 liters of 2.4 liters, 50 percent, on track."
    public static func waterAccessibility(_ water: WaterProgress) -> String {
        "Water, \(FuelyFormat.waterSpoken(water.totalML)) of \(FuelyFormat.waterSpoken(water.goalML)), "
            + "\(FuelyFormat.percentValue(water.fraction)) percent, \(paceText(water).lowercased())"
    }

    // MARK: Sleep

    /// Shown when there is no score (DECISIONS S7).
    public static let noSleepHint = "Wear your Watch to bed to get a sleep score."

    /// "Goal 80 · Reached", "Goal 80", or the no-data hint.
    public static func sleepDetail(score: Int?, goal: Int) -> String {
        guard let score else { return noSleepHint }
        return score >= goal ? "Goal \(goal) · Reached" : "Goal \(goal)"
    }

    public static func sleepAccessibility(score: Int?, goal: Int) -> String {
        guard let score else { return "Sleep score, no data. \(noSleepHint)" }
        return "Sleep score \(score) of 100, goal \(goal)" + (score >= goal ? ", reached" : "")
    }

    // MARK: Workouts

    /// "Weekly goal reached", or "1 to go · 3 days left" (days left include today).
    public static func workoutDetail(_ week: WorkoutWeek, now: Date, calendar: Calendar) -> String {
        if week.isGoalReached { return "Weekly goal reached" }
        let daysLeft = week.daysLeft(includingDayOf: now, calendar: calendar)
        return "\(week.workoutsStillNeeded) to go · \(FuelyFormat.count(daysLeft, "day")) left"
    }

    /// "Today 20 of 50 min" / "Today 55 min ✓".
    public static func workoutToday(_ week: WorkoutWeek, now: Date, calendar: Calendar) -> String {
        let day = week.day(containing: now, calendar: calendar)
        let minutes = Int((day?.minutes ?? 0).rounded(.down))
        if day?.isWorkoutDay == true { return "Today \(minutes) min ✓" }
        return "Today \(minutes) of \(week.goal.minMinutesPerDay) min"
    }

    public static func workoutAccessibility(_ week: WorkoutWeek, now: Date, calendar: Calendar) -> String {
        "Workouts, \(week.workoutDays) of \(FuelyFormat.count(week.goal.daysPerWeek, "day")) this week. "
            + "\(workoutDetail(week, now: now, calendar: calendar).replacingOccurrences(of: " · ", with: ", "))"
    }

    // MARK: Sync

    public struct SyncHint: Sendable, Hashable {
        public let title: String
        public let message: String
    }

    /// The hint for a HealthKit sync problem (e.g. "Health access off"); nil when all is fine.
    public static func syncHint(_ issue: HealthSyncIssue?) -> SyncHint? {
        switch issue {
        case nil:
            nil
        case .notAuthorized?:
            SyncHint(title: "Health access off",
                     message: "Your water is saved in Fuely. To sync it, allow access in Settings → Privacy & Security → Health → Fuely.")
        case .locked?:
            SyncHint(title: "Waiting to sync", message: "Fuely syncs with Apple Health once your iPhone is unlocked.")
        case .unavailable?:
            SyncHint(title: "Apple Health unavailable", message: "Your water is saved in Fuely only.")
        case .other?:
            SyncHint(title: "Sync paused", message: "Fuely couldn't reach Apple Health and will try again.")
        }
    }
}
