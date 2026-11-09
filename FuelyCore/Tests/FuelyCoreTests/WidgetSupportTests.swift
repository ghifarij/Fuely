import Foundation
import Testing
@testable import FuelyCore

@Suite struct WidgetTimelinePlanTests {
    let cal = Calendar.test()

    @Test func insideWindowEveryQuarterHourThenWindowEndThenMidnight() {
        let now = cal.at(2026, 11, 4, 21, 7)
        let dates = WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal)
        #expect(dates == [now, cal.at(2026, 11, 4, 21, 15), cal.at(2026, 11, 4, 21, 30),
                          cal.at(2026, 11, 4, 21, 45), cal.at(2026, 11, 4, 22), cal.at(2026, 11, 5)])
    }

    @Test func onAStepBoundaryDoesNotRepeatNow() {
        let now = cal.at(2026, 11, 4, 21, 30)
        let dates = WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal)
        #expect(dates == [now, cal.at(2026, 11, 4, 21, 45), cal.at(2026, 11, 4, 22), cal.at(2026, 11, 5)])
    }

    @Test func beforeWindowStartsAtWindowStart() {
        let now = cal.at(2026, 11, 4, 0, 1)
        let dates = WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal)
        #expect(dates.first == now)
        #expect(dates[1] == cal.at(2026, 11, 4, 5))
        #expect(dates[2] == cal.at(2026, 11, 4, 5, 15))
        #expect(dates.suffix(2) == [cal.at(2026, 11, 4, 22), cal.at(2026, 11, 5)])
        // 05:00 … 21:45 = 68 steps, + now, window end, midnight.
        #expect(dates.count == 71)
    }

    @Test func afterWindowOnlyMidnight() {
        let now = cal.at(2026, 11, 4, 22)
        #expect(WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal) == [now, cal.at(2026, 11, 5)])
    }

    @Test func invalidWindowOnlyMidnight() {
        let window = DrinkingWindow(start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 5))
        let now = cal.at(2026, 11, 4, 12)
        #expect(WidgetTimelinePlan.entryDates(from: now, window: window, calendar: cal) == [now, cal.at(2026, 11, 5)])
    }

    @Test func alignsToAnOddWindowStart() {
        let window = DrinkingWindow(start: TimeOfDay(hour: 6, minute: 10), end: TimeOfDay(hour: 7))
        let now = cal.at(2026, 11, 4, 6, 20)
        #expect(WidgetTimelinePlan.entryDates(from: now, window: window, calendar: cal)
                == [now, cal.at(2026, 11, 4, 6, 25), cal.at(2026, 11, 4, 6, 40), cal.at(2026, 11, 4, 6, 55),
                    cal.at(2026, 11, 4, 7), cal.at(2026, 11, 5)])
    }

    @Test func alwaysStrictlyIncreasing() {
        for hour in 0..<24 {
            for minute in stride(from: 0, to: 60, by: 7) {
                let dates = WidgetTimelinePlan.entryDates(from: cal.at(2026, 11, 4, hour, minute), window: .default, calendar: cal)
                #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 })
                #expect(dates.last == cal.at(2026, 11, 5))
            }
        }
    }

    @Test func midnightOnADSTDay() {
        let ny = Calendar.test("America/New_York")
        // 2026-11-01 is the US fall-back day (25 hours long).
        #expect(WidgetTimelinePlan.nextMidnight(after: ny.at(2026, 11, 1, 12), calendar: ny) == ny.at(2026, 11, 2))
    }
}

@Suite struct WidgetCopyTests {
    let cal = Calendar.test()
    var now: Date { cal.at(2026, 11, 4, 13, 30) } // Wednesday

    func summary(waterML: Int, sleep: Int?, workoutDays: Int = 0, snapshotDay: Int = 4) -> TodaySummary {
        var log = WaterLog()
        if waterML > 0 {
            log.log(WaterEntry(date: cal.at(2026, 11, 4, 9), amountML: waterML), enqueuedAt: now)
        }
        let workouts = (0..<workoutDays).map { day in
            let start = cal.at(2026, 11, 2 + day, 7)
            return WorkoutSample(start: start, end: start.addingTimeInterval(.minutes(60)), duration: .minutes(60))
        }
        let snapshot = HealthSnapshot(refreshedAt: cal.at(2026, 11, snapshotDay, 7), externalWaterML: 0,
                                      sleepScore: sleep, workouts: workouts)
        return TodaySummary.make(settings: .default, waterLog: log, snapshot: snapshot, now: now, calendar: cal)
    }

    @Test func inlineMatchesG1() {
        #expect(WidgetCopy.inline(summary(waterML: 1250, sleep: 82, workoutDays: 2)) == "💧1.2L · 😴82 · 🏃2/3")
        #expect(WidgetCopy.inlineCompact(summary(waterML: 1250, sleep: 82, workoutDays: 2)) == "💧1.2L 😴82 🏃2/3")
    }

    @Test func lineMatchesG2() {
        let s = summary(waterML: 1200, sleep: 82, workoutDays: 2)
        #expect(WidgetMetric.allCases.map { WidgetCopy.lineRow($0, in: s) } == ["💧 1.2/2.4L", "😴 82", "🏃 2/3"])
        #expect(WidgetCopy.lineEmoji(.water) == "💧")
        #expect(WidgetCopy.lineValue(.water, in: s) == "1.2/2.4L")
        #expect(WidgetCopy.lineValue(.sleep, in: summary(waterML: 1200, sleep: nil, workoutDays: 2)) == "—")
    }

    @Test func missingSleepIsADash() {
        #expect(WidgetCopy.inline(summary(waterML: 0, sleep: nil)) == "💧0.0L · 😴— · 🏃0/3")
        #expect(WidgetCopy.value(.sleep, in: summary(waterML: 0, sleep: nil)) == "—")
        #expect(WidgetCopy.detail(.sleep, in: summary(waterML: 0, sleep: nil)) == "No data")
    }

    @Test func staleSleepFromYesterdayIsADash() {
        // S7a: the snapshot is from yesterday, so the widget shows "—" today.
        let s = summary(waterML: 500, sleep: 90, snapshotDay: 3)
        #expect(WidgetCopy.value(.sleep, in: s) == "—")
        #expect(WidgetRings.fraction(.sleep, in: s) == 0)
    }

    @Test func values() {
        let s = summary(waterML: 1250, sleep: 82, workoutDays: 2)
        #expect(WidgetCopy.value(.water, in: s) == "1.2")
        #expect(WidgetCopy.value(.sleep, in: s) == "82")
        #expect(WidgetCopy.value(.workouts, in: s) == "2/3")
        #expect(WidgetCopy.detail(.water, in: s) == "On track")
        #expect(WidgetCopy.detail(.sleep, in: s) == "Goal 80")
    }

    @Test func shortPace() {
        #expect(WidgetCopy.shortPace(summary(waterML: 850, sleep: nil).water) == "350 ml behind")
        #expect(WidgetCopy.shortPace(summary(waterML: 1300, sleep: nil).water) == "On track")
        #expect(WidgetCopy.shortPace(summary(waterML: 2400, sleep: nil).water) == "Goal reached")
    }

    @Test func ringFractions() {
        let s = summary(waterML: 3600, sleep: 72, workoutDays: 4)
        #expect(WidgetRings.fraction(.water, in: s) == 1.5) // laps past 100% (W3)
        #expect(WidgetRings.fraction(.sleep, in: s) == 0.9) // 72 / goal 80
        #expect(WidgetRings.fraction(.workouts, in: s) == 1) // 4/3 caps at a closed ring
        #expect(WidgetRings.isGoalMet(.water, in: s))
        #expect(!WidgetRings.isGoalMet(.sleep, in: s))
        #expect(WidgetRings.isGoalMet(.workouts, in: s))
        #expect(WidgetRings.fraction(.sleep, in: summary(waterML: 0, sleep: 95)) == 1)
    }

    @Test func accessibility() {
        let s = summary(waterML: 1200, sleep: 82, workoutDays: 1)
        #expect(WidgetCopy.accessibility(s)
                == "Water, 1.2 liters of 2.4 liters, on track. Sleep score 82, goal 80. Workouts, 1 of 3 days this week")
        #expect(WidgetCopy.accessibility(.sleep, in: summary(waterML: 0, sleep: nil)) == "Sleep score, no data")
        #expect(WidgetCopy.addAccessibility(amountML: 250) == "Log 250 milliliters of water")
    }
}

/// Timeline and words for the in-widget amount picker (DECISIONS W6b).
@Suite struct WaterDraftWidgetTests {
    let cal = Calendar.test()

    @Test func timelineAddsAnEntryAtTheDraftExpiry() {
        let now = cal.at(2026, 11, 4, 21, 7)
        let expiry = now.addingTimeInterval(120)
        let dates = WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal, draftExpiry: expiry)
        #expect(dates == [now, expiry, cal.at(2026, 11, 4, 21, 15), cal.at(2026, 11, 4, 21, 30),
                          cal.at(2026, 11, 4, 21, 45), cal.at(2026, 11, 4, 22), cal.at(2026, 11, 5)])
    }

    @Test func timelineIgnoresAPastOrDuplicateExpiry() {
        let now = cal.at(2026, 11, 4, 21, 13)
        let plain = WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal)
        #expect(WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal, draftExpiry: now) == plain)
        #expect(WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal,
                                              draftExpiry: now.addingTimeInterval(-5)) == plain)
        #expect(WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal,
                                              draftExpiry: cal.at(2026, 11, 4, 21, 15)) == plain)
        #expect(WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal, draftExpiry: nil) == plain)
    }

    @Test func timelineWithExpiryOutsideTheWindowStaysIncreasing() {
        let now = cal.at(2026, 11, 4, 23, 59)
        let expiry = now.addingTimeInterval(120) // after midnight
        let dates = WidgetTimelinePlan.entryDates(from: now, window: .default, calendar: cal, draftExpiry: expiry)
        #expect(dates == [now, cal.at(2026, 11, 5), expiry])
    }

    @Test func pickerWords() {
        #expect(WidgetCopy.draftAmount(250) == "250")
        #expect(WidgetCopy.draftAmountWithUnit(250) == "250 ml")
        #expect(WidgetCopy.draftUnit == "ml")
        #expect(WidgetCopy.draftTitle == "Log water")
    }

    @Test func pickerVoiceOver() {
        #expect(WidgetCopy.cancelAccessibility == "Cancel")
        #expect(WidgetCopy.decreaseAccessibility == "Decrease by 50 milliliters")
        #expect(WidgetCopy.increaseAccessibility == "Increase by 50 milliliters")
        #expect(WidgetCopy.draftAmountAccessibility(250) == "250 milliliters")
        #expect(WidgetCopy.presetAccessibility(500) == "Set 500 milliliters")
        #expect(WidgetCopy.cycleAccessibility(250) == "250 milliliters. Tap for another amount")
        #expect(WidgetCopy.addAccessibility(amountML: 400) == "Log 400 milliliters of water")
        #expect(WidgetCopy.startAccessibility == "Log water, choose an amount")
    }
}
