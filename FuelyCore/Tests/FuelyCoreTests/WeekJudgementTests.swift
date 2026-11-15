import Foundation
import Testing
@testable import FuelyCore

@Suite struct RecapWeekTests {
    let cal = Calendar.test()

    @Test func namesTheMondayWhateverTheFirstWeekday() {
        // 2026-11-08 is a Sunday: still the week of Monday 2 November.
        #expect(RecapWeek(containing: cal.at(2026, 11, 8, 23, 59), calendar: cal).description == "2026-11-02")
        #expect(RecapWeek(containing: cal.at(2026, 11, 9), calendar: cal).description == "2026-11-09")
        let week = RecapWeek(mondayYear: 2026, month: 11, day: 2)
        #expect(week.start(calendar: cal) == cal.at(2026, 11, 2))
        #expect(week.lastDay(calendar: cal) == cal.at(2026, 11, 8))
        #expect(week.date(ofDay: 3, calendar: cal) == cal.at(2026, 11, 5))
    }

    @Test func movesByWeeksAcrossMonthsAndYears() {
        let week = RecapWeek(mondayYear: 2026, month: 12, day: 28)
        #expect(week.advanced(by: 1, calendar: cal).description == "2027-01-04")
        #expect(week.advanced(by: -5, calendar: cal).description == "2026-11-23")
        #expect(week < week.advanced(by: 1, calendar: cal))
        #expect(RecapWeek(mondayYear: 2026, month: 2, day: 23) < RecapWeek(mondayYear: 2026, month: 11, day: 2))
    }

    @Test func isoWeekNumber() {
        #expect(RecapWeek(mondayYear: 2026, month: 11, day: 2).isoWeekNumber == 45)
        #expect(RecapWeek(mondayYear: 2026, month: 12, day: 28).isoWeekNumber == 53)
        #expect(RecapWeek(mondayYear: 2027, month: 1, day: 4).isoWeekNumber == 1)
    }

    @Test func codesAsText() throws {
        let week = RecapWeek(mondayYear: 2026, month: 11, day: 2)
        let data = try JSONEncoder().encode([week])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-11-02"]"#)
        #expect(try JSONDecoder().decode([RecapWeek].self, from: data) == [week])
        #expect(throws: (any Error).self) { try JSONDecoder().decode([RecapWeek].self, from: Data(#"["soon"]"#.utf8)) }
    }

    @Test func aDayWhoseMidnightIsSkippedStillResolves() {
        // Havana moves the clock forward at 00:00 on Sunday 8 March 2026.
        let havana = Calendar.test("America/Havana")
        let week = RecapWeek(mondayYear: 2026, month: 3, day: 2)
        let sunday = week.lastDay(calendar: havana)
        #expect(havana.component(.day, from: sunday) == 8)
        #expect(RecapWeek(containing: sunday, calendar: havana) == week)
        #expect(week.advanced(by: 1, calendar: havana).description == "2026-03-09")
    }
}

@Suite struct WeekJudgementTests {
    let cal = Calendar.test()
    let week = RecapWeek(mondayYear: 2026, month: 11, day: 2)

    // MARK: Water (WR4, WR4a)

    @Test(arguments: [(7, WaterWeekJudgement.Tier.perfect, true), (6, .strong, true), (5, .strong, true),
                      (4, .mixed, false), (3, .mixed, false), (2, .low, false), (1, .low, false), (0, .low, false)])
    func waterTiers(days: Int, tier: WaterWeekJudgement.Tier, strong: Bool) {
        let water = makeJudgement(waterDays: days).water
        #expect(water.daysReached == days)
        #expect(water.tier == tier)
        #expect(water.isStrong == strong)
        #expect(water.fraction == Double(days) / 7)
    }

    @Test func waterPatternFacts() {
        let water = WaterWeekJudgement(goalML: 2400, dayTotalsML: [2400, 2650, 900, 2650, 3000, 0, 2399])
        #expect(water.reachedDays == [0, 1, 3, 4])
        #expect(water.slippedDays == [2, 5, 6])
        #expect(water.bestDay == 4)
        #expect(water.bestDayML == 3000)
        #expect(water.hasData)
    }

    @Test func bestDayIsTheEarliestOnATieAndMissingWithoutWater() {
        #expect(WaterWeekJudgement(goalML: 2400, dayTotalsML: [0, 800, 0, 800, 0, 0, 0]).bestDay == 1)
        let empty = WaterWeekJudgement(goalML: 2400, dayTotalsML: [])
        #expect(empty.bestDay == nil)
        #expect(empty.bestDayML == 0)
        #expect(!empty.hasData)
        #expect(empty.slippedDays == Array(0..<7))
    }

    // MARK: Sleep (WR4, S7)

    @Test func sleepIsJudgedOverTrackedNightsOnly() {
        let sleep = SleepWeekJudgement(goal: 80, scores: [84, 91, 78, 85])
        #expect(sleep.state == .judged)
        #expect(sleep.trackedNights == 4)
        #expect(sleep.average == 85) // 84.5 rounds up
        #expect(sleep.nightsAtGoal == 3)
        #expect(sleep.tier == .strong)
        #expect(sleep.isStrong)
        #expect(sleep.fraction == 1)
    }

    @Test(arguments: [(80, SleepWeekJudgement.Tier.strong), (79, .mid), (70, .mid), (69, .low), (40, .low)])
    func sleepTiers(average: Int, tier: SleepWeekJudgement.Tier) {
        let sleep = SleepWeekJudgement(goal: 80, scores: [average, average, average])
        #expect(sleep.tier == tier)
        #expect(sleep.isStrong == (tier == .strong))
    }

    @Test func fewerThanThreeNightsGiveNoVerdict() {
        let two = SleepWeekJudgement(goal: 80, scores: [95, 97])
        #expect(two.state == .tooFewNights)
        #expect(two.tier == nil)
        #expect(!two.isStrong)
        #expect(!two.isJudged)
        #expect(two.fraction == 0)
        #expect(two.average == 96)

        let none = SleepWeekJudgement(goal: 80, scores: [])
        #expect(none.state == .noneTracked)
        #expect(none.average == nil)
        #expect(none.trackedNights == 0)
    }

    // MARK: Workouts (WR4, K2)

    @Test(arguments: [(5, 3, WorkoutWeekJudgement.Tier.beyond, 2), (4, 3, .beyond, 1), (3, 3, .met, 0),
                      (2, 3, .oneShort, 0), (1, 3, .missed, 0), (0, 3, .missed, 0),
                      (0, 1, .missed, 0), (1, 1, .met, 0), (6, 7, .oneShort, 0), (7, 7, .met, 0)])
    func workoutTiers(days: Int, goal: Int, tier: WorkoutWeekJudgement.Tier, extra: Int) {
        let workouts = makeJudgement(workoutDays: days, goalDays: goal).workouts
        #expect(workouts.tier == tier)
        #expect(workouts.extraDays == extra)
        #expect(workouts.isStrong == (tier == .beyond || tier == .met))
        #expect(workouts.fraction == Double(days) / Double(goal))
        #expect(workouts.hasData == (days > 0))
    }

    // MARK: Mood (WR6)

    /// (water days, sleep scores, workout days of 3) → mood. Sleep: [] = none tracked,
    /// 84 = strong, 74 = mid, 60 = low (three nights each).
    static let moodTable: [(Int, [Int], Int, WeeklyRecap.Mood)] = [
        // Three judged rings.
        (7, [84, 84, 84], 4, .allStrong), (5, [80, 80, 80], 3, .allStrong),
        (6, [74, 74, 74], 3, .twoStrong), (6, [84, 84, 84], 2, .twoStrong), (4, [84, 84, 84], 3, .twoStrong),
        (0, [84, 84, 84], 5, .twoStrong),
        (5, [60, 60, 60], 0, .oneStrong), (2, [84, 84, 84], 1, .oneStrong), (3, [74, 74, 74], 3, .oneStrong),
        (4, [74, 74, 74], 2, .mixed), (3, [60, 60, 60], 0, .mixed), (0, [74, 74, 74], 0, .mixed),
        (1, [60, 60, 60], 2, .mixed),
        (2, [60, 60, 60], 1, .low), (0, [60, 60, 60], 0, .low), (1, [69, 69, 69], 0, .low),
        // No sleep verdict: water and workouts only.
        (7, [], 3, .allStrong), (5, [90, 90], 4, .allStrong), (6, [40], 3, .allStrong),
        (6, [], 2, .oneStrong), (1, [84, 84], 3, .oneStrong), (0, [], 3, .oneStrong), (5, [], 0, .oneStrong),
        (4, [], 0, .mixed), (0, [60], 2, .mixed), (3, [84, 84], 2, .mixed),
        (2, [], 1, .low), (1, [], 0, .low), (0, [95, 95], 0, .low), (0, [], 1, .low),
        // Nothing at all.
        (0, [], 0, .notEnoughData),
    ]

    @Test(arguments: moodTable.indices)
    func mood(row: Int) {
        let (water, sleep, workouts, mood) = Self.moodTable[row]
        let judgement = makeJudgement(waterDays: water, sleep: sleep, workoutDays: workouts)
        #expect(judgement.mood == mood, "water \(water), sleep \(sleep), workouts \(workouts)")
    }

    @Test func notEnoughDataNeedsAllThreeEmpty() {
        #expect(!makeJudgement().hasEnoughData)
        #expect(makeJudgement(sleep: [50]).hasEnoughData)
        #expect(makeJudgement(workoutDays: 1).hasEnoughData)
        // Water below the goal, or a workout too short to count, is still data.
        let sips = WeekJudgement(week: week, water: WaterWeekJudgement(goalML: 2400, dayTotalsML: [0, 250]),
                                 sleep: SleepWeekJudgement(goal: 80, scores: []),
                                 workouts: WorkoutWeekJudgement(goal: .default, workoutDays: 0))
        #expect(sips.mood == .low)
        let shortRun = WeekJudgement(week: week, water: WaterWeekJudgement(goalML: 2400, dayTotalsML: []),
                                     sleep: SleepWeekJudgement(goal: 80, scores: []),
                                     workouts: WorkoutWeekJudgement(goal: .default, workoutDays: 0, hasData: true))
        #expect(shortRun.mood == .low)
    }

    @Test func judgedAndStrongRings() {
        let all = makeJudgement(waterDays: 6, sleep: [84, 84, 84], workoutDays: 1)
        #expect(all.judgedRings == [.water, .sleep, .workouts])
        #expect(all.strongRings == [.water, .sleep])
        #expect(all.weakRings == [.workouts])
        #expect(makeJudgement(waterDays: 6, sleep: [99, 99]).judgedRings == [.water, .workouts])
    }

    // MARK: Weakest ring (WR5)

    @Test func weakestRingIsNilWhenEveryJudgedRingIsStrong() {
        #expect(makeJudgement(waterDays: 7, sleep: [84, 84, 84], workoutDays: 3).weakestRing == nil)
        #expect(makeJudgement(waterDays: 5, sleep: [10, 10], workoutDays: 3).weakestRing == nil)
    }

    @Test func weakestRingPrefersLowTiersThenTheEmptierRing() {
        // Sleep is mid, workouts missed.
        #expect(makeJudgement(waterDays: 7, sleep: [74, 74, 74], workoutDays: 1).weakestRing == .workouts)
        // Water low (2/7 = 0.29) against workouts missed (1/3 = 0.33).
        #expect(makeJudgement(waterDays: 2, sleep: [84, 84, 84], workoutDays: 1).weakestRing == .water)
        // Both mid: water 4/7 = 0.57 against workouts 2/3 = 0.67.
        #expect(makeJudgement(waterDays: 4, sleep: [84, 84, 84], workoutDays: 2).weakestRing == .water)
        // Sleep low against water mixed.
        #expect(makeJudgement(waterDays: 4, sleep: [50, 50, 50], workoutDays: 3).weakestRing == .sleep)
        // Unjudged sleep is never the weakest.
        #expect(makeJudgement(waterDays: 6, sleep: [10], workoutDays: 2).weakestRing == .workouts)
        // A tie goes to water.
        #expect(makeJudgement(waterDays: 0, sleep: [], workoutDays: 0, goalDays: 3).weakestRing == .water)
    }

    // MARK: From history

    @Test func judgesAFinishedWeekOfHistory() {
        var settings = FuelySettings.default
        settings.waterGoalML = 2000
        settings.sleepGoalScore = 85
        settings.workoutGoal = WorkoutGoal(minMinutesPerDay: 30, daysPerWeek: 2)
        let history = makeWeekHistory(week, calendar: cal, settings: settings,
                                      water: [2000, 2100, 1999, 2600, 2000, 300, 0],
                                      sleep: [88, nil, 80, 90, nil, nil, 86],
                                      workoutMinutes: [0, 45, 29, 0, 30, 0, 61])
        let judgement = WeekJudgement(history, calendar: cal)
        #expect(judgement.week == week)
        #expect(judgement.water.goalML == 2000)
        #expect(judgement.water.daysReached == 4)
        #expect(judgement.water.slippedDays == [2, 5, 6])
        #expect(judgement.water.bestDay == 3)
        #expect(judgement.sleep.goal == 85)
        #expect(judgement.sleep.trackedNights == 4)
        #expect(judgement.sleep.average == 86)
        #expect(judgement.sleep.nightsAtGoal == 3)
        #expect(judgement.workouts.workoutDays == 3)
        #expect(judgement.workouts.goalDays == 2)
        #expect(judgement.workouts.tier == .beyond)
        #expect(judgement.mood == .twoStrong)
    }

    @Test func thresholdsComeFromTheConfig() {
        let config = WeeklyRecapConfig(waterStrongDays: 4, minimumSleepNights: 2, sleepMidMargin: 5)
        let judgement = makeJudgement(waterDays: 4, sleep: [74, 74], workoutDays: 3, config: config)
        #expect(judgement.water.tier == .strong)
        #expect(judgement.sleep.state == .judged)
        #expect(judgement.sleep.tier == .low)
        #expect(judgement.mood == .twoStrong)
    }
}
