import Foundation
import Testing
@testable import FuelyCore

@Suite struct OnboardingFlagTests {
    let store = makeTempStore()

    @Test func defaultsToNotCompleted() throws {
        #expect(FuelySettings.default.hasCompletedOnboarding == false)
        #expect(try store.settings().hasCompletedOnboarding == false)
    }

    @Test func oldSettingsFileWithoutTheFlagDecodesAsNotCompleted() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 1, "waterGoalML": 2100}"#.utf8).write(to: store.url(for: .settings))
        let settings = try store.settings()
        #expect(settings.hasCompletedOnboarding == false)
        #expect(settings.waterGoalML == 2100)
    }

    @Test func roundTrips() throws {
        try store.updateSettings { $0.hasCompletedOnboarding = true }
        #expect(try store.settings().hasCompletedOnboarding == true)
    }
}

@Suite struct SettingsLimitsTests {
    @Test(arguments: [(70.0, 70.0), (70.46, 70.5), (30.0, 30.0), (250.0, 250.0)])
    func validWeights(kg: Double, expected: Double) {
        #expect(SettingsLimits.validWeight(kg) == expected)
    }

    @Test func invalidWeights() {
        #expect(SettingsLimits.validWeight(nil) == nil)
        #expect(SettingsLimits.validWeight(29.9) == nil)
        #expect(SettingsLimits.validWeight(251) == nil)
        #expect(SettingsLimits.validWeight(.nan) == nil)
    }

    @Test func parsesTheWeightField() {
        #expect(SettingsLimits.parseWeight("70") == 70)
        #expect(SettingsLimits.parseWeight(" 70.5 ") == 70.5)
        #expect(SettingsLimits.parseWeight("70,5") == 70.5)
        #expect(SettingsLimits.parseWeight("72 kg") == 72)
        #expect(SettingsLimits.parseWeight("") == nil)
        #expect(SettingsLimits.parseWeight("abc") == nil)
        #expect(SettingsLimits.parseWeight("-70") == nil)
        #expect(SettingsLimits.parseWeight("1e2") == nil)
        #expect(SettingsLimits.parseWeight("12") == nil)
        #expect(SettingsLimits.weightText(70) == "70")
        #expect(SettingsLimits.weightText(70.5) == "70.5")
        #expect(SettingsLimits.weightText(nil) == "")
    }

    @Test func suggestedGoalUsesWeightOnly() {
        #expect(FuelySettings(weightKG: 70).suggestedWaterGoalML == 2500)
        #expect(FuelySettings(weightKG: nil).suggestedWaterGoalML == nil)
        // 250 kg × 35 = 8750 → clamped to the goal range.
        #expect(FuelySettings(weightKG: 250).suggestedWaterGoalML == SettingsLimits.waterGoalML.upperBound)
    }

    @Test func drinkingWindowNeedsAnHour() {
        let window = { (s: Int, e: Int) in DrinkingWindow(start: TimeOfDay(minutesSinceMidnight: s), end: TimeOfDay(minutesSinceMidnight: e)) }
        #expect(SettingsLimits.isValid(.default))
        #expect(SettingsLimits.isValid(window(300, 360)))
        #expect(!SettingsLimits.isValid(window(300, 359)))
        #expect(!SettingsLimits.isValid(window(22 * 60, 5 * 60)))
        #expect(SettingsLimits.latestStart(forEnd: TimeOfDay(hour: 22)) == TimeOfDay(hour: 21))
        #expect(SettingsLimits.latestStart(forEnd: TimeOfDay(hour: 0, minute: 30)) == TimeOfDay(hour: 0))
        #expect(SettingsLimits.earliestEnd(forStart: TimeOfDay(hour: 5)) == TimeOfDay(hour: 6))
        #expect(SettingsLimits.earliestEnd(forStart: TimeOfDay(hour: 23, minute: 30)) == TimeOfDay(hour: 23, minute: 59))
    }

    @Test func timeOfDayFromMinutesClamps() {
        #expect(TimeOfDay(minutesSinceMidnight: 90) == TimeOfDay(hour: 1, minute: 30))
        #expect(TimeOfDay(minutesSinceMidnight: -5) == TimeOfDay(hour: 0))
        #expect(TimeOfDay(minutesSinceMidnight: 5000) == TimeOfDay(hour: 23, minute: 59))
    }

    @Test func sanitizedClampsEverything() {
        var settings = FuelySettings(weightKG: 500, waterGoalML: 100, drinkingWindow: DrinkingWindow(start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 5)),
                                     widgetAmountML: 5000, workoutGoal: WorkoutGoal(minMinutesPerDay: 0, daysPerWeek: 3),
                                     sleepGoalScore: 120, hasCompletedOnboarding: true)
        settings = settings.sanitized()
        #expect(settings.weightKG == nil)
        #expect(settings.waterGoalML == 500)
        #expect(settings.drinkingWindow == .default)
        #expect(settings.widgetAmountML == 1000)
        #expect(settings.workoutGoal == WorkoutGoal(minMinutesPerDay: 5, daysPerWeek: 3))
        #expect(settings.sleepGoalScore == 100)
        #expect(settings.hasCompletedOnboarding)
        #expect(FuelySettings.default.sanitized() == .default)
    }
}

@Suite struct HistoryDeleteTests {
    let store = makeTempStore()
    let cal = Calendar.test()

    @Test func deletesAFuelyEntryThatIsOnlyInHealthKit() throws {
        let old = WaterEntry(date: cal.at(2026, 10, 20, 9), amountML: 250, source: .fuely, healthKitSampleID: UUID())
        #expect(try store.deleteWaterEntry(old, at: cal.at(2026, 11, 4, 12)))
        let log = try store.waterLog()
        #expect(log.isDeleted(old.id))
        #expect(log.pending.map(\.kind) == [.delete])
        #expect(log.pending.first?.entryID == old.id)
        // A second delete is a no-op.
        #expect(try store.deleteWaterEntry(old, at: cal.at(2026, 11, 4, 12)) == false)
        #expect(try store.waterLog().pending.count == 1)
    }

    @Test func deletesALocalEntryLikeBefore() throws {
        let entry = try store.logWater(amountML: 300, at: cal.at(2026, 11, 4, 9))
        #expect(try store.deleteWaterEntry(entry, at: cal.at(2026, 11, 4, 10)))
        let log = try store.waterLog()
        #expect(log.entries.isEmpty)
        #expect(log.pending.map(\.kind) == [.delete])
    }

    @Test func otherAppsEntriesAreReadOnly() throws {
        let external = WaterEntry(date: cal.at(2026, 11, 4, 9), amountML: 200, source: .external(name: "Other App"))
        #expect(try store.deleteWaterEntry(external, at: cal.at(2026, 11, 4, 10)) == false)
        #expect(try store.waterLog().pending.isEmpty)
    }

    @Test func serviceDeletesFromHealthKit() async throws {
        let hk = FakeHealthKit()
        // Only in HealthKit (e.g. restored after a reinstall), logged earlier today (W7a).
        let old = WaterEntry(date: cal.at(2026, 11, 4, 9), amountML: 250, source: .fuely)
        hk.insertFuelySample(old)
        let service = WaterLogService(store: store, healthKit: hk, calendar: cal)
        #expect(try await service.delete(old, at: cal.at(2026, 11, 4, 12)))
        #expect(hk.fuelySamples[old.id] == nil)
        #expect(try store.waterLog().pending.isEmpty)
    }
}

@Suite struct WeekHistoryTests {
    let cal = Calendar.test()
    /// Wednesday 2026-11-04 15:00; the week is Mon 2 – Sun 8 Nov.
    var now: Date { cal.at(2026, 11, 4, 15) }
    let settings = FuelySettings(waterGoalML: 2000, workoutGoal: WorkoutGoal(minMinutesPerDay: 30, daysPerWeek: 3),
                                 sleepGoalScore: 80)

    /// 8 h of Watch-staged sleep ending at 05:00 on `day` (23:00 the evening before).
    func night(endingOn day: Int, month: Int = 11) -> SleepSample {
        let end = cal.at(2026, month, day, 5)
        return SleepSample(start: end.addingTimeInterval(-.hours(6)), end: end, stage: .asleepCore,
                           source: SleepSampleSource(bundleIdentifier: "com.apple.health", isAppleWatch: true))
    }

    @Test func buildsAMondayToSundayWeekFromHealthKit() {
        var log = WaterLog()
        let local = WaterEntry(date: cal.at(2026, 11, 3, 9), amountML: 500, source: .fuely)
        log.log(local, enqueuedAt: local.date)
        let remoteOnly = WaterEntry(date: cal.at(2026, 11, 2, 8), amountML: 700, source: .fuely, healthKitSampleID: UUID())
        let deleted = WaterEntry(date: cal.at(2026, 11, 2, 10), amountML: 900, source: .fuely, healthKitSampleID: UUID())
        log.delete(deleted, enqueuedAt: now)
        let external = WaterEntry(date: cal.at(2026, 11, 3, 12), amountML: 1600, source: .external(name: "Other App"))
        let health = WeekHealthData(
            water: [remoteOnly, deleted, local, external],
            sleep: [night(endingOn: 3), night(endingOn: 4)],
            workouts: [WorkoutSample(start: cal.at(2026, 11, 2, 7), end: cal.at(2026, 11, 2, 7, 40), duration: .minutes(40)),
                       WorkoutSample(start: cal.at(2026, 11, 3, 7), end: cal.at(2026, 11, 3, 7, 20), duration: .minutes(20))])

        let week = WeekHistory.make(weekContaining: now, now: now, settings: settings, waterLog: log, health: health,
                                    snapshot: nil, calendar: cal)

        #expect(week.start == cal.at(2026, 11, 2))
        #expect(week.days.count == 7)
        #expect(week.usesHealthData)
        #expect(week.isCurrentWeek)
        let monday = week.days[0], tuesday = week.days[1], wednesday = week.days[2]
        // Local entry counted once; the HealthKit-only Fuely sample is listed; the deleted one isn't.
        #expect(monday.fuelyEntries.map(\.id) == [remoteOnly.id])
        #expect(tuesday.fuelyEntries.map(\.id) == [local.id])
        #expect(tuesday.externalEntries.map(\.id) == [external.id])
        #expect(tuesday.waterTotalML == 2100)
        #expect(tuesday.isWaterGoalMet)
        #expect(abs(tuesday.waterFraction - 1.05) < 0.0001)
        // Sleep: Monday has no night (S7: nil, never 0).
        #expect(monday.sleepScore == nil)
        #expect(tuesday.sleepScore != nil)
        #expect(wednesday.sleepScore != nil)
        #expect(wednesday.isToday)
        // Workouts: Monday 40 min counts, Tuesday 20 min doesn't.
        #expect(monday.isWorkoutDay)
        #expect(!tuesday.isWorkoutDay)
        #expect(week.workoutWeek.workoutDays == 1)
        // Future days are empty.
        #expect(week.days[3...].allSatisfy { $0.isFuture && $0.waterTotalML == 0 && $0.sleepScore == nil })
        #expect(week.elapsedDays.count == 3)
        #expect(week.waterGoalDays == 1)
        #expect(week.scoredNights.count == 2)
    }

    @Test func withoutHealthKitUsesTheLocalLogAndTheSnapshot() {
        var log = WaterLog()
        let entry = WaterEntry(date: cal.at(2026, 11, 4, 9), amountML: 400)
        log.log(entry, enqueuedAt: entry.date)
        let snapshot = HealthSnapshot(refreshedAt: cal.at(2026, 11, 4, 8), externalWaterML: 300, sleepScore: 84,
                                      workouts: [WorkoutSample(start: cal.at(2026, 11, 2, 7), end: cal.at(2026, 11, 2, 8), duration: .minutes(60))])
        let week = WeekHistory.make(weekContaining: now, now: now, settings: settings, waterLog: log, health: nil,
                                    snapshot: snapshot, calendar: cal)
        #expect(!week.usesHealthData)
        let today = week.days[2]
        #expect(today.waterTotalML == 700)
        #expect(today.externalWaterML == 300)
        #expect(today.externalEntries.isEmpty)
        #expect(today.sleepScore == 84)
        #expect(week.days[1].sleepScore == nil)
        #expect(week.days[0].isWorkoutDay)
    }

    @Test func averageSleepSkipsNightsWithoutData() {
        let health = WeekHealthData(water: [], sleep: [night(endingOn: 3), night(endingOn: 4)], workouts: [])
        let week = WeekHistory.make(weekContaining: now, now: now, settings: settings, waterLog: WaterLog(),
                                    health: health, snapshot: nil, calendar: cal)
        let scores = week.scoredNights
        #expect(scores.count == 2)
        #expect(week.averageSleepScore == Int((Double(scores.reduce(0, +)) / 2).rounded()))
        #expect(HistoryCopy.sleepSummary(week) == "Average of 2 nights")
        let empty = WeekHistory.make(weekContaining: now, now: now, settings: settings, waterLog: WaterLog(),
                                     health: WeekHealthData(water: [], sleep: [], workouts: []), snapshot: nil, calendar: cal)
        #expect(empty.averageSleepScore == nil)
    }

    @Test func pastWeekHasNoFutureDays() {
        let lastWeek = cal.at(2026, 10, 28, 12)
        let week = WeekHistory.make(weekContaining: lastWeek, now: now, settings: settings, waterLog: WaterLog(),
                                    health: nil, snapshot: nil, calendar: cal)
        #expect(week.start == cal.at(2026, 10, 26))
        #expect(!week.isCurrentWeek)
        #expect(week.days.allSatisfy { !$0.isFuture })
    }

    @Test func loaderReadsHealthKitForTheWeek() async throws {
        let store = makeTempStore()
        try store.saveSettings(settings)
        let hk = FakeHealthKit()
        hk.setExternalWater([WaterEntry(date: cal.at(2026, 11, 2, 12), amountML: 250, source: .external(name: "Health")),
                             WaterEntry(date: cal.at(2026, 11, 9, 12), amountML: 999, source: .external(name: "Health"))])
        hk.setSleep([night(endingOn: 4)])
        hk.setWorkouts([WorkoutSample(start: cal.at(2026, 11, 3, 7), end: cal.at(2026, 11, 3, 8), duration: .minutes(60))])
        let loader = WeekHistoryLoader(store: store, healthKit: hk, calendar: cal)
        let (week, issue) = try await loader.load(weekContaining: now, now: now)
        #expect(issue == nil)
        #expect(week.usesHealthData)
        #expect(week.days[0].externalWaterML == 250)
        #expect(week.days.map(\.externalWaterML).reduce(0, +) == 250) // next Monday's sample is outside
        #expect(week.days[1].isWorkoutDay)
        #expect(week.days[2].sleepScore != nil)
    }

    @Test func loaderFallsBackWhenHealthKitFails() async throws {
        let store = makeTempStore()
        try store.logWater(amountML: 250, at: cal.at(2026, 11, 4, 9))
        let hk = FakeHealthKit()
        hk.failing = true
        let (week, issue) = try await WeekHistoryLoader(store: store, healthKit: hk, calendar: cal)
            .load(weekContaining: now, now: now)
        #expect(issue == .locked)
        #expect(!week.usesHealthData)
        #expect(week.days[2].waterTotalML == 250)
    }

    @Test func loaderWithoutHealthKit() async throws {
        let (week, issue) = try await WeekHistoryLoader(store: makeTempStore(), healthKit: nil, calendar: cal)
            .load(weekContaining: now, now: now)
        #expect(issue == nil)
        #expect(!week.usesHealthData)
    }
}

@Suite struct HistoryCopyTests {
    let cal = Calendar.test()
    let us = Locale(identifier: "en_US")
    let gb = Locale(identifier: "en_GB")
    var now: Date { cal.at(2026, 11, 4, 15) }

    func week(_ date: Date) -> WeekHistory {
        WeekHistory.make(weekContaining: date, now: now, settings: .default, waterLog: WaterLog(), health: nil,
                         snapshot: nil, calendar: cal)
    }

    /// Date intervals use the system's thin spaces around the dash; compare with plain spaces.
    func spaced(_ text: String) -> String { text.replacingOccurrences(of: "\u{2009}", with: " ") }

    @Test func weekTitles() {
        #expect(spaced(HistoryCopy.weekTitle(week(now), now: now, calendar: cal, locale: us)) == "This week")
        #expect(spaced(HistoryCopy.weekTitle(week(cal.at(2026, 10, 30)), now: now, calendar: cal, locale: us)) == "Last week")
        #expect(spaced(HistoryCopy.weekTitle(week(cal.at(2026, 10, 22)), now: now, calendar: cal, locale: us)) == "Oct 19 – 25")
        #expect(spaced(HistoryCopy.weekRange(week(cal.at(2026, 10, 30)), calendar: cal, locale: us)) == "Oct 26 – Nov 1")
        #expect(spaced(HistoryCopy.weekRange(week(now), calendar: cal, locale: us)) == "Nov 2 – 8")
    }

    /// DECISIONS D3: dates follow the phone's region, not a fixed en_US.
    @Test func weekRangeFollowsRegion() {
        #expect(spaced(HistoryCopy.weekTitle(week(cal.at(2026, 10, 22)), now: now, calendar: cal, locale: gb)) == "19 – 25 Oct")
        #expect(spaced(HistoryCopy.weekRange(week(cal.at(2026, 10, 30)), calendar: cal, locale: gb)) == "26 Oct – 1 Nov")
        #expect(spaced(HistoryCopy.weekRange(week(now), calendar: cal, locale: gb)) == "2 – 8 Nov")
    }

    @Test func dayTitles() {
        let days = week(now).days
        #expect(HistoryCopy.dayTitle(days[2], now: now, calendar: cal, locale: us) == "Today")
        #expect(HistoryCopy.dayTitle(days[1], now: now, calendar: cal, locale: us) == "Yesterday")
        #expect(HistoryCopy.dayTitle(days[0], now: now, calendar: cal, locale: us) == "Monday")
        #expect(HistoryCopy.longDate(days[0].date, calendar: cal, locale: us) == "Monday, November 2")
        #expect(HistoryCopy.shortDate(days[0].date, calendar: cal, locale: us) == "Nov 2")
        #expect(HistoryCopy.weekdayInitial(days[0].date, calendar: cal, locale: us) == "M")
    }

    /// The day detail titles itself from the date it opens with, before its data loads, so the
    /// title is there on the first frame.
    @Test func dayTitlesFromDate() {
        #expect(HistoryCopy.dayTitle(cal.at(2026, 11, 4, 8), now: now, calendar: cal, locale: us) == "Today")
        #expect(HistoryCopy.dayTitle(cal.at(2026, 11, 3, 23, 59), now: now, calendar: cal, locale: us) == "Yesterday")
        #expect(HistoryCopy.dayTitle(cal.at(2026, 11, 2), now: now, calendar: cal, locale: us) == "Monday")
        // A day in a previous week.
        #expect(HistoryCopy.dayTitle(cal.at(2026, 10, 29, 12), now: now, calendar: cal, locale: us) == "Thursday")
    }

    @Test func dayDatesFollowRegion() {
        let days = week(now).days
        #expect(HistoryCopy.longDate(days[0].date, calendar: cal, locale: gb) == "Monday 2 November")
        #expect(HistoryCopy.shortDate(days[0].date, calendar: cal, locale: gb) == "2 Nov")
        #expect(HistoryCopy.longDate(days[0].date, calendar: cal, locale: Locale(identifier: "en_NL"))
                == "Monday, 2 November")
    }

    /// The region's format, but the words stay English (P-English only).
    @Test func languageStaysEnglish() {
        let days = week(now).days
        let dutch = Locale(identifier: "nl_NL")
        #expect(HistoryCopy.dayTitle(days[0], now: now, calendar: cal, locale: dutch) == "Monday")
        #expect(HistoryCopy.longDate(days[0].date, calendar: cal, locale: dutch) == "Monday, 2 November")
        #expect(HistoryCopy.weekdayInitial(days[0].date, calendar: cal, locale: dutch) == "M")
        #expect(DisplayLocale.english(keepingRegionOf: dutch).language.languageCode == .english)
        #expect(DisplayLocale.english(keepingRegionOf: dutch).region == .netherlands)
        #expect(DisplayLocale.english(keepingRegionOf: gb) == gb)
    }

    @Test func summaries() {
        let w = week(now)
        #expect(HistoryCopy.waterSummary(w) == "Goal met 0 of 3 days")
        #expect(HistoryCopy.sleepSummary(w).hasPrefix("No scores yet."))
        #expect(HistoryCopy.workoutSummary(w) == "0/3 days")
        #expect(HistoryCopy.workoutMinutes(w.days[0]) == "—")
    }

    @Test func externalSubtitle() {
        #expect(HistoryCopy.externalSubtitle(WaterEntry(date: now, amountML: 1, source: .external(name: "Other App")))
                == "Other App · read-only")
        #expect(HistoryCopy.externalSubtitle(WaterEntry(date: now, amountML: 1, source: .external(name: "")))
                == "Other app · read-only")
    }

    @Test func dayAccessibility() {
        let days = week(now).days
        #expect(HistoryCopy.dayAccessibility(days[5], now: now, calendar: cal, locale: us).hasSuffix("No data yet."))
        #expect(HistoryCopy.dayAccessibility(days[0], now: now, calendar: cal, locale: us)
                == "Monday, Monday, November 2. Water 0 milliliters, 0 percent of goal, no sleep score, no workouts.")
        #expect(HistoryCopy.dayAccessibility(days[0], now: now, calendar: cal, locale: gb)
                .hasPrefix("Monday, Monday 2 November. "))
    }
}

@Suite struct SettingsCopyTests {
    @Test func windowLength() {
        #expect(SettingsCopy.windowLength(.default) == "17 h")
        #expect(SettingsCopy.windowLength(DrinkingWindow(start: TimeOfDay(hour: 5, minute: 30), end: TimeOfDay(hour: 22))) == "16 h 30 min")
        #expect(SettingsCopy.windowLength(DrinkingWindow(start: TimeOfDay(hour: 5), end: TimeOfDay(hour: 5, minute: 45))) == "45 min")
    }

    @Test func weight() {
        #expect(SettingsCopy.weight(70) == "70 kg")
        #expect(SettingsCopy.weight(70.46) == "70.5 kg")
    }

    @Test func healthAccessTitles() {
        #expect(SettingsCopy.healthAccess(.allowed).title == "Connected")
        #expect(SettingsCopy.healthAccess(.denied).title == "Water sync off")
        #expect(SettingsCopy.healthAccess(.notDetermined).title == "Not connected")
        #expect(SettingsCopy.healthAccess(.unavailable).title == "Unavailable")
    }
}
