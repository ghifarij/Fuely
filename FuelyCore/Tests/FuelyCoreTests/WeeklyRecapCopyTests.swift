import Foundation
import Testing
@testable import FuelyCore

@Suite struct WeeklyRecapCopyTests {
    let cal = Calendar.test()
    let us = Locale(identifier: "en_US")
    let week = RecapWeek(mondayYear: 2026, month: 11, day: 2)
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private func judgement(water: [Int], sleep: [Int] = [], sleepGoal: Int = 80, workoutDays: Int = 0,
                           goalDays: Int = 3, workoutData: Bool = false) -> WeekJudgement {
        WeekJudgement(week: week, water: WaterWeekJudgement(goalML: 2400, dayTotalsML: water),
                      sleep: SleepWeekJudgement(goal: sleepGoal, scores: sleep),
                      workouts: WorkoutWeekJudgement(goal: WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: goalDays),
                                                     workoutDays: workoutDays, hasData: workoutData))
    }

    private func text(_ judgement: WeekJudgement, _ variant: Int = 0) -> WeeklyRecapText {
        WeeklyRecapCopy.text(for: judgement, variant: variant, calendar: cal, locale: us)
    }

    /// Every phrasing of one piece over a full cycle of seeds. The line tests check that a wording
    /// is among them, so they don't depend on which seed picks it.
    private func all(_ judgement: WeekJudgement, _ piece: (WeeklyRecapText) -> String) -> Set<String> {
        Set((0..<WeeklyRecapCopy.variantCycle).map { piece(text(judgement, $0)) })
    }

    // MARK: The hard limits (WR3)

    /// Long amounts on purpose: "12.35 L" on days at the goal, "2.39 L" just under it.
    private static func water(reached: Set<Int>) -> WaterWeekJudgement {
        WaterWeekJudgement(goalML: 2400, dayTotalsML: (0..<7).map { reached.contains($0) ? 12_350 : 2_390 })
    }

    /// Every weekday pattern: each subset of days at the goal, plus nothing logged.
    static let everyWaterPattern = [WaterWeekJudgement(goalML: 2400, dayTotalsML: [])]
        + (0..<128).map { mask in water(reached: Set((0..<7).filter { mask & (1 << $0) != 0 })) }

    /// Every count of days at the goal, with and without the weekend patterns, plus nothing logged.
    static let waterPerDayCount = [WaterWeekJudgement(goalML: 2400, dayTotalsML: [])]
        + (0...7).map { water(reached: Set(0..<$0)) }
        + [[5, 6], [0, 5, 6], [2, 3, 4], [1, 2, 3, 4], [0, 1, 2, 5, 6]].map { water(reached: Set($0)) }

    /// No night, too few, and every tier with none / some / all nights at the goal; goals 50 and 100.
    static let everySleepCase: [SleepWeekJudgement] = [50, 100].flatMap { goal in
        [[], [goal], [goal, goal - 20], [goal, goal, goal], Array(repeating: goal, count: 7),
         [goal, goal - 3, goal - 3], Array(repeating: goal - 5, count: 7),
         [goal, goal - 40, goal - 40, goal - 40, goal, goal, goal - 40],
         Array(repeating: goal - 30, count: 7), [100, 100, 100, 100, 100, 100, max(goal - 1, 0)]]
            .map { SleepWeekJudgement(goal: goal, scores: $0) }
    }

    /// Every number of workout days against every weekly goal, plus workouts too short to count.
    static let everyWorkoutCase: [WorkoutWeekJudgement] = (1...7).flatMap { goalDays in
        let goal = WorkoutGoal(minMinutesPerDay: SettingsLimits.workoutMinutes.upperBound, daysPerWeek: goalDays)
        return [WorkoutWeekJudgement(goal: goal, workoutDays: 0, hasData: true)]
            + (0...7).map { WorkoutWeekJudgement(goal: goal, workoutDays: $0) }
    }

    /// Checks every phrasing of every combination; returns the moods seen and what broke the rules.
    private func audit(_ waters: [WaterWeekJudgement], _ sleeps: [SleepWeekJudgement],
                       _ workouts: [WorkoutWeekJudgement]) -> (moods: Set<WeeklyRecap.Mood>, failures: Set<String>) {
        var moods = Set<WeeklyRecap.Mood>()
        var failures = Set<String>()
        func check(_ text: String, _ limit: Int, _ what: String) {
            if text.isEmpty || text.count > limit || text.contains("  ") || text.contains("!") || !text.hasSuffix(".") {
                failures.insert("\(what) (\(text.count)/\(limit)): \(text)")
            }
        }
        for water in waters {
            for sleep in sleeps {
                for workout in workouts {
                    let judgement = WeekJudgement(week: week, water: water, sleep: sleep, workouts: workout)
                    moods.insert(judgement.mood)
                    for variant in 0..<WeeklyRecapCopy.variantCycle {
                        let text = WeeklyRecapCopy.text(for: judgement, variant: variant, weekdayNames: Self.names)
                        check(text.headline, WeeklyRecapCopy.Limit.headline, "headline")
                        check(text.supporting, WeeklyRecapCopy.Limit.supporting, "supporting")
                        check(text.waterLine, WeeklyRecapCopy.Limit.ringLine, "water")
                        check(text.sleepLine, WeeklyRecapCopy.Limit.ringLine, "sleep")
                        check(text.workoutLine, WeeklyRecapCopy.Limit.ringLine, "workouts")
                        check(text.closing, WeeklyRecapCopy.Limit.closing, "closing")
                        let first = text.closing.first.map(String.init) ?? ""
                        if text.closingIsSuggestion != (first == first.lowercased()) {
                            failures.insert("closing case: \(text.closing)")
                        }
                        if text.closingIsSuggestion == (judgement.hasEnoughData && judgement.weakestRing == nil) {
                            failures.insert("closing kind: \(text.closing)")
                        }
                    }
                }
            }
        }
        return (moods, failures)
    }

    @Test func theCasesCoverEveryTier() {
        #expect(Self.everyWaterPattern.count == 129)
        #expect(Set(Self.waterPerDayCount.map(\.daysReached)) == Set(0...7))
        #expect(Set(Self.waterPerDayCount.map(\.tier)) == Set(WaterWeekJudgement.Tier.allCases))
        #expect(Set(Self.everySleepCase.map(\.state)) == Set(SleepWeekJudgement.State.allCases))
        #expect(Set(Self.everySleepCase.compactMap(\.tier)) == Set(SleepWeekJudgement.Tier.allCases))
        #expect(Set(Self.everyWorkoutCase.map(\.tier)) == Set(WorkoutWeekJudgement.Tier.allCases))
    }

    /// Every tier combination (every count of water days × every sleep case × every workout case)
    /// × every phrasing: within the limits, never empty.
    @Test func everyTierCombinationFitsTheScreen() {
        let result = audit(Self.waterPerDayCount, Self.everySleepCase, Self.everyWorkoutCase)
        #expect(result.moods == Set(WeeklyRecap.Mood.allCases))
        #expect(result.failures.isEmpty, "\(result.failures.sorted().prefix(20))")
    }

    /// Every weekday pattern × every phrasing, against one sleep case per state and tier and one
    /// workout case per tier (the weekday pattern only changes the water line and, through the
    /// weekend, the suggestion).
    @Test func everyWeekdayPatternFitsTheScreen() {
        let sleeps = [[], [100], [100, 100, 100], [75, 75, 75], [40, 40, 40]].map { SleepWeekJudgement(goal: 80, scores: $0) }
        let goal = WorkoutGoal(minMinutesPerDay: 240, daysPerWeek: 3)
        let workouts = [0, 2, 3, 7].map { WorkoutWeekJudgement(goal: goal, workoutDays: $0) }
        let result = audit(Self.everyWaterPattern, sleeps, workouts)
        #expect(result.moods == Set(WeeklyRecap.Mood.allCases))
        #expect(result.failures.isEmpty, "\(result.failures.sorted().prefix(20))")
    }

    @Test func limitsAreTheOnesTheScreenWasDesignedFor() {
        #expect(WeeklyRecapCopy.Limit.headline == 22)
        #expect(WeeklyRecapCopy.Limit.supporting == 45)
        #expect(WeeklyRecapCopy.Limit.ringLine == 34)
        #expect(WeeklyRecapCopy.Limit.closing == 60)
    }

    // MARK: Phrasings

    @Test func everyCaseHasAtLeastThreePhrasings() {
        let strong = [84, 84, 84], mid = [74, 74, 74], low = [60, 60, 60]
        let full = Array(repeating: 2400, count: 7)
        let cases: [WeekJudgement] = [
            judgement(water: full, sleep: strong, workoutDays: 4),                       // all strong
            judgement(water: full, workoutDays: 3),                                      // all strong, 2 rings
            judgement(water: full, sleep: mid, workoutDays: 3),                          // two strong
            judgement(water: full, sleep: low, workoutDays: 0),                          // one strong
            judgement(water: full, workoutDays: 1),                                      // one strong, 2 rings
            judgement(water: [2400, 2400, 2400, 900, 0, 0, 0], sleep: mid, workoutDays: 2), // mixed
            judgement(water: [900, 0, 0, 0, 0, 0, 0], sleep: low, workoutDays: 0),       // low
            judgement(water: []),                                                        // not enough data
        ]
        #expect(Set(cases.map(\.mood)) == Set(WeeklyRecap.Mood.allCases))
        for item in cases {
            #expect(all(item, \.headline).count >= 3, "\(item.mood) headline")
            #expect(all(item, \.supporting).count >= 3, "\(item.mood) supporting")
            #expect(all(item, \.closing).count >= 3, "\(item.mood) closing")
        }
        // Each weakest ring, close and far.
        for item in [judgement(water: [2400, 2400, 2400, 0, 0, 0, 0], sleep: strong, workoutDays: 3),
                     judgement(water: [2400, 2400, 2400, 0, 2400, 0, 0], sleep: strong, workoutDays: 3),
                     judgement(water: [0, 0, 300, 0, 0, 0, 0], sleep: strong, workoutDays: 3),
                     judgement(water: full, sleep: mid, workoutDays: 3),
                     judgement(water: full, sleep: low, workoutDays: 3),
                     judgement(water: full, sleep: strong, workoutDays: 2),
                     judgement(water: full, sleep: strong, workoutDays: 0)] {
            #expect(all(item, \.closing).count >= 3, "\(String(describing: item.weakestRing)) closing")
        }
    }

    @Test func theSameWeekAlwaysReadsTheSameAndWeeksDiffer() {
        let item = judgement(water: Array(repeating: 2400, count: 7), sleep: [84, 84, 84], workoutDays: 3)
        #expect(WeeklyRecapCopy.text(for: item, calendar: cal, locale: us)
            == WeeklyRecapCopy.text(for: item, calendar: cal, locale: us))
        #expect(WeeklyRecapCopy.variant(for: week) == 45 + 2026)
        #expect(WeeklyRecapCopy.text(for: item, calendar: cal, locale: us) == text(item, 45 + 2026))
        // The time zone doesn't change the phrasing.
        #expect(WeeklyRecapCopy.text(for: item, calendar: .test("America/Los_Angeles"), locale: us)
            == WeeklyRecapCopy.text(for: item, calendar: cal, locale: us))

        let next = WeekJudgement(week: week.advanced(by: 1, calendar: cal), water: item.water, sleep: item.sleep,
                                 workouts: item.workouts)
        #expect(WeeklyRecapCopy.text(for: next, calendar: cal, locale: us).headline
            != WeeklyRecapCopy.text(for: item, calendar: cal, locale: us).headline)
    }

    // MARK: Water line

    @Test func waterLines() {
        let g = 2400
        #expect(all(judgement(water: []), \.waterLine).contains("No water logged."))
        #expect(all(judgement(water: Array(repeating: g, count: 7)), \.waterLine).contains("Every day reached the goal."))
        #expect(all(judgement(water: [g, g, g, g, g, 0, g]), \.waterLine).contains("Only Saturday slipped."))
        #expect(all(judgement(water: [g, g, 0, g, g, g, 0]), \.waterLine).contains("Wednesday and Sunday slipped."))
        #expect(all(judgement(water: [g, g, g, g, g, 0, 0]), \.waterLine).contains("Only the weekend slipped."))
        #expect(all(judgement(water: [g, g, 0, 2650, 0, g, 0]), \.waterLine).contains("Best day: Thursday, 2.65 L."))
        #expect(all(judgement(water: [0, g, 0, 0, 0, 0, 0]), \.waterLine).contains("Tuesday reached the goal."))
        #expect(all(judgement(water: [0, g, 0, 0, g, 0, 0]), \.waterLine).contains("Tuesday and Friday got there."))
        #expect(all(judgement(water: [0, 0, 0, 0, 0, g, g]), \.waterLine).contains("The weekend reached the goal."))
        #expect(all(judgement(water: [0, 850, 0, 300, 0, 0, 0]), \.waterLine).contains("Best day: Tuesday, 850 ml."))
    }

    @Test func weekdayNamesAreEnglishInAnyRegion() {
        let g = 2400
        let item = judgement(water: [g, g, 0, g, g, g, g])
        for id in ["id_ID", "nl_NL", "en_GB", "ja_JP"] {
            #expect(WeeklyRecapCopy.text(for: item, variant: 2, calendar: cal, locale: Locale(identifier: id)).waterLine
                == "Only Wednesday slipped.")
        }
    }

    // MARK: Sleep line

    @Test func sleepLines() {
        #expect(all(judgement(water: []), \.sleepLine).contains("No sleep tracked."))
        #expect(all(judgement(water: [], sleep: [90]), \.sleepLine).contains("1 night tracked. Wear your Watch."))
        #expect(all(judgement(water: [], sleep: [90, 70]), \.sleepLine).contains("Only 2 nights. Wear your Watch."))
        #expect(all(judgement(water: [], sleep: [84, 90, 70, 81, 85]), \.sleepLine).contains("5 nights tracked, 4 at 80+."))
        #expect(all(judgement(water: [], sleep: [84, 90, 81]), \.sleepLine).contains("All 3 tracked nights at 80+."))
        #expect(all(judgement(water: [], sleep: [60, 61, 62, 63]), \.sleepLine).contains("4 nights tracked, none at 80+."))
        for item in [judgement(water: [], sleep: [90]), judgement(water: [], sleep: [90, 70])] {
            #expect(all(item, \.sleepLine).allSatisfy { $0.contains("Wear your Watch") })
        }
    }

    // MARK: Workout line

    @Test func workoutLines() {
        #expect(all(judgement(water: [], workoutDays: 4), \.workoutLine).contains("One more than planned."))
        #expect(all(judgement(water: [], workoutDays: 6), \.workoutLine).contains("3 more than planned."))
        #expect(all(judgement(water: [], workoutDays: 3), \.workoutLine).contains("Goal reached."))
        #expect(all(judgement(water: [], workoutDays: 2), \.workoutLine).contains("One day short of the goal."))
        #expect(all(judgement(water: [], workoutDays: 1, goalDays: 4), \.workoutLine).contains("3 days short of the goal."))
        #expect(all(judgement(water: [], workoutDays: 0), \.workoutLine).contains("No workouts logged."))
        #expect(all(judgement(water: [], workoutDays: 0, workoutData: true), \.workoutLine).contains("No day reached 50 min."))
    }

    // MARK: Supporting line and closing

    @Test func supportingLineNamesTheRings() {
        let full = Array(repeating: 2400, count: 7)
        #expect(all(judgement(water: full, sleep: [84, 84, 84], workoutDays: 3), \.supporting).contains("Water, sleep and workouts all landed."))
        #expect(all(judgement(water: full, workoutDays: 3), \.supporting).contains("Water and workouts both landed."))
        #expect(all(judgement(water: full, sleep: [74, 74, 74], workoutDays: 3), \.supporting).contains("Water and workouts held up, sleep lagged."))
        #expect(all(judgement(water: [], sleep: [84, 84, 84], workoutDays: 0), \.supporting).contains("Sleep held up, water and workouts slipped."))
        #expect(all(judgement(water: full, workoutDays: 0), \.supporting).contains("Water held up, workouts came up short."))
        #expect(all(judgement(water: [2400, 2400, 2400], sleep: [60, 60, 60], workoutDays: 2), \.supporting).contains("Water and workouts got close to the goal."))
        #expect(all(judgement(water: [2400, 2400, 2400], sleep: [74, 74, 74], workoutDays: 2), \.supporting).contains("All three rings got close."))
        #expect(all(judgement(water: [300], workoutDays: 0), \.supporting).contains("Water and workouts both ran low."))
        #expect(all(judgement(water: [300], sleep: [60, 60, 60], workoutDays: 0), \.supporting).contains("Water, sleep and workouts all ran low."))
    }

    @Test func closingIsACongratulationOnlyWhenEveryJudgedRingIsStrong() {
        let full = Array(repeating: 2400, count: 7)
        let strong = judgement(water: full, sleep: [84, 84, 84], workoutDays: 3)
        #expect(!text(strong).closingIsSuggestion)
        #expect(all(strong, \.closing).contains("Nothing to fix. Enjoy it, and keep the rhythm."))
        #expect(!text(judgement(water: full, sleep: [10, 10], workoutDays: 3)).closingIsSuggestion)

        let sleep = judgement(water: full, sleep: [74, 74, 74], workoutDays: 3)
        #expect(text(sleep).closingIsSuggestion)
        #expect(all(sleep, \.closing).contains("start winding down 20 minutes earlier."))
        #expect(all(judgement(water: full, sleep: [84, 84, 84], workoutDays: 2), \.closing).contains("one more workout day gets you there."))
        #expect(all(judgement(water: [300], sleep: [84, 84, 84], workoutDays: 3), \.closing).contains("start small, a glass of water each morning."))
        let empty = judgement(water: [])
        #expect(text(empty).closingIsSuggestion)
        #expect(all(empty, \.closing).contains("log your first glass and the rest follows."))
    }

    @Test func weekendSuggestionWhenTheWeekendSlipped() {
        let g = 2400
        let item = judgement(water: [g, g, 0, g, g, 0, 0], sleep: [84, 84, 84], workoutDays: 3)
        #expect(all(item, \.closing).allSatisfy { $0.contains("weekend") || $0.contains("Saturday") })
    }

    // MARK: Rows and dates

    @Test func rowsCarryNumbersAndRingFill() {
        let item = judgement(water: [2400, 2400, 2400, 2400, 2400, 2400, 0], sleep: [84, 86, 79, 90], workoutDays: 4)
        let rows = WeeklyRecapCopy.rows(for: item, text: text(item))
        #expect(rows.map(\.ring) == [.water, .sleep, .workouts])
        #expect(rows[0].stat == "6 of 7 days")
        #expect(rows[0].shortNumber == "6/7")
        #expect(rows[0].caption == "of 7 days")
        #expect(rows[0].fraction == 6.0 / 7)
        #expect(rows[1].number == "85")
        #expect(rows[1].stat == "85 avg sleep score")
        #expect(rows[1].shortNumber == "85")
        #expect(rows[1].caption == "avg sleep score")
        #expect(rows[1].fraction == 1)
        #expect(rows[2].stat == "4 of 3 days")
        #expect(rows[2].shortNumber == "4/3")
        #expect(rows[2].caption == "of 3 days")
        #expect(rows[2].fraction == 4.0 / 3)
        #expect(rows.allSatisfy { $0.hasVerdict })
        #expect(rows[0].line == text(item).waterLine)
        #expect(rows[0].spokenSummary == "Water, 6 of 7 days. \(text(item).waterLine)")
    }

    @Test func sleepRowWithoutAVerdictSaysWhy() {
        // Fewer than 3 tracked nights: no number, the tracked count instead (WR4).
        let few = judgement(water: [], sleep: [95, 95], workoutDays: 0, goalDays: 1)
        let fewRows = WeeklyRecapCopy.rows(for: few, text: text(few))
        #expect(fewRows[1].number == nil)
        #expect(!fewRows[1].hasVerdict)
        #expect(fewRows[1].fraction == 0)
        #expect(fewRows[1].stat == "2 nights tracked")
        #expect(fewRows[1].shortNumber == "—")
        #expect(fewRows[1].caption == "2 nights tracked")
        #expect(fewRows[1].spokenSummary == "Sleep, 2 nights tracked. \(text(few).sleepLine)")
        #expect(fewRows[2].stat == "0 of 1 day")
        #expect(fewRows[2].shortNumber == "0/1")

        let one = judgement(water: [], sleep: [95], workoutDays: 0)
        #expect(WeeklyRecapCopy.rows(for: one, text: text(one))[1].stat == "1 night tracked")

        // No tracked night at all (no Watch).
        let none = judgement(water: [], sleep: [], workoutDays: 0)
        let noneRows = WeeklyRecapCopy.rows(for: none, text: text(none))
        #expect(noneRows[1].number == nil)
        #expect(noneRows[1].stat == "No sleep tracked")
        #expect(noneRows[1].shortNumber == "—")
        #expect(noneRows[1].caption == "not tracked")
        #expect(noneRows[0].stat == "0 of 7 days")
        #expect(noneRows[0].hasVerdict)
    }

    @Test func rowsSurviveSavingWithAndWithoutAVerdict() throws {
        let item = judgement(water: [2400, 2400, 0, 0, 0, 0, 0], sleep: [95, 95], workoutDays: 2)
        let rows = WeeklyRecapCopy.rows(for: item, text: text(item))
        let decoded = try JSONDecoder().decode([WeeklyRecap.Row].self, from: JSONEncoder().encode(rows))
        #expect(decoded == rows)
        #expect(decoded[1].number == nil)
    }

    @Test func dateRangeFollowsTheRegion() {
        // Date intervals use the system's thin spaces around the dash; compare with plain spaces.
        func range(_ week: RecapWeek, _ locale: Locale) -> String {
            WeeklyRecapCopy.dateRange(week, calendar: cal, locale: locale).replacingOccurrences(of: "\u{2009}", with: " ")
        }
        #expect(range(week, us) == "Nov 2 – 8")
        #expect(range(week, Locale(identifier: "en_GB")) == "2 – 8 Nov")
        #expect(range(RecapWeek(mondayYear: 2026, month: 10, day: 26), us) == "Oct 26 – Nov 1")
        #expect(range(week, Locale(identifier: "nl_NL")) == "2 – 8 Nov")
    }
}
