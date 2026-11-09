import Foundation

/// One calendar day of workouts.
public struct WorkoutDay: Sendable, Hashable {
    /// Start of the day.
    public let date: Date
    /// Summed active minutes of all workouts that started this day (DECISIONS K3).
    public let minutes: Double
    /// Whether `minutes` reaches the daily minimum.
    public let isWorkoutDay: Bool
}

/// A Monday–Sunday week of workout days (DECISIONS K2, K3).
public struct WorkoutWeek: Sendable, Hashable {
    /// Monday 00:00.
    public let start: Date
    /// Monday through Sunday, always 7.
    public let days: [WorkoutDay]
    public let goal: WorkoutGoal

    /// Days that reached the minimum; each day counts at most once. May exceed the goal.
    public var workoutDays: Int { days.filter(\.isWorkoutDay).count }
    public var isGoalReached: Bool { workoutDays >= goal.daysPerWeek }
    public var workoutsStillNeeded: Int { max(goal.daysPerWeek - workoutDays, 0) }

    public func day(containing date: Date, calendar: Calendar) -> WorkoutDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Days from the day of `date` through Sunday, including that day; 0 outside this week.
    public func daysLeft(includingDayOf date: Date, calendar: Calendar) -> Int {
        guard let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { return 0 }
        return days.count - index
    }
}

public enum WorkoutAggregation {
    /// Monday 00:00 of the week containing `date`, regardless of the calendar's `firstWeekday`.
    public static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday … 7 = Saturday
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    /// The Monday–Sunday week containing `now`, regardless of the calendar's `firstWeekday`.
    /// A workout counts on the day it starts, with its active `duration`.
    public static func week(containing now: Date, samples: [WorkoutSample], goal: WorkoutGoal, calendar: Calendar) -> WorkoutWeek {
        let monday = weekStart(containing: now, calendar: calendar)
        let dayStarts = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday) ?? monday }

        var seconds = [Date: TimeInterval]()
        for sample in samples {
            let day = calendar.startOfDay(for: sample.start)
            seconds[day, default: 0] += max(sample.duration, 0)
        }

        let threshold = TimeInterval(goal.minMinutesPerDay * 60)
        let days = dayStarts.map { day in
            let total = seconds[day] ?? 0
            return WorkoutDay(date: day, minutes: total / 60, isWorkoutDay: total > 0 && total >= threshold)
        }
        return WorkoutWeek(start: monday, days: days, goal: goal)
    }
}
