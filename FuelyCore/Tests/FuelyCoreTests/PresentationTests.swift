import Foundation
import Testing
@testable import FuelyCore

@Suite struct FuelyFormatTests {
    @Test(arguments: [(0, "0 ml"), (150, "150 ml"), (999, "999 ml"), (1000, "1 L"), (1200, "1.2 L"),
                      (1250, "1.25 L"), (1205, "1.21 L"), (2004, "2 L"), (2400, "2.4 L"), (-50, "0 ml")])
    func water(ml: Int, expected: String) {
        #expect(FuelyFormat.water(ml) == expected)
    }

    @Test(arguments: [(0, "0.0"), (850, "0.8"), (1200, "1.2"), (2390, "2.3"), (2400, "2.4"), (12_345, "12.3")])
    func compactLitresRoundsDown(ml: Int, expected: String) {
        #expect(FuelyFormat.compactLitres(ml) == expected)
    }

    @Test func spokenWater() {
        #expect(FuelyFormat.waterSpoken(850) == "850 milliliters")
        #expect(FuelyFormat.waterSpoken(1000) == "1 liter")
        #expect(FuelyFormat.waterSpoken(1250) == "1.25 liters")
    }

    @Test func percentCanExceed100() {
        #expect(FuelyFormat.percent(0.524) == "52%")
        #expect(FuelyFormat.percent(1.3) == "130%")
        #expect(FuelyFormat.percent(-0.2) == "0%")
        #expect(FuelyFormat.percent(.nan) == "0%")
    }

    @Test func missingSleepScoreIsADashNeverZero() {
        #expect(FuelyFormat.sleepScore(nil) == "—")
        #expect(FuelyFormat.sleepScore(82) == "82")
        #expect(FuelyFormat.sleepScore(0) == "0")
    }

    @Test func workoutDays() {
        let cal = Calendar.test()
        let now = cal.at(2026, 11, 4, 12) // Wednesday
        let week = WorkoutAggregation.week(
            containing: now,
            samples: [WorkoutSample(start: cal.at(2026, 11, 2, 7), end: cal.at(2026, 11, 2, 8), duration: .minutes(60))],
            goal: .default, calendar: cal)
        #expect(FuelyFormat.workoutDays(week) == "1/3")
    }

    @Test func count() {
        #expect(FuelyFormat.count(1, "day") == "1 day")
        #expect(FuelyFormat.count(3, "day") == "3 days")
    }
}

@Suite struct TodayCopyTests {
    let cal = Calendar.test()

    /// 13:30 on Wednesday 2026-11-04: half of the 05:00–22:00 window, so a 2400 ml goal expects 1200.
    var now: Date { cal.at(2026, 11, 4, 13, 30) }

    func summary(waterML: Int, sleep: Int?, workoutDays: Int = 0, issue: HealthSyncIssue? = nil) -> TodaySummary {
        var log = WaterLog()
        if waterML > 0 {
            log.log(WaterEntry(date: cal.at(2026, 11, 4, 9), amountML: waterML), enqueuedAt: now)
        }
        if let issue, let job = log.nextPending() { log.recordFailure(job.id, issue: issue) }
        let workouts = (0..<workoutDays).map { day in
            let start = cal.at(2026, 11, 2 + day, 7)
            return WorkoutSample(start: start, end: start.addingTimeInterval(.minutes(60)), duration: .minutes(60))
        }
        let snapshot = HealthSnapshot(refreshedAt: now, externalWaterML: 0, sleepScore: sleep, workouts: workouts)
        return TodaySummary.make(settings: .default, waterLog: log, snapshot: snapshot, now: now, calendar: cal)
    }

    @Test func headlineCoversEverySleepAndWaterCombination() {
        #expect(TodayCopy.headline(for: summary(waterML: 1300, sleep: 85)) == "Sleep ✓ and hydrated — you're set for a sharp day.")
        #expect(TodayCopy.headline(for: summary(waterML: 1300, sleep: 85, workoutDays: 3)).contains("workout goal is done"))
        #expect(TodayCopy.headline(for: summary(waterML: 500, sleep: 85)).hasPrefix("Well rested"))
        #expect(TodayCopy.headline(for: summary(waterML: 1300, sleep: 60)).hasPrefix("Short night"))
        #expect(TodayCopy.headline(for: summary(waterML: 500, sleep: 60)).hasPrefix("Go easy"))
        #expect(TodayCopy.headline(for: summary(waterML: 1300, sleep: nil)) == "Hydrated and on track. Keep it flowing.")
        #expect(TodayCopy.headline(for: summary(waterML: 500, sleep: nil)) == "A glass of water now gets you back on pace.")
    }

    @Test func paceText() {
        #expect(TodayCopy.paceText(summary(waterML: 1300, sleep: nil).water) == "On track")
        #expect(TodayCopy.paceText(summary(waterML: 2400, sleep: nil).water) == "Goal reached")
        #expect(TodayCopy.paceText(summary(waterML: 850, sleep: nil).water) == "350 ml behind pace")
    }

    @Test func catchUpRoundsUpTo10ml() {
        let water = WaterPace.progress(totalML: 1000, goalML: 2400, window: .default, at: cal.at(2026, 11, 4, 13, 31), calendar: cal)
        // expected ≈ 1202.35 → gap 202.35 → 210
        #expect(TodayCopy.catchUpML(water) == 210)
        #expect(TodayCopy.catchUpML(summary(waterML: 1300, sleep: nil).water) == 0)
    }

    @Test func waterAccessibility() {
        #expect(TodayCopy.waterAccessibility(summary(waterML: 1200, sleep: nil).water)
                == "Water, 1.2 liters of 2.4 liters, 50 percent")
        #expect(TodayCopy.waterAccessibility(summary(waterML: 3000, sleep: nil).water)
                == "Water, 3 liters of 2.4 liters, 125 percent")
    }

    @Test func sleepDetailAndNoDataHint() {
        #expect(TodayCopy.sleepDetail(score: nil, goal: 80) == "Wear your Watch to bed to get a sleep score.")
        #expect(TodayCopy.sleepDetail(score: 82, goal: 80) == "Goal 80 · Reached")
        #expect(TodayCopy.sleepDetail(score: 70, goal: 80) == "Goal 80")
        #expect(TodayCopy.sleepAccessibility(score: nil, goal: 80).contains("no data"))
    }

    @Test func workoutDetail() {
        let one = summary(waterML: 0, sleep: nil, workoutDays: 1).workoutWeek
        #expect(TodayCopy.workoutDetail(one, now: now, calendar: cal) == "2 to go · 5 days left")
        let done = summary(waterML: 0, sleep: nil, workoutDays: 3).workoutWeek
        #expect(TodayCopy.workoutDetail(done, now: now, calendar: cal) == "Weekly goal reached")
        let sunday = cal.at(2026, 11, 8, 9)
        let week = WorkoutAggregation.week(containing: sunday, samples: [], goal: .default, calendar: cal)
        #expect(TodayCopy.workoutDetail(week, now: sunday, calendar: cal) == "3 to go · 1 day left")
    }

    @Test func workoutToday() {
        let three = summary(waterML: 0, sleep: nil, workoutDays: 3).workoutWeek // Mon, Tue, Wed 60 min
        #expect(TodayCopy.workoutToday(three, now: now, calendar: cal) == "Today 60 min ✓")
        let none = summary(waterML: 0, sleep: nil).workoutWeek
        #expect(TodayCopy.workoutToday(none, now: now, calendar: cal) == "Today 0 of 50 min")
    }

    @Test func syncHint() {
        #expect(TodayCopy.syncHint(nil) == nil)
        #expect(TodayCopy.syncHint(.notAuthorized)?.title == "Health access off")
        for issue in [HealthSyncIssue.locked, .unavailable, .other] {
            #expect(TodayCopy.syncHint(issue) != nil)
        }
        #expect(summary(waterML: 250, sleep: nil, issue: .notAuthorized).syncIssue == .notAuthorized)
    }
}

@Suite struct QuickLogSupportTests {
    @Test(arguments: [("250", 250), (" 330 ", 330), ("400ml", 400), ("400 ML", 400), ("1", 1), ("5000", 5000)])
    func validCustomAmounts(text: String, expected: Int) {
        #expect(WaterLogging.parseCustomAmount(text) == expected)
    }

    @Test(arguments: ["", "0", "5001", "-5", "2.5", "abc", "12a", "٣٠٠", "99999999999999999999"])
    func invalidCustomAmounts(text: String) {
        #expect(WaterLogging.parseCustomAmount(text) == nil)
    }

    @Test func undoCandidateIsTodaysLatestEntryOnly() {
        let cal = Calendar.test()
        let now = cal.at(2026, 11, 8, 10)
        var log = WaterLog()
        #expect(log.undoCandidate(now: now, calendar: cal) == nil)
        let yesterday = WaterEntry(date: cal.at(2026, 11, 7, 21), amountML: 250)
        log.log(yesterday, enqueuedAt: yesterday.date)
        #expect(log.undoCandidate(now: now, calendar: cal) == nil)
        let first = WaterEntry(date: cal.at(2026, 11, 8, 7), amountML: 150)
        let second = WaterEntry(date: cal.at(2026, 11, 8, 9), amountML: 500)
        log.log(second, enqueuedAt: second.date)
        log.log(first, enqueuedAt: first.date)
        #expect(log.undoCandidate(now: now, calendar: cal)?.id == second.id)
    }

    @Test func deepLinkRoundTrip() {
        for link in FuelyDeepLink.allCases {
            #expect(FuelyDeepLink(url: link.url) == link)
        }
        #expect(FuelyDeepLink.quickLog.url.absoluteString == "fuely://quick-log")
        #expect(FuelyDeepLink(url: URL(string: "https://quick-log")!) == nil)
        #expect(FuelyDeepLink(url: URL(string: "fuely://nope")!) == nil)
    }
}
