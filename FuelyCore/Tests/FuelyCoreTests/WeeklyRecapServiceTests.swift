import Foundation
import Testing
@testable import FuelyCore

@Suite struct WeeklyRecapServiceTests {
    let cal = Calendar.test()
    let store = makeTempStore()
    let us = Locale(identifier: "en_US")

    private func week(_ month: Int, _ day: Int) -> RecapWeek {
        RecapWeek(mondayYear: 2026, month: month, day: day)
    }

    private func service(_ loader: any WeekHistoryLoading) -> WeeklyRecapService {
        WeeklyRecapService(store: store, loader: loader, calendar: cal, locale: us)
    }

    /// Onboarding finished on Wednesday 4 November 2026.
    private func onboard(at date: Date? = nil) throws {
        let date = date ?? cal.at(2026, 11, 4, 20, 15)
        try store.updateSettings { $0.completeOnboarding(at: date) }
    }

    private func strongWeek(_ week: RecapWeek, settings: FuelySettings = .default) -> WeekHistory {
        makeWeekHistory(week, calendar: cal, settings: settings,
                        water: [2400, 2500, 2400, 2600, 2400, 2400, 900],
                        sleep: [84, nil, 88, 81, nil, 79, 90], workoutMinutes: [60, 0, 55, 0, 0, 70, 0])
    }

    @Test func nothingBeforeOnboarding() async throws {
        let loader = FakeWeekLoader(calendar: cal)
        #expect(try await service(loader).refresh(now: cal.at(2026, 11, 16, 9)) == nil)
        #expect(loader.loaded.isEmpty)
        #expect(try store.weeklyRecaps().recaps.isEmpty)
        #expect(try store.settings().onboardingCompletedAt == nil)
    }

    @Test func firstFullWeekPopsUpOnceOnTheFirstOpenOfTheNextWeek() async throws {
        try onboard()
        let loader = FakeWeekLoader(calendar: cal)
        loader.set(strongWeek(week(11, 9)))
        let service = service(loader)

        // The partial first week and the running week: nothing.
        #expect(try await service.refresh(now: cal.at(2026, 11, 7, 9)) == nil)
        #expect(try await service.refresh(now: cal.at(2026, 11, 12, 9)) == nil)
        #expect(loader.loaded.isEmpty)

        let opened = cal.at(2026, 11, 18, 7, 30)
        let recap = try #require(try await service.refresh(now: opened))
        #expect(recap.week == week(11, 9))
        #expect(recap.createdAt == opened)
        #expect(recap.mood == .allStrong)
        #expect(recap.row(.water)?.stat == "6 of 7 days")
        #expect(recap.row(.sleep)?.stat == "84 avg sleep score")
        #expect(recap.row(.workouts)?.stat == "3 of 3 days")
        #expect(try store.weeklyRecaps().recaps == [recap])

        // Not marked yet (e.g. the app was closed first): offered again, without recomputing.
        #expect(try await service.refresh(now: cal.at(2026, 11, 18, 12)) == recap)
        #expect(loader.loaded == [week(11, 9)])

        try service.markShown(recap)
        #expect(try await service.refresh(now: cal.at(2026, 11, 19, 12)) == nil)
        #expect(try await service.refresh(now: cal.at(2026, 11, 22, 23)) == nil)
        #expect(loader.loaded == [week(11, 9)])
    }

    @Test func savedRecapIsFrozen() async throws {
        try onboard()
        let loader = FakeWeekLoader(calendar: cal)
        loader.set(strongWeek(week(11, 9)))
        let service = service(loader)
        let recap = try #require(try await service.refresh(now: cal.at(2026, 11, 16, 9)))
        try service.markShown(recap)

        // Goals change and Health data arrives late: the saved recap stays as it was.
        try store.updateSettings { $0.waterGoalML = 5000; $0.sleepGoalScore = 95 }
        loader.set(makeWeekHistory(week(11, 9), calendar: cal, settings: try store.settings()))
        loader.set(strongWeek(week(11, 16), settings: try store.settings()))
        let next = try #require(try await service.refresh(now: cal.at(2026, 11, 23, 9)))
        #expect(try service.recap(forWeekContaining: cal.at(2026, 11, 12, 15)) == recap)
        // The new week uses the goals in force now.
        #expect(next.week == week(11, 16))
        #expect(next.numbers.waterGoalML == 5000)
        #expect(next.numbers.sleepGoal == 95)
        #expect(next.numbers.waterDaysReached == 0)
        #expect(loader.loaded == [week(11, 9), week(11, 16)])
    }

    @Test func skippedWeeksAreMadeQuietlyAndOnlyTheNewestIsReturned() async throws {
        try onboard()
        let loader = FakeWeekLoader(calendar: cal)
        let service = service(loader)
        let recap = try #require(try await service.refresh(now: cal.at(2026, 12, 10, 18)))
        #expect(recap.week == week(11, 30))
        #expect(loader.loaded == [week(11, 9), week(11, 16), week(11, 23), week(11, 30)])
        #expect(try store.weeklyRecaps().recaps.map(\.week) == loader.loaded)

        try service.markShown(recap)
        #expect(try await service.refresh(now: cal.at(2026, 12, 11, 8)) == nil)
        // Every saved week can be reopened from the Week view (WR9).
        #expect(try service.recap(forWeekContaining: cal.at(2026, 11, 22, 23, 59))?.week == week(11, 16))
        #expect(try service.recap(forWeekContaining: cal.at(2026, 11, 5, 12)) == nil)
        #expect(try service.recap(forWeekContaining: cal.at(2026, 12, 10, 18)) == nil)
    }

    @Test func emptyWeekStillGetsARecap() async throws {
        try onboard()
        let recap = try #require(try await service(FakeWeekLoader(calendar: cal)).refresh(now: cal.at(2026, 11, 16, 9)))
        #expect(recap.mood == .notEnoughData)
        #expect(recap.row(.sleep)?.line == "No sleep tracked.")
        #expect(recap.row(.sleep)?.number == nil)
        #expect(recap.row(.sleep)?.shortNumber == "—")
        #expect(recap.row(.sleep)?.stat == "No sleep tracked")
        #expect(recap.row(.water)?.line == "No water logged.")
        #expect(recap.closingIsSuggestion)
    }

    @Test func aWeekHealthKitCouldNotBeReadForIsLeftForLater() async throws {
        try onboard()
        let loader = FakeWeekLoader(calendar: cal)
        loader.set(strongWeek(week(11, 16)))
        loader.setIssue(.locked, for: week(11, 16))
        let service = service(loader)

        // The older week is made, the newest can't be: nothing pops up, nothing wrong is frozen.
        #expect(try await service.refresh(now: cal.at(2026, 11, 23, 6)) == nil)
        #expect(try store.weeklyRecaps().recaps.map(\.week) == [week(11, 9)])
        #expect(try store.weeklyRecaps().lastShownWeek == nil)

        loader.setIssue(nil, for: week(11, 16))
        let recap = try #require(try await service.refresh(now: cal.at(2026, 11, 23, 9)))
        #expect(recap.week == week(11, 16))
        #expect(recap.mood == .allStrong)
        #expect(loader.loaded == [week(11, 9), week(11, 16), week(11, 16)])
    }

    @Test func keepsTheLatestTwelve() async throws {
        try onboard(at: cal.at(2026, 1, 5, 9))
        let loader = FakeWeekLoader(calendar: cal)
        let service = service(loader)
        let first = try #require(try await service.refresh(now: cal.at(2026, 11, 16, 9)))
        #expect(first.week == week(11, 9))
        #expect(loader.loaded.count == 12)
        #expect(try store.weeklyRecaps().recaps.first?.week == week(8, 24))
        try service.markShown(first)

        let second = try #require(try await service.refresh(now: cal.at(2026, 11, 24, 9)))
        #expect(second.week == week(11, 16))
        let archive = try store.weeklyRecaps()
        #expect(archive.recaps.count == 12)
        #expect(archive.recaps.first?.week == week(8, 31))
        #expect(loader.loaded.count == 13)
    }

    // MARK: Start date (WR10)

    @Test func existingInstallStartsOnTheDayOfItsEarliestDrinkAndKeepsThatDate() async throws {
        // Onboarding was finished before the date was saved.
        try store.updateSettings { $0.hasCompletedOnboarding = true }
        try store.logWater(amountML: 300, at: cal.at(2026, 11, 10, 14))
        try store.logWater(amountML: 250, at: cal.at(2026, 11, 9, 8, 30))
        let loader = FakeWeekLoader(calendar: cal)
        let service = service(loader)

        let recap = try #require(try await service.refresh(now: cal.at(2026, 11, 16, 9)))
        #expect(recap.week == week(11, 9))
        #expect(try store.settings().onboardingCompletedAt == cal.at(2026, 11, 9))

        // The local log is pruned later; the start date doesn't move.
        try store.updateWaterLog { $0 = WaterLog() }
        try store.logWater(amountML: 250, at: cal.at(2026, 11, 25, 8))
        #expect(try service.resolveStartDate(now: cal.at(2026, 11, 26, 9)) == cal.at(2026, 11, 9))
    }

    @Test func existingInstallWithoutDrinksStartsNow() async throws {
        try store.updateSettings { $0.hasCompletedOnboarding = true }
        let loader = FakeWeekLoader(calendar: cal)
        let service = service(loader)
        let now = cal.at(2026, 11, 16, 9)
        #expect(try await service.refresh(now: now) == nil)
        #expect(try store.settings().onboardingCompletedAt == now)
        #expect(loader.loaded.isEmpty)
        // Started on a Monday: that week gets a recap once it is over.
        #expect(try await service.refresh(now: cal.at(2026, 11, 23, 9))?.week == week(11, 16))
    }

    // MARK: With the real loader

    @Test func worksWithTheRealWeekHistoryLoader() async throws {
        try onboard()
        try store.updateSettings { $0.workoutGoal = WorkoutGoal(minMinutesPerDay: 30, daysPerWeek: 2) }
        let health = FakeHealthKit()
        // Invented week: the goal (2400 ml) on five days, three workouts.
        health.setExternalWater((9...13).map {
            WaterEntry(date: cal.at(2026, 11, $0, 12), amountML: 2400 + $0 * 10, source: .external(name: "Health"))
        })
        health.setWorkouts([10, 12, 14].map {
            WorkoutSample(start: cal.at(2026, 11, $0, 7), end: cal.at(2026, 11, $0, 8), duration: .minutes(45))
        })
        let loader = WeekHistoryLoader(store: store, healthKit: health, calendar: cal)
        let recap = try #require(try await service(loader).refresh(now: cal.at(2026, 11, 16, 9)))
        #expect(recap.week == week(11, 9))
        #expect(recap.mood == .allStrong)
        #expect(recap.numbers.waterDaysReached == 5)
        #expect(recap.numbers.bestWaterDayML == 2530)
        #expect(recap.numbers.workoutDays == 3)
        #expect(recap.row(.workouts)?.stat == "3 of 2 days")
        #expect(recap.row(.sleep)?.line == "No sleep tracked.")
        #expect(recap.row(.water)?.line.contains("weekend") == true || recap.row(.water)?.line.contains("eekday") == true)
        #expect(!recap.closingIsSuggestion)

        // Locked phone: the next week waits.
        health.failing = true
        #expect(try await service(loader).refresh(now: cal.at(2026, 11, 23, 9)) == nil)
        #expect(try store.weeklyRecaps().recaps.count == 1)
    }
}
