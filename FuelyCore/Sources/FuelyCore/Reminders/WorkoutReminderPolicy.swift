import Foundation

/// The single workout reminder for a day (DECISIONS R2–R4). Both values feed the copy,
/// e.g. "2 workouts to go, 3 days left this week."
public enum WorkoutReminder: Sendable, Hashable {
    /// slack = 1: a gentle nudge.
    case nudge(workoutsToGo: Int, daysLeft: Int)
    /// slack = 0: "today's a workout day".
    case workoutDay(workoutsToGo: Int, daysLeft: Int)
    /// slack < 0: one quiet note, then silence for the rest of the week.
    case behind(workoutsToGo: Int, daysLeft: Int)
}

/// Decides the morning workout reminder from the week's slack. Decides; does not schedule.
public enum WorkoutReminderPolicy {
    /// slack = days left in the week (including today) − workouts still needed (DECISIONS R2).
    public static func slack(daysLeftInWeek: Int, workoutsStillNeeded: Int) -> Int {
        daysLeftInWeek - workoutsStillNeeded
    }

    /// The reminder to show at `now`, or nil. Nothing before today's `reminderTime`, nothing if a
    /// workout reminder already went out today, nothing once today's minimum is met or the weekly
    /// goal is reached, and nothing after the week's "behind" note was sent.
    public static func reminder(now: Date, samples: [WorkoutSample], goal: WorkoutGoal, reminderTime: TimeOfDay,
                                alreadyRemindedToday: Bool, behindNoteSentThisWeek: Bool,
                                calendar: Calendar) -> WorkoutReminder? {
        guard !alreadyRemindedToday, now >= reminderTime.date(on: now, calendar: calendar) else { return nil }
        let week = WorkoutAggregation.week(containing: now, samples: samples, goal: goal, calendar: calendar)
        guard !week.isGoalReached, week.day(containing: now, calendar: calendar)?.isWorkoutDay != true else { return nil }

        let daysLeft = week.daysLeft(includingDayOf: now, calendar: calendar)
        let toGo = week.workoutsStillNeeded
        switch slack(daysLeftInWeek: daysLeft, workoutsStillNeeded: toGo) {
        case 2...: return nil
        case 1: return .nudge(workoutsToGo: toGo, daysLeft: daysLeft)
        case 0: return .workoutDay(workoutsToGo: toGo, daysLeft: daysLeft)
        default: return behindNoteSentThisWeek ? nil : .behind(workoutsToGo: toGo, daysLeft: daysLeft)
        }
    }

    /// The next `reminderTime` at or after `now`.
    public static func nextReminderDate(after now: Date, reminderTime: TimeOfDay, calendar: Calendar) -> Date {
        let today = reminderTime.date(on: now, calendar: calendar)
        if today >= now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return reminderTime.date(on: tomorrow, calendar: calendar)
    }
}
