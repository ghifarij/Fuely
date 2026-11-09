import Foundation
import HealthKit
import Testing
@testable import FuelyCore

struct HealthSyncTests {
    let cal = Calendar.test()
    let store = makeTempStore()
    let health = FakeHealthKit()
    var sync: HealthSync { HealthSync(store: store, healthKit: health, calendar: cal) }
    var now: Date { cal.at(2026, 11, 9, 9) }

    @Test func pushSavesQueuedEntriesAndRecordsSampleIDs() async throws {
        let entry = try store.logWater(amountML: 300, at: now)
        let result = await sync.pushPending()
        #expect(result.applied == 1)
        #expect(result.remaining == 0)
        #expect(result.failure == nil)
        let stored = try #require(try store.waterLog().entry(id: entry.id))
        #expect(stored.healthKitSampleID == health.fuelySamples[entry.id]?.healthKitSampleID)
    }

    @Test func lockedPhoneKeepsEntriesQueuedUntilTheNextPush() async throws {
        health.failing = true
        let entry = try store.logWater(amountML: 300, at: now)
        let locked = await sync.pushPending()
        #expect(locked.applied == 0)
        #expect(locked.remaining == 1)
        #expect(locked.failure is HKError)
        #expect(try store.waterLog().entry(id: entry.id) != nil)
        #expect(health.fuelySamples.isEmpty)

        health.failing = false
        let unlocked = await sync.pushPending()
        #expect(unlocked.applied == 1)
        #expect(unlocked.remaining == 0)
        #expect(health.fuelySamples[entry.id]?.amountML == 300)
    }

    @Test func pushStopsAtFirstFailureAndKeepsOrder() async throws {
        let a = try store.logWater(amountML: 100, at: now)
        let b = try store.logWater(amountML: 200, at: now)
        let c = try store.logWater(amountML: 300, at: now)
        health.failAfterWrites = 1
        let result = await sync.pushPending()
        #expect(result.applied == 1)
        #expect(result.remaining == 2)
        #expect(health.fuelySamples.keys.sorted() == [a.id])
        #expect(try store.waterLog().pending.map(\.entryID) == [b.id, c.id])
    }

    @Test func deleteAfterSyncRemovesTheHealthKitSample() async throws {
        let service = WaterLogService(store: store, healthKit: health)
        let (entry, _) = try await service.log(amountML: 250, at: now)
        #expect(health.fuelySamples[entry.id] != nil)
        #expect(try await service.delete(entryID: entry.id, at: now))
        #expect(health.fuelySamples[entry.id] == nil)
        #expect(try store.waterLog().pending.isEmpty)
    }

    @Test func deleteBeforeSyncNeverSavesTheEntry() async throws {
        let entry = try store.logWater(amountML: 250, at: now)
        try store.deleteWaterEntry(id: entry.id, at: now)
        await sync.pushPending()
        #expect(!health.calls.contains("save"))
        #expect(health.fuelySamples.isEmpty)
        #expect(try store.waterLog().pending.isEmpty)
    }

    @Test func pushingTwiceConcurrentlyIsHarmless() async throws {
        for amount in [100, 200, 300] { try store.logWater(amountML: amount, at: now) }
        async let first = sync.pushPending()
        async let second = sync.pushPending()
        _ = await (first, second)
        #expect(health.fuelySamples.count == 3)
        #expect(try store.waterLog().pending.isEmpty)
    }

    @Test func serviceWithoutHealthKitOnlyQueues() async throws {
        // The widget extension: no HealthKit, the app pushes later.
        let widget = WaterLogService(store: store, healthKit: nil)
        let (_, push) = try await widget.log(amountML: 300, at: now)
        #expect(push == nil)
        #expect(try store.waterLog().pending.count == 1)
        #expect(try store.todaySummary(now: now, calendar: cal).water.totalML == 300)

        await sync.pushPending()
        #expect(health.fuelySamples.count == 1)
    }

    @Test func refreshBuildsTheWidgetSnapshot() async throws {
        try store.logWater(amountML: 500, at: cal.at(2026, 11, 9, 8))
        health.setExternalWater([
            WaterEntry(date: cal.at(2026, 11, 9, 7), amountML: 250, source: .external(name: "WaterMinder"), healthKitSampleID: UUID()),
            WaterEntry(date: cal.at(2026, 11, 8, 7), amountML: 999, source: .external(name: "WaterMinder"), healthKitSampleID: UUID()),
        ])
        health.setSleep([SleepSample(start: cal.at(2026, 11, 8, 22), end: cal.at(2026, 11, 9, 6), stage: .asleepCore)])
        health.setWorkouts([
            WorkoutSample(start: cal.at(2026, 11, 9, 6), end: cal.at(2026, 11, 9, 7), duration: 3600),
            WorkoutSample(start: cal.at(2026, 11, 2, 6), end: cal.at(2026, 11, 2, 7), duration: 3600), // last week
        ])

        let snapshot = try await sync.refresh(now: now)
        #expect(snapshot.externalWaterML == 250)
        #expect(snapshot.sleepScore == 100)
        #expect(snapshot.workouts.count == 1)
        #expect(try store.healthSnapshot() == snapshot)

        let summary = try store.todaySummary(now: now, calendar: cal)
        #expect(summary.water.totalML == 750) // Fuely 500 (pushed during refresh) + external 250, no double count
        #expect(summary.pendingSyncCount == 0)
        #expect(summary.workoutWeek.workoutDays == 1)
    }

    @Test func noSleepDataGivesNoScore() async throws {
        let snapshot = try await sync.refresh(now: now)
        #expect(snapshot.sleepScore == nil)
    }

    @Test func refreshMirrorsDeletionsInTheHealthApp() async throws {
        let entry = try store.logWater(amountML: 300, at: now)
        await sync.pushPending()
        health.removeFuelySample(entry.id)
        try await sync.refresh(now: now)
        #expect(try store.waterLog().entries.isEmpty)
    }

    @Test func refreshRestoresFuelySamplesMissingLocally() async throws {
        let earlier = WaterEntry(date: cal.at(2026, 11, 9, 7), amountML: 400, source: .fuely, healthKitSampleID: UUID())
        health.insertFuelySample(earlier)
        try await sync.refresh(now: now)
        #expect(try store.waterLog().entries.map(\.id) == [earlier.id])
    }

    @Test func refreshFailureKeepsTheOldSnapshotAndQueue() async throws {
        let old = HealthSnapshot(refreshedAt: cal.at(2026, 11, 9, 6), externalWaterML: 100, sleepScore: 70, workouts: [])
        try store.saveHealthSnapshot(old)
        try store.logWater(amountML: 300, at: now)
        health.failing = true
        await #expect(throws: HKError.self) { try await sync.refresh(now: now) }
        #expect(try store.healthSnapshot() == old)
        #expect(try store.waterLog().pending.count == 1)
    }

    // MARK: Review fixes

    @Test func undoDuringAnInFlightSaveDoesNotResurrectTheEntry() async throws {
        let entry = try store.logWater(amountML: 300, at: now)
        let store = store, sync = sync, now = now
        health.setBeforeSaveStores {
            // The user undoes while the save is in flight, and the delete's push runs first.
            _ = try? store.deleteWaterEntry(id: entry.id, at: now)
            await sync.pushPending()
        }
        await sync.pushPending()
        #expect(health.fuelySamples[entry.id] == nil)
        try await sync.refresh(now: now)
        let log = try store.waterLog()
        #expect(log.entry(id: entry.id) == nil)
        #expect(log.pending.isEmpty)
    }

    @Test func refreshKeepsAnEntrySyncedDuringItsRead() async throws {
        let service = WaterLogService(store: store, healthKit: health)
        let now = now
        health.setAfterWaterRead { _ = try? await service.log(amountML: 200, at: now) }
        try await sync.refresh(now: now)
        #expect(try store.waterLog().entries.map(\.amountML) == [200])
        #expect(health.fuelySamples.count == 1)
    }

    @Test func aPermanentErrorSkipsThatJobInsteadOfWedgingTheQueue() async throws {
        let a = try store.logWater(amountML: 100, at: now)
        let b = try store.logWater(amountML: 200, at: now)
        health.setWriteError(HKError(.errorAuthorizationDenied), forEntry: a.id)
        let result = await sync.pushPending()
        #expect(result.applied == 1)
        #expect(result.remaining == 1)
        #expect(health.fuelySamples.keys.sorted() == [b.id])
        #expect(try store.waterLog().pending.map(\.entryID) == [a.id])
        // The skipped entry stays local and still counts.
        #expect(try store.todaySummary(now: now, calendar: cal).water.totalML == 300)
    }

    @Test func syncIssueIsRecordedUntilAPushSucceeds() async throws {
        let a = try store.logWater(amountML: 100, at: now)
        health.setWriteError(HKError(.errorAuthorizationNotDetermined), forEntry: a.id)
        let denied = await sync.pushPending()
        #expect(denied.issue == .notAuthorized)
        let log = try store.waterLog()
        #expect(log.lastSyncIssue == .notAuthorized)
        #expect(log.pending.first?.attempts == 1)
        #expect(log.pending.first?.lastIssue == .notAuthorized)
        #expect(try store.todaySummary(now: now, calendar: cal).syncIssue == .notAuthorized)

        health.setWriteError(nil, forEntry: a.id)
        let fixed = await sync.pushPending()
        #expect(fixed.issue == nil)
        #expect(fixed.applied == 1)
        #expect(try store.waterLog().lastSyncIssue == nil)
    }

    @Test func lockedErrorStopsThePush() async throws {
        try store.logWater(amountML: 100, at: now)
        try store.logWater(amountML: 200, at: now)
        health.failing = true
        let result = await sync.pushPending()
        #expect(result.issue == .locked)
        #expect(health.calls.filter { $0 == "save" }.count == 1)
        #expect(result.remaining == 2)
    }

    @Test func classifiesHealthKitErrors() {
        #expect(HealthSyncIssue(HKError(.errorDatabaseInaccessible)) == .locked)
        #expect(HealthSyncIssue(HKError(.errorAuthorizationDenied)) == .notAuthorized)
        #expect(HealthSyncIssue(HKError(.errorAuthorizationNotDetermined)) == .notAuthorized)
        #expect(HealthSyncIssue(HKError(.errorHealthDataUnavailable)) == .unavailable)
        #expect(HealthSyncIssue(HealthKitClientError.unavailable) == .unavailable)
        #expect(HealthSyncIssue(FakeHealthKitError()) == .other)
        #expect(HealthSyncIssue.locked.stopsPush)
        #expect(!HealthSyncIssue.notAuthorized.stopsPush)
    }

    @Test func retriedSaveKeepsTheStoredSampleAndRefreshCorrectsTheSampleID() async throws {
        // The save landed, then the app died before recording it, so the save is still queued.
        let entry = WaterEntry(date: now, amountML: 300)
        var stored = entry
        stored.healthKitSampleID = UUID()
        health.insertFuelySample(stored)
        try store.updateWaterLog { $0.log(entry, enqueuedAt: now) }

        await sync.pushPending()
        #expect(health.fuelySamples[entry.id]?.healthKitSampleID == stored.healthKitSampleID)
        try await sync.refresh(now: now)
        #expect(try store.waterLog().entry(id: entry.id)?.healthKitSampleID == stored.healthKitSampleID)
    }

    @Test func liveClientMapsSleepStages() {
        #expect(LiveHealthKitClient.stage(rawValue: 0) == .inBed)
        #expect(LiveHealthKitClient.stage(rawValue: 1) == .asleepUnspecified)
        #expect(LiveHealthKitClient.stage(rawValue: 2) == .awake)
        #expect(LiveHealthKitClient.stage(rawValue: 3) == .asleepCore)
        #expect(LiveHealthKitClient.stage(rawValue: 4) == .asleepDeep)
        #expect(LiveHealthKitClient.stage(rawValue: 5) == .asleepREM)
        #expect(LiveHealthKitClient.stage(rawValue: 99) == nil)
    }

    @Test func widgetButtonUsesTheSettingsAmount() {
        var settings = FuelySettings.default
        #expect(LogWaterAction.widgetAmountML(settings: settings) == 250)
        settings.widgetAmountML = 400
        #expect(LogWaterAction.widgetAmountML(settings: settings) == 400)
    }
}
