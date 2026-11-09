import Foundation

/// Moves data between the App Group store and HealthKit (DECISIONS W4).
///
/// - `pushPending()` applies the queued saves/deletes in order. A locked phone (protected data
///   unavailable) stops the push and leaves the rest queued; any other error (e.g. Health access
///   off) skips that job, which stays queued with its attempt count, and the push moves on. Call it
///   again on app foreground or the next sync. Running it from two processes at once is safe: saves
///   are idempotent (HealthKit sync identifier), deletes of missing samples succeed, and a save that
///   lands after its entry was deleted queues another delete (tombstones in `WaterLog`).
/// - `refresh(now:)` pushes, then reads today's water, recent sleep and this week's workouts,
///   mirrors Fuely's own samples into the local log and saves the widget snapshot.
public struct HealthSync: Sendable {
    public let store: FuelyStore
    public let healthKit: any HealthKitClient
    public let calendar: Calendar
    public let sleepConfig: SleepScoreConfig

    /// Synced local entries older than this many days are forgotten (Apple Health keeps them).
    public static let localRetentionDays = 7

    public init(store: FuelyStore, healthKit: any HealthKitClient, calendar: Calendar = .current,
                sleepConfig: SleepScoreConfig = .default) {
        self.store = store
        self.healthKit = healthKit
        self.calendar = calendar
        self.sleepConfig = sleepConfig
    }

    @discardableResult
    public func pushPending() async -> WaterPushResult {
        var attempted = Set<UUID>()
        var applied = 0
        var failure: (any Error)?
        var issue: HealthSyncIssue?
        do {
            while let operation = try store.waterLog().nextPending(excluding: attempted) {
                attempted.insert(operation.id)
                do {
                    try await apply(operation)
                    applied += 1
                } catch {
                    let kind = HealthSyncIssue(error)
                    if failure == nil { (failure, issue) = (error, kind) }
                    try? store.updateWaterLog { $0.recordFailure(operation.id, issue: kind) }
                    if kind.stopsPush { break }
                }
            }
        } catch {
            if failure == nil { (failure, issue) = (error, HealthSyncIssue(error)) }
        }
        if failure == nil, applied > 0 {
            try? store.updateWaterLog { $0.clearSyncIssue() }
        }
        let remaining = (try? store.waterLog().pending.count) ?? 0
        return WaterPushResult(applied: applied, remaining: remaining, failure: failure, issue: issue)
    }

    /// Pushes pending changes, then reads HealthKit and updates the local log and the widget snapshot.
    /// Throws when HealthKit can't be read (e.g. locked); the cached snapshot stays as it was.
    @discardableResult
    public func refresh(now: Date) async throws -> HealthSnapshot {
        await pushPending()

        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let todayInterval = DateInterval(start: today, end: max(tomorrow, today))

        let historyDays = max(sleepConfig.bedtimeHistoryNights, 1) + 2
        let sleepStart = calendar.date(byAdding: .day, value: -historyDays, to: today) ?? today
        let sleepInterval = DateInterval(start: sleepStart, end: max(now, sleepStart))

        let weekStart = WorkoutAggregation.weekStart(containing: now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let weekInterval = DateInterval(start: weekStart, end: max(weekEnd, weekStart))

        // Wall clock, like `syncedAt` set by concurrent pushes (`now` may be injected).
        let readStartedAt = Date()
        async let water = healthKit.waterEntries(in: todayInterval)
        async let sleep = healthKit.sleepSamples(in: sleepInterval)
        async let workouts = healthKit.workouts(in: weekInterval)
        let (waterEntries, sleepSamples, workoutSamples) = try await (water, sleep, workouts)

        let fuelyRemote = waterEntries.filter { $0.source == .fuely }
        let retentionStart = calendar.date(byAdding: .day, value: -Self.localRetentionDays, to: today) ?? today
        try store.updateWaterLog { log in
            log.reconcile(withHealthKit: fuelyRemote, in: todayInterval, readStartedAt: readStartedAt)
            log.pruneSyncedEntries(before: retentionStart)
            log.pruneTombstones(deletedBefore: retentionStart)
        }

        let externalML = waterEntries.filter { $0.source != .fuely }.reduce(0) { $0 + $1.amountML }
        let score = SleepScoring.score(forNightEndingOn: now, samples: sleepSamples, calendar: calendar, config: sleepConfig)
        let snapshot = HealthSnapshot(refreshedAt: now, externalWaterML: externalML,
                                      sleepScore: score?.total, workouts: workoutSamples)
        try store.saveHealthSnapshot(snapshot)
        return snapshot
    }

    private func apply(_ operation: PendingWaterSync) async throws {
        switch operation.kind {
        case .save:
            guard let entry = try store.waterLog().entry(id: operation.entryID) else {
                // Deleted meanwhile; its queued delete handles HealthKit.
                try store.updateWaterLog { $0.complete(operation.id) }
                return
            }
            // The returned id may not be the stored sample's (see `saveWater`); reconcile corrects it.
            let sampleID = try await healthKit.saveWater(entry)
            try store.updateWaterLog { $0.completeSave(operation.id, entryID: entry.id, healthKitSampleID: sampleID, at: Date()) }
        case .delete:
            try await healthKit.deleteWater(entryID: operation.entryID)
            try store.updateWaterLog { $0.complete(operation.id) }
        }
    }
}
