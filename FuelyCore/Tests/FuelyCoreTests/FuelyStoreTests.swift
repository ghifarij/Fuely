import Foundation
import Testing
@testable import FuelyCore

struct FuelyStoreTests {
    let cal = Calendar.test()
    let store = makeTempStore()

    @Test func emptyStoreReadsDefaults() throws {
        #expect(try store.settings() == .default)
        #expect(try store.waterLog() == WaterLog())
        #expect(try store.healthSnapshot() == nil)
        #expect(try store.reminders() == ReminderBookkeeping())
    }

    @Test func settingsRoundTrip() throws {
        var settings = FuelySettings.default
        settings.weightKG = 70
        settings.waterGoalML = 2500
        settings.widgetAmountML = 350
        settings.drinkingWindow = DrinkingWindow(start: TimeOfDay(hour: 6), end: TimeOfDay(hour: 21, minute: 30))
        try store.saveSettings(settings)
        #expect(try store.settings() == settings)

        try store.updateSettings { $0.sleepGoalScore = 85 }
        #expect(try store.settings().sleepGoalScore == 85)
        // A second store on the same directory (another process) sees the same data.
        #expect(try FuelyStore(directory: store.directory).settings().widgetAmountML == 350)
    }

    @Test func waterLogRoundTripAndQueue() throws {
        let now = cal.at(2026, 11, 9, 9)
        let a = try store.logWater(amountML: 300, at: now)
        let b = try store.logWater(amountML: 150, at: now.addingTimeInterval(60))
        var log = try store.waterLog()
        #expect(log.entries.map(\.id) == [a.id, b.id])
        #expect(log.pending.map(\.kind) == [.save, .save])

        #expect(try store.deleteWaterEntry(id: a.id, at: now))
        log = try store.waterLog()
        #expect(log.entries.map(\.id) == [b.id])
        #expect(log.pending.map(\.kind) == [.save, .delete])
        #expect(log.pending.map(\.entryID) == [b.id, a.id])
        #expect(try !store.deleteWaterEntry(id: a.id, at: now))
    }

    @Test func rejectsNonPositiveAmounts() {
        #expect(throws: FuelyStoreError.invalidAmount(0)) { try store.logWater(amountML: 0, at: .now) }
        #expect(throws: FuelyStoreError.invalidAmount(-5)) { try store.logWater(amountML: -5, at: .now) }
    }

    @Test func snapshotAndRemindersRoundTrip() throws {
        let now = cal.at(2026, 11, 9, 9)
        let snapshot = HealthSnapshot(refreshedAt: now, externalWaterML: 400, sleepScore: 82,
                                      workouts: [WorkoutSample(start: now, end: now + 1800, duration: 1800)])
        try store.saveHealthSnapshot(snapshot)
        #expect(try store.healthSnapshot() == snapshot)

        try store.updateReminders { $0.recordWaterReminder(at: now, calendar: cal) }
        #expect(try store.reminders().waterRemindersSent(onDayOf: now, calendar: cal) == 1)
    }

    @Test func filesAreJSONInTheDirectory() throws {
        try store.logWater(amountML: 250, at: .now)
        let data = try Data(contentsOf: store.url(for: .waterLog))
        #expect(try JSONSerialization.jsonObject(with: data) is [String: Any])
    }

    @Test func corruptFileThrowsInsteadOfSilentlyResetting() throws {
        try store.logWater(amountML: 250, at: .now)
        try Data("not json".utf8).write(to: store.url(for: .waterLog))
        #expect(throws: (any Error).self) { try store.waterLog() }
        #expect(throws: (any Error).self) { try store.logWater(amountML: 250, at: .now) }
    }

    // MARK: Schema evolution

    private func write(_ json: String, to file: FuelyStore.File) throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.url(for: file))
    }

    @Test func filesWithMissingFieldsDecodeWithDefaults() throws {
        try write(#"{"waterGoalML": 2000, "drinkingWindow": {"start": {"hour": 6}}, "workoutGoal": {}}"#, to: .settings)
        let settings = try store.settings()
        #expect(settings.waterGoalML == 2000)
        #expect(settings.drinkingWindow == DrinkingWindow(start: TimeOfDay(hour: 6), end: DrinkingWindow.default.end))
        #expect(settings.workoutGoal == .default)
        #expect(settings.widgetAmountML == FuelySettings.default.widgetAmountML)
        #expect(settings.sleepGoalScore == 80)
        #expect(settings.weightKG == nil)

        let id = UUID()
        try write(#"{"entries": [{"id": "\#(id.uuidString)", "date": 800000000, "amountML": 250}], "pending": [{"kind": "save", "entryID": "\#(id.uuidString)"}]}"#, to: .waterLog)
        let log = try store.waterLog()
        #expect(log.entries.map(\.id) == [id])
        #expect(log.entries.first?.source == .fuely)
        #expect(log.entries.first?.healthKitSampleID == nil)
        #expect(log.pending.map(\.entryID) == [id])
        #expect(log.pending.first?.attempts == 0)

        try write(#"{"refreshedAt": 800000000}"#, to: .healthSnapshot)
        let snapshot = try #require(try store.healthSnapshot())
        #expect(snapshot.externalWaterML == 0)
        #expect(snapshot.sleepScore == nil)
        #expect(snapshot.workouts.isEmpty)

        try write("{}", to: .reminders)
        #expect(try store.reminders() == ReminderBookkeeping())
    }

    @Test func filesWithUnknownFieldsDecode() throws {
        try store.saveSettings(FuelySettings(waterGoalML: 2100))
        try store.logWater(amountML: 250, at: cal.at(2026, 11, 9, 9))
        try store.saveHealthSnapshot(HealthSnapshot(refreshedAt: .now, externalWaterML: 5, sleepScore: 70,
                                                    workouts: [WorkoutSample(start: .now, end: .now, duration: 0)]))
        try store.updateReminders { $0.recordWaterReminder(at: .now, calendar: cal) }
        try store.updateWaterDraft { $0 = WaterDraft(amountML: 300, startedAt: cal.at(2026, 11, 9, 9)) }
        for file in FuelyStore.File.allCases {
            let url = store.url(for: file)
            var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            object["addedInAFutureVersion"] = ["nested": true]
            try JSONSerialization.data(withJSONObject: object).write(to: url)
        }
        #expect(try store.settings().waterGoalML == 2100)
        #expect(try store.waterLog().entries.map(\.amountML) == [250])
        #expect(try store.healthSnapshot()?.sleepScore == 70)
        #expect(try store.reminders().waterRemindersSent(onDayOf: .now, calendar: cal) == 1)
        #expect(try store.waterDraft()?.amountML == 300)
    }

    @Test func filesCarryASchemaVersion() throws {
        try store.saveSettings(.default)
        try store.logWater(amountML: 250, at: .now)
        for file in [FuelyStore.File.settings, .waterLog] {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: file))) as? [String: Any]
            #expect(object?["schemaVersion"] as? Int == 1)
        }
    }

    @Test func concurrentWritesFromSeveralStoreInstancesAreNotLost() async throws {
        let directory = store.directory
        let writers = 40
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<writers {
                group.addTask {
                    // Separate instances stand in for the app, the widget and the intent.
                    try FuelyStore(directory: directory).logWater(amountML: 100 + i, at: .now)
                }
            }
            try await group.waitForAll()
        }
        let log = try store.waterLog()
        #expect(log.entries.count == writers)
        #expect(log.pending.count == writers)
    }

    @Test func todaySummaryCombinesLocalWaterAndSnapshot() throws {
        let now = cal.at(2026, 11, 9, 13, 30)  // halfway through 05:00–22:00
        try store.saveSettings(FuelySettings(waterGoalML: 2000))
        try store.logWater(amountML: 500, at: cal.at(2026, 11, 9, 8))
        try store.logWater(amountML: 999, at: cal.at(2026, 11, 8, 8)) // yesterday
        try store.saveHealthSnapshot(HealthSnapshot(refreshedAt: cal.at(2026, 11, 9, 7), externalWaterML: 600,
                                                    sleepScore: 82, workouts: []))
        let summary = try store.todaySummary(now: now, calendar: cal)
        #expect(summary.fuelyWaterML == 500)
        #expect(summary.externalWaterML == 600)
        #expect(summary.water.totalML == 1100)
        #expect(summary.water.status == .onTrack)
        #expect(summary.sleepScore == 82)
        #expect(summary.sleepGoalMet == true)
        #expect(summary.pendingSyncCount == 2)
    }
}

struct TodaySummaryTests {
    let cal = Calendar.test()

    @Test func staleSnapshotRollsOverAtMidnight() {
        let yesterday = cal.at(2026, 11, 8, 20)
        let now = cal.at(2026, 11, 9, 6)
        let snapshot = HealthSnapshot(refreshedAt: yesterday, externalWaterML: 800, sleepScore: 75, workouts: [])
        let summary = TodaySummary.make(settings: .default, waterLog: WaterLog(), snapshot: snapshot, now: now, calendar: cal)
        #expect(summary.externalWaterML == 0)
        #expect(summary.sleepScore == nil)
        #expect(summary.sleepGoalMet == nil)
        #expect(summary.healthRefreshedAt == yesterday)
    }

    @Test func workoutsCountOnlyInTheirOwnWeek() {
        // Mon 2026-11-09 and Sun 2026-11-08 (previous week).
        let monday = cal.at(2026, 11, 9, 7)
        let sunday = cal.at(2026, 11, 8, 7)
        let workouts = [WorkoutSample(start: sunday, end: sunday + 3600, duration: 3600),
                        WorkoutSample(start: monday, end: monday + 3600, duration: 3600)]
        let snapshot = HealthSnapshot(refreshedAt: monday, externalWaterML: 0, sleepScore: nil, workouts: workouts)
        let summary = TodaySummary.make(settings: .default, waterLog: WaterLog(), snapshot: snapshot,
                                        now: cal.at(2026, 11, 10, 9), calendar: cal)
        #expect(summary.workoutWeek.workoutDays == 1)

        let nextWeek = TodaySummary.make(settings: .default, waterLog: WaterLog(), snapshot: snapshot,
                                         now: cal.at(2026, 11, 16, 9), calendar: cal)
        #expect(nextWeek.workoutWeek.workoutDays == 0)
    }

    @Test func noSnapshotMeansOnlyLocalWater() {
        var log = WaterLog()
        log.log(WaterEntry(date: cal.at(2026, 11, 9, 8), amountML: 300), enqueuedAt: .now)
        let summary = TodaySummary.make(settings: .default, waterLog: log, snapshot: nil,
                                        now: cal.at(2026, 11, 9, 9), calendar: cal)
        #expect(summary.water.totalML == 300)
        #expect(summary.sleepScore == nil)
        #expect(summary.healthRefreshedAt == nil)
    }
}
