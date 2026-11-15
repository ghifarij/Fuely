import Foundation
import Testing
@testable import FuelyCore

@Suite struct WeeklyRecapPlannerTests {
    let cal = Calendar.test()

    private func week(_ month: Int, _ day: Int, year: Int = 2026) -> RecapWeek {
        RecapWeek(mondayYear: year, month: month, day: day)
    }

    private func plan(start: Date?, now: Date, saved: [RecapWeek] = [], shown: RecapWeek? = nil,
                      calendar: Calendar? = nil) -> WeeklyRecapPlan {
        let archive = WeeklyRecapArchive(recaps: saved.map { sampleRecap(week: $0) }, lastShownWeek: shown)
        return WeeklyRecapPlanner.plan(startDate: start, archive: archive, now: now, calendar: calendar ?? cal)
    }

    // Onboarding on Wednesday 4 November 2026; the first full week is 9–15 November.
    var start: Date { cal.at(2026, 11, 4, 20, 15) }

    @Test func nothingWithoutAStartDate() {
        #expect(plan(start: nil, now: cal.at(2026, 11, 16, 9)) == WeeklyRecapPlan())
    }

    @Test func noRecapForThePartialFirstWeek() {
        // Still in the first, partial week, then in the first full week.
        #expect(plan(start: start, now: cal.at(2026, 11, 8, 23, 59)) == WeeklyRecapPlan())
        #expect(plan(start: start, now: cal.at(2026, 11, 9, 7)) == WeeklyRecapPlan())
        #expect(plan(start: start, now: cal.at(2026, 11, 15, 23, 59, 59)) == WeeklyRecapPlan())
    }

    @Test(arguments: [(16, 0), (16, 7), (18, 12), (22, 23)])
    func firstOpenOfTheNewWeekWhateverTheDay(day: Int, hour: Int) {
        // Monday 00:00, Monday morning, Wednesday, the next Sunday night.
        let result = plan(start: start, now: cal.at(2026, 11, day, hour))
        #expect(result.weeksToGenerate == [week(11, 9)])
        #expect(result.weekToPresent == week(11, 9))
    }

    @Test func alreadyShown() {
        let result = plan(start: start, now: cal.at(2026, 11, 18, 12), saved: [week(11, 9)], shown: week(11, 9))
        #expect(result == WeeklyRecapPlan())
    }

    @Test func savedButNotShownYetStillPopsUp() {
        let result = plan(start: start, now: cal.at(2026, 11, 18, 12), saved: [week(11, 9)])
        #expect(result.weeksToGenerate.isEmpty)
        #expect(result.weekToPresent == week(11, 9))
    }

    @Test func aNewWeekPopsUpAgainAfterAnEarlierOneWasShown() {
        let result = plan(start: start, now: cal.at(2026, 11, 23, 8), saved: [week(11, 9)], shown: week(11, 9))
        #expect(result.weeksToGenerate == [week(11, 16)])
        #expect(result.weekToPresent == week(11, 16))
    }

    @Test func weeksSkippedWhileAwayAreMadeQuietlyAndOnlyTheNewestPops() {
        // Last open in the week of 16 November; back on Thursday 10 December.
        let result = plan(start: start, now: cal.at(2026, 12, 10, 18), saved: [week(11, 9)], shown: week(11, 9))
        #expect(result.weeksToGenerate == [week(11, 16), week(11, 23), week(11, 30)])
        #expect(result.weekToPresent == week(11, 30))
    }

    @Test func aGapInTheSavedWeeksIsFilled() {
        let result = plan(start: start, now: cal.at(2026, 12, 10, 18), saved: [week(11, 9), week(11, 23)],
                          shown: week(11, 30))
        #expect(result.weeksToGenerate == [week(11, 16), week(11, 30)])
        #expect(result.weekToPresent == nil)
    }

    @Test func startDateInTheMiddleOfAWeekSkipsThatWeek() {
        // Tuesday 00:00 is already too late for that week.
        let tuesday = cal.at(2026, 11, 10)
        #expect(plan(start: tuesday, now: cal.at(2026, 11, 16, 9)) == WeeklyRecapPlan())
        #expect(plan(start: tuesday, now: cal.at(2026, 11, 23, 9)).weeksToGenerate == [week(11, 16)])
        // Sunday night: the next day's week counts.
        #expect(plan(start: cal.at(2026, 11, 8, 23, 30), now: cal.at(2026, 11, 16, 9)).weeksToGenerate == [week(11, 9)])
    }

    @Test func startDateOnAMondayCountsThatWeek() {
        // Any time on Monday: the week begins on the start day.
        for hour in [0, 9, 23] {
            let result = plan(start: cal.at(2026, 11, 9, hour, 30), now: cal.at(2026, 11, 16, 9))
            #expect(result.weeksToGenerate == [week(11, 9)])
            #expect(result.weekToPresent == week(11, 9))
        }
    }

    @Test func atMostTheTwelveNewestWeeks() {
        let result = plan(start: cal.at(2026, 1, 5, 10), now: cal.at(2026, 11, 16, 9))
        #expect(result.weeksToGenerate.count == 12)
        #expect(result.weeksToGenerate.first == week(8, 24))
        #expect(result.weeksToGenerate.last == week(11, 9))
        #expect(result.weeksToGenerate == result.weeksToGenerate.sorted())
        #expect(result.weekToPresent == week(11, 9))
    }

    @Test func nowBeforeTheStartDateDoesNothing() {
        #expect(plan(start: start, now: cal.at(2026, 10, 1, 9)) == WeeklyRecapPlan())
    }

    @Test func acrossTheYearBoundary() {
        let result = plan(start: cal.at(2026, 12, 21, 9), now: cal.at(2027, 1, 5, 9))
        #expect(result.weeksToGenerate == [week(12, 21), week(12, 28)])
        #expect(result.weekToPresent == week(12, 28))
    }

    // MARK: DST and time zones

    @Test func autumnDSTChange() {
        // New York falls back on Sunday 1 November 2026: that week is an hour longer.
        let ny = Calendar.test("America/New_York")
        let result = plan(start: ny.at(2026, 10, 19, 8), now: ny.at(2026, 11, 2, 0, 30), calendar: ny)
        #expect(result.weeksToGenerate == [week(10, 19), week(10, 26)])
        #expect(result.weekToPresent == week(10, 26))
        // The last minutes of the long Sunday still belong to the old week.
        #expect(plan(start: ny.at(2026, 10, 19, 8), now: ny.at(2026, 11, 1, 23, 59), calendar: ny).weeksToGenerate
            == [week(10, 19)])
    }

    @Test func springDSTChange() {
        // Amsterdam springs forward on Sunday 29 March 2026: that week is an hour shorter.
        let ams = Calendar.test("Europe/Amsterdam")
        let start = ams.at(2026, 3, 16, 12)
        #expect(plan(start: start, now: ams.at(2026, 3, 29, 23, 30), calendar: ams).weeksToGenerate == [week(3, 16)])
        let result = plan(start: start, now: ams.at(2026, 3, 30, 0, 5), calendar: ams)
        #expect(result.weeksToGenerate == [week(3, 16), week(3, 23)])
        #expect(result.weekToPresent == week(3, 23))
    }

    @Test func theCalendarsTimeZoneDecidesWhenTheWeekEnds() {
        // The same instant: Monday 01:00 in Bangkok, still Sunday morning in Los Angeles.
        let la = Calendar.test("America/Los_Angeles")
        let now = cal.at(2026, 11, 16, 1)
        #expect(la.component(.weekday, from: now) == 1)
        #expect(plan(start: start, now: now).weekToPresent == week(11, 9))
        #expect(plan(start: start, now: now, calendar: la) == WeeklyRecapPlan())
    }

    @Test func aSundayFirstCalendarStillUsesMondayWeeks() {
        var sundayFirst = Calendar.test()
        sundayFirst.firstWeekday = 1
        // Sunday 15 November belongs to the week that started on Monday the 9th.
        #expect(plan(start: start, now: cal.at(2026, 11, 15, 12), calendar: sundayFirst) == WeeklyRecapPlan())
        #expect(plan(start: start, now: cal.at(2026, 11, 16, 12), calendar: sundayFirst).weekToPresent == week(11, 9))
    }
}

@Suite struct WeeklyRecapStartTests {
    let cal = Calendar.test()

    @Test func storedDateWins() {
        var settings = FuelySettings(hasCompletedOnboarding: true)
        settings.onboardingCompletedAt = cal.at(2026, 11, 4, 20, 15)
        var log = WaterLog()
        log.log(WaterEntry(date: cal.at(2026, 10, 1, 9), amountML: 250), enqueuedAt: cal.at(2026, 10, 1, 9))
        #expect(WeeklyRecapStart.startDate(settings: settings, waterLog: log, calendar: cal) == cal.at(2026, 11, 4, 20, 15))
    }

    @Test func existingInstallUsesTheDayOfTheEarliestFuelyDrink() {
        var log = WaterLog()
        for (day, hour) in [(5, 14), (3, 21), (4, 8)] {
            log.log(WaterEntry(date: cal.at(2026, 11, day, hour), amountML: 250), enqueuedAt: cal.at(2026, 11, day, hour))
        }
        let settings = FuelySettings(hasCompletedOnboarding: true)
        #expect(WeeklyRecapStart.startDate(settings: settings, waterLog: log, calendar: cal) == cal.at(2026, 11, 3))
    }

    @Test func nothingToGoOn() {
        #expect(WeeklyRecapStart.startDate(settings: .default, waterLog: WaterLog(), calendar: cal) == nil)
    }

    @Test func completingOnboardingStampsTheDateOnce() throws {
        var settings = FuelySettings.default
        #expect(settings.onboardingCompletedAt == nil)
        settings.completeOnboarding(at: cal.at(2026, 11, 4, 20, 15))
        #expect(settings.hasCompletedOnboarding)
        #expect(settings.onboardingCompletedAt == cal.at(2026, 11, 4, 20, 15))
        settings.completeOnboarding(at: cal.at(2026, 12, 1, 9))
        #expect(settings.onboardingCompletedAt == cal.at(2026, 11, 4, 20, 15))

        let store = makeTempStore()
        try store.saveSettings(settings)
        #expect(try store.settings() == settings)
    }

    @Test func settingsFileWithoutTheDateStillLoads() throws {
        let store = makeTempStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 1, "waterGoalML": 2100, "hasCompletedOnboarding": true}"#.utf8)
            .write(to: store.url(for: .settings))
        let settings = try store.settings()
        #expect(settings.hasCompletedOnboarding)
        #expect(settings.onboardingCompletedAt == nil)
        #expect(settings.waterGoalML == 2100)
    }
}
