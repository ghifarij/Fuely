import Foundation
@testable import FuelyCore

/// A finished week of invented values. `water` = each day's total (ml), `sleep` = each night's
/// score (nil = not tracked), `workoutMinutes` = each day's minutes; Monday first.
func makeWeekHistory(_ week: RecapWeek, calendar: Calendar, settings: FuelySettings = .default,
                     water: [Int] = [], sleep: [Int?] = [], workoutMinutes: [Double] = []) -> WeekHistory {
    func value<T>(_ list: [T], _ index: Int, _ fallback: T) -> T { index < list.count ? list[index] : fallback }
    let goal = settings.workoutGoal
    var days: [HistoryDay] = []
    var workoutDays: [WorkoutDay] = []
    for index in 0..<7 {
        let date = week.date(ofDay: index, calendar: calendar)
        let minutes = value(workoutMinutes, index, 0)
        let isWorkoutDay = minutes > 0 && minutes >= Double(goal.minMinutesPerDay)
        workoutDays.append(WorkoutDay(date: date, minutes: minutes, isWorkoutDay: isWorkoutDay))
        days.append(HistoryDay(date: date, isToday: false, isFuture: false, fuelyEntries: [], externalEntries: [],
                               externalWaterML: value(water, index, 0), waterGoalML: settings.waterGoalML,
                               sleepScore: value(sleep, index, nil), sleepGoal: settings.sleepGoalScore,
                               workoutMinutes: minutes, isWorkoutDay: isWorkoutDay))
    }
    let start = week.start(calendar: calendar)
    return WeekHistory(start: start, days: days, workoutWeek: WorkoutWeek(start: start, days: workoutDays, goal: goal),
                       usesHealthData: true)
}

/// A judgement from invented values with the default goals (2400 ml, score 80, 3 × 50 min).
func makeJudgement(week: RecapWeek = RecapWeek(mondayYear: 2026, month: 11, day: 2),
                   waterDays: Int = 0, sleep: [Int] = [], workoutDays: Int = 0, goalDays: Int = 3,
                   config: WeeklyRecapConfig = .default) -> WeekJudgement {
    let totals = (0..<7).map { $0 < waterDays ? 2400 : 0 }
    return WeekJudgement(week: week,
                         water: WaterWeekJudgement(goalML: 2400, dayTotalsML: totals, config: config),
                         sleep: SleepWeekJudgement(goal: 80, scores: sleep, config: config),
                         workouts: WorkoutWeekJudgement(goal: WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: goalDays),
                                                        workoutDays: workoutDays))
}

func sampleRecap(week: RecapWeek, createdAt: Date = Date(timeIntervalSinceReferenceDate: 800_000_000),
                 waterDays: Int = 6) -> WeeklyRecap {
    WeeklyRecap.make(from: makeJudgement(week: week, waterDays: waterDays, sleep: [84, 86, 79, 90], workoutDays: 3),
                     createdAt: createdAt, calendar: .test(), locale: Locale(identifier: "en_US"))
}

/// Serves invented weeks; counts what was asked for.
final class FakeWeekLoader: WeekHistoryLoading, @unchecked Sendable {
    private let lock = NSLock()
    private let calendar: Calendar
    private var _weeks: [RecapWeek: WeekHistory] = [:]
    private var _issues: [RecapWeek: HealthSyncIssue] = [:]
    private var _loaded: [RecapWeek] = []

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    var loaded: [RecapWeek] { lock.withLock { _loaded } }

    func set(_ history: WeekHistory) {
        lock.withLock { _weeks[RecapWeek(containing: history.start, calendar: calendar)] = history }
    }

    func setIssue(_ issue: HealthSyncIssue?, for week: RecapWeek) {
        lock.withLock { _issues[week] = issue }
    }

    func load(weekContaining date: Date, now: Date) async throws -> (week: WeekHistory, issue: HealthSyncIssue?) {
        let week = RecapWeek(containing: date, calendar: calendar)
        return lock.withLock {
            _loaded.append(week)
            return (_weeks[week] ?? makeWeekHistory(week, calendar: calendar), _issues[week])
        }
    }
}
