import Foundation
import Testing
@testable import FuelyCore

@Suite struct WaterGoalTests {
    @Test(arguments: [(68.0, 2400), (70.0, 2500), (57.1, 2000), (80.0, 2800)])
    func suggestedGoalIsWeightTimes35RoundedTo100(weight: Double, expected: Int) {
        #expect(WaterGoal.suggestedML(weightKG: weight) == expected)
    }

    @Test func suggestedGoalForNonPositiveWeightIsZero() {
        #expect(WaterGoal.suggestedML(weightKG: 0) == 0)
        #expect(WaterGoal.suggestedML(weightKG: -5) == 0)
    }
}

@Suite struct WaterPaceTests {
    let cal = Calendar.test()
    let window = DrinkingWindow.default // 05:00–22:00, 17 h

    @Test func elapsedFractionAcrossTheDay() {
        #expect(WaterPace.elapsedFraction(of: window, at: cal.at(2026, 11, 8, 3), calendar: cal) == 0)
        #expect(WaterPace.elapsedFraction(of: window, at: cal.at(2026, 11, 8, 5), calendar: cal) == 0)
        #expect(WaterPace.elapsedFraction(of: window, at: cal.at(2026, 11, 8, 13, 30), calendar: cal) == 0.5)
        #expect(WaterPace.elapsedFraction(of: window, at: cal.at(2026, 11, 8, 22), calendar: cal) == 1)
        #expect(WaterPace.elapsedFraction(of: window, at: cal.at(2026, 11, 8, 23, 59), calendar: cal) == 1)
    }

    @Test func expectedIntakeIsGoalTimesElapsedFraction() {
        let expected = WaterPace.expectedIntakeML(goalML: 2400, window: window, at: cal.at(2026, 11, 8, 13, 30), calendar: cal)
        #expect(expected == 1200)
    }

    @Test func statusBehindOnTrackAndGoalMet() {
        let now = cal.at(2026, 11, 8, 13, 30)
        func status(_ total: Int) -> WaterPaceStatus {
            WaterPace.progress(totalML: total, goalML: 2400, window: window, at: now, calendar: cal).status
        }
        #expect(status(1000) == .behind)
        #expect(status(1200) == .onTrack)
        #expect(status(2400) == .goalMet)
    }

    @Test func progressCanExceed100Percent() {
        let p = WaterPace.progress(totalML: 3000, goalML: 2400, window: window, at: cal.at(2026, 11, 8, 12), calendar: cal)
        #expect(p.fraction == 1.25)
        #expect(p.status == .goalMet)
    }

    @Test func beforeTheWindowNobodyIsBehind() {
        let p = WaterPace.progress(totalML: 0, goalML: 2400, window: window, at: cal.at(2026, 11, 8, 4), calendar: cal)
        #expect(p.status == .onTrack)
        #expect(p.expectedML == 0)
    }

    @Test func zeroGoalCountsAsMetWithoutDividingByZero() {
        let p = WaterPace.progress(totalML: 0, goalML: 0, window: window, at: cal.at(2026, 11, 8, 12), calendar: cal)
        #expect(p.status == .goalMet)
        #expect(p.fraction == 0)
    }

    @Test func invalidWindowNeverMarksBehind() {
        let bad = DrinkingWindow(start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 5))
        #expect(!bad.isValid)
        let p = WaterPace.progress(totalML: 0, goalML: 2400, window: bad, at: cal.at(2026, 11, 8, 23), calendar: cal)
        #expect(p.status == .onTrack)
    }

    @Test func customWindow() {
        let w = DrinkingWindow(start: TimeOfDay(hour: 7, minute: 30), end: TimeOfDay(hour: 19, minute: 30))
        #expect(WaterPace.elapsedFraction(of: w, at: cal.at(2026, 11, 8, 10, 30), calendar: cal) == 0.25)
    }

    @Test func dayTotalCountsOnlyTheCalendarDayOfNow() {
        let now = cal.at(2026, 11, 8, 12)
        let entries = [
            WaterEntry(date: cal.at(2026, 11, 7, 23, 59), amountML: 500),
            WaterEntry(date: cal.at(2026, 11, 8, 0, 0), amountML: 300),
            WaterEntry(date: cal.at(2026, 11, 8, 11), amountML: 250, source: .external(name: "WaterMinder")),
            WaterEntry(date: cal.at(2026, 11, 9, 0, 0), amountML: 700),
        ]
        #expect(WaterPace.totalML(of: entries, onDayOf: now, calendar: cal) == 550)
        #expect(WaterPace.totalML(of: [], onDayOf: now, calendar: cal) == 0)
    }

    @Test func dayTotalDependsOnTheInjectedTimeZone() {
        let utc = Calendar.test("UTC")
        let instant = cal.at(2026, 11, 8, 3) // 2026-11-07 20:00 UTC
        let entries = [WaterEntry(date: instant, amountML: 400)]
        #expect(WaterPace.totalML(of: entries, onDayOf: cal.at(2026, 11, 8, 12), calendar: cal) == 400)
        #expect(WaterPace.totalML(of: entries, onDayOf: utc.at(2026, 11, 8, 12), calendar: utc) == 0)
    }

    @Test func springForwardDayUsesRealElapsedTime() {
        // 2026-03-08 New York: 02:00 -> 03:00. Window 01:00–21:00 is 19 real hours.
        let ny = Calendar.test("America/New_York")
        let w = DrinkingWindow(start: TimeOfDay(hour: 1), end: TimeOfDay(hour: 21))
        // 01:00 EST -> 11:30 EDT = 9.5 real hours = half of 19.
        #expect(WaterPace.elapsedFraction(of: w, at: ny.at(2026, 3, 8, 11, 30), calendar: ny) == 0.5)
    }

    @Test func entryHelpers() {
        #expect(WaterEntry(date: .distantPast, amountML: 1).isDeletable)
        #expect(!WaterEntry(date: .distantPast, amountML: 1, source: .external(name: "X")).isDeletable)
        #expect(WaterLogging.quickAddAmountsML == [150, 250, 500])
        #expect(WaterLogging.defaultWidgetAmountML == 250)
    }

    // MARK: DST (America/New_York: 2026-03-08 springs forward 02:00 -> 03:00, 2026-11-01 falls back 02:00 -> 01:00)

    let ny = Calendar.test("America/New_York")

    @Test func defaultWindowIs17RealHoursOnBothTransitionDays() throws {
        for (month, day) in [(3, 8), (11, 1)] {
            let interval = try #require(window.interval(on: ny.at(2026, month, day, 12), calendar: ny))
            #expect(interval.duration == .hours(17))
            #expect(WaterPace.elapsedFraction(of: window, at: ny.at(2026, month, day, 13, 30), calendar: ny) == 0.5)
            #expect(WaterPace.expectedIntakeML(goalML: 1700, window: window, at: ny.at(2026, month, day, 6), calendar: ny) == 100)
        }
    }

    @Test func fallBackWindowStartingInTheRepeatedHourUsesItsFirstOccurrence() throws {
        // 01:00 happens twice; the window starts at the first (EDT) one: 01:00 EDT -> 21:00 EST = 21 h.
        let w = DrinkingWindow(start: TimeOfDay(hour: 1), end: TimeOfDay(hour: 21))
        let interval = try #require(w.interval(on: ny.at(2026, 11, 1, 12), calendar: ny))
        #expect(interval.start == Date(timeIntervalSince1970: 1_793_509_200)) // 2026-11-01 05:00 UTC
        #expect(interval.duration == .hours(21))
        #expect(WaterPace.elapsedFraction(of: w, at: ny.at(2026, 11, 1, 10, 30), calendar: ny) == 0.5)
    }

    @Test func springForwardWindowStartingInTheSkippedHourStartsAnHourLater() throws {
        // 02:30 doesn't exist; it resolves to 03:30 EDT. 03:30 -> 22:00 = 18.5 h.
        let w = DrinkingWindow(start: TimeOfDay(hour: 2, minute: 30), end: TimeOfDay(hour: 22))
        let interval = try #require(w.interval(on: ny.at(2026, 3, 8, 12), calendar: ny))
        #expect(interval.start == Date(timeIntervalSince1970: 1_772_955_000)) // 2026-03-08 07:30 UTC
        #expect(interval.duration == .hours(18.5))
        #expect(!w.contains(ny.at(2026, 3, 8, 1, 59), calendar: ny))
        #expect(w.contains(interval.start, calendar: ny))
    }

    @Test func windowContainsOnTransitionDays() {
        for (month, day) in [(3, 8), (11, 1)] {
            #expect(!window.contains(ny.at(2026, month, day, 4, 59), calendar: ny))
            #expect(window.contains(ny.at(2026, month, day, 5), calendar: ny))
            #expect(window.contains(ny.at(2026, month, day, 21, 59), calendar: ny))
            #expect(!window.contains(ny.at(2026, month, day, 22), calendar: ny))
        }
        // The repeated 01:30 (both EDT and EST) is before the window.
        let firstOneThirty = ny.at(2026, 11, 1, 1, 30)
        #expect(!window.contains(firstOneThirty, calendar: ny))
        #expect(!window.contains(firstOneThirty + .hours(1), calendar: ny))
    }

    @Test func todaySummaryCountsTheWholeLongAndShortDays() {
        // Fall-back day is 25 h long, spring-forward day 23 h.
        for (month, day, length) in [(11, 1, 25.0), (3, 8, 23.0)] {
            let start = ny.startOfDay(for: ny.at(2026, month, day, 12))
            var log = WaterLog()
            for (offset, amount) in [(-60.0, 900), (30 * 60.0, 100), (length * 3600 - 60, 200), (length * 3600, 800)] {
                log.log(WaterEntry(date: start + offset, amountML: amount), enqueuedAt: start)
            }
            let summary = TodaySummary.make(settings: FuelySettings(waterGoalML: 1700), waterLog: log, snapshot: nil,
                                            now: ny.at(2026, month, day, 13, 30), calendar: ny)
            #expect(summary.fuelyWaterML == 300, "day \(month)/\(day)")
            #expect(summary.water.expectedML == 850)
            #expect(summary.water.status == .behind)
        }
    }
}
