#if DEBUG
import FuelyCore
import Foundation

/// DEBUG fixtures for the SwiftUI previews: six invented weeks, one per mood (WR6), built as the
/// saved model. No HealthKit, no store.
enum WeeklyRecapSamples {
    static let all: [WeeklyRecap] = [allStrong, twoStrong, oneStrong, mixed, low, notEnoughData]

    // An invented Monday–Sunday week.
    private static let week = RecapWeek(mondayYear: 2026, month: 3, day: 2)
    /// Goals in every sample: 2.4 L, sleep score 80, 3 workout days.
    private static let sleepGoal = 80
    private static let workoutGoal = 3

    private static func recap(_ mood: WeeklyRecap.Mood, _ headline: String, _ supporting: String,
                              rows: [WeeklyRecap.Row], suggestion: String? = nil, congratulation: String? = nil,
                              _ numbers: WeeklyRecap.Numbers) -> WeeklyRecap {
        WeeklyRecap(week: week, createdAt: Date(timeIntervalSinceReferenceDate: 794_750_400), mood: mood,
                    headline: headline, supporting: supporting, rows: rows,
                    closing: suggestion ?? congratulation ?? "", closingIsSuggestion: suggestion != nil,
                    numbers: numbers)
    }

    private static func numbers(water: Int, bestML: Int, nights: Int = 0, average: Int? = nil, atGoal: Int = 0,
                                workouts: Int) -> WeeklyRecap.Numbers {
        WeeklyRecap.Numbers(waterDaysReached: water, waterGoalML: 2400, bestWaterDayML: bestML,
                            sleepTrackedNights: nights, sleepAverage: average, sleepNightsAtGoal: atGoal,
                            sleepGoal: sleepGoal, workoutDays: workouts, workoutGoalDays: workoutGoal)
    }

    private static func water(_ days: Int, _ line: String) -> WeeklyRecap.Row {
        .init(ring: .water, fraction: Double(days) / 7, number: "\(days)", unit: "of 7 days",
              shortNumber: "\(days)/7", caption: "of 7 days", line: line)
    }

    private static func sleep(average: Int, _ line: String) -> WeeklyRecap.Row {
        .init(ring: .sleep, fraction: min(Double(average) / Double(sleepGoal), 1), number: "\(average)",
              unit: "avg sleep score", shortNumber: "\(average)", caption: "avg sleep score", line: line)
    }

    /// No verdict (WR4): `stat` says why.
    private static func noSleepVerdict(_ stat: String, caption: String, _ line: String) -> WeeklyRecap.Row {
        .init(ring: .sleep, fraction: 0, number: nil, unit: stat, shortNumber: WeeklyRecap.Row.noVerdict,
              caption: caption, line: line)
    }

    private static func workouts(_ days: Int, _ line: String) -> WeeklyRecap.Row {
        .init(ring: .workouts, fraction: Double(days) / Double(workoutGoal), number: "\(days)",
              unit: "of \(workoutGoal) days", shortNumber: "\(days)/\(workoutGoal)",
              caption: "of \(workoutGoal) days", line: line)
    }

    /// 🤩 Every judged ring strong: a congratulation instead of a suggestion (WR5).
    static let allStrong = recap(
        .allStrong, "A strong week.", "Water, sleep and workouts all landed.",
        rows: [
            water(7, "Every day reached the goal."),
            sleep(average: 84, "5 nights tracked, 4 at 80 or above."),
            workouts(4, "One more than planned."),
        ],
        congratulation: "Nothing to fix. Enjoy it, and keep the rhythm.",
        numbers(water: 7, bestML: 2900, nights: 5, average: 84, atGoal: 4, workouts: 4))

    /// 😄 Two strong.
    static let twoStrong = recap(
        .twoStrong, "A good week.", "Hydrated and active, sleep fell a little behind.",
        rows: [
            water(6, "Only Saturday slipped."),
            sleep(average: 74, "6 nights tracked, 2 at 80 or above."),
            workouts(3, "Goal reached on Friday."),
        ],
        suggestion: "start winding down 20 minutes earlier.",
        numbers(water: 6, bestML: 2700, nights: 6, average: 74, atGoal: 2, workouts: 3))

    /// 🙂 One strong, and no Watch: "No sleep tracked", judged on water and workouts only (WR4).
    static let oneStrong = recap(
        .oneStrong, "A steady week.", "Water held up well, workouts came up short.",
        rows: [
            water(5, "Wednesday and Sunday slipped."),
            noSleepVerdict("No sleep tracked", caption: "not tracked", "Wear your Watch to bed for a score."),
            workouts(1, "One session, on Tuesday."),
        ],
        suggestion: "pick two workout days now and keep them free.",
        numbers(water: 5, bestML: 2600, workouts: 1))

    /// 😅 Mixed, none strong; fewer than 3 tracked nights → no sleep verdict + Watch hint (WR4).
    static let mixed = recap(
        .mixed, "A mixed week.", "A bit of everything, nothing quite there yet.",
        rows: [
            water(4, "Best day: Thursday, 2.6 L."),
            noSleepVerdict("2 nights tracked", caption: "2 nights tracked", "Too few nights for a score."),
            workouts(2, "One day short of the goal."),
        ],
        suggestion: "one more workout day gets you there.",
        numbers(water: 4, bestML: 2600, nights: 2, average: 77, atGoal: 1, workouts: 2))

    /// 😴 Low week.
    static let low = recap(
        .low, "A quiet week.", "Some weeks are like that. A fresh one starts now.",
        rows: [
            water(1, "Tuesday reached the goal."),
            sleep(average: 61, "7 nights tracked, none reached 80."),
            workouts(0, "No workouts logged."),
        ],
        suggestion: "start small, a glass of water each morning.",
        numbers(water: 1, bestML: 2450, nights: 7, average: 61, workouts: 0))

    /// 👀 Not enough data: no water, no sleep, no workouts (WR4a).
    static let notEnoughData = recap(
        .notEnoughData, "Not much to go on.", "Fuely saw very little of last week.",
        rows: [
            water(0, "No water logged."),
            noSleepVerdict("No sleep tracked", caption: "not tracked", "Wear your Watch to bed for a score."),
            workouts(0, "No workouts found."),
        ],
        suggestion: "log your first glass and the rest follows.",
        numbers(water: 0, bestML: 0, workouts: 0))
}
#endif
