import Foundation

/// The single path for logging and deleting water from the app, the widget (+) and the App Intent:
/// write to the App Group store first, then try to sync to HealthKit (DECISIONS W4, W7).
/// With `healthKit == nil` (widget extension) the change stays queued for the app to push.
/// Only today's drinks can be deleted (W7a); `calendar` decides where today starts.
public struct WaterLogService: Sendable {
    public let store: FuelyStore
    public let healthKit: (any HealthKitClient)?
    public let calendar: Calendar

    public init(store: FuelyStore, healthKit: (any HealthKitClient)?, calendar: Calendar = .current) {
        self.store = store
        self.healthKit = healthKit
        self.calendar = calendar
    }

    /// The service for the current process: HealthKit only in the app, never in an extension.
    public static func current(store: FuelyStore) -> WaterLogService {
        WaterLogService(store: store, healthKit: canUseHealthKit ? LiveHealthKitClient() : nil)
    }

    /// False inside app extensions (the widget has no HealthKit entitlement) or without HealthKit.
    public static var canUseHealthKit: Bool {
        Bundle.main.bundleURL.pathExtension != "appex" && LiveHealthKitClient.isAvailable
    }

    /// Stores the entry, then pushes the queue. Succeeds even if HealthKit fails (it stays queued).
    @discardableResult
    public func log(amountML: Int, at date: Date) async throws -> (entry: WaterEntry, push: WaterPushResult?) {
        let entry = try store.logWater(amountML: amountML, at: date)
        return (entry, await push())
    }

    /// Deletes a Fuely entry locally, then pushes the HealthKit delete. False if not found, read-only
    /// or on a finished day (W7a).
    @discardableResult
    public func delete(entryID: UUID, at date: Date) async throws -> Bool {
        guard let entry = try store.waterLog().entry(id: entryID),
              DayEditability.isEditable(day: entry.date, now: date, calendar: calendar),
              try store.deleteWaterEntry(id: entryID, at: date) else { return false }
        await push()
        return true
    }

    /// Deletes a Fuely entry shown in Today or History (it may exist only in HealthKit), then pushes
    /// the HealthKit delete. False for other apps' entries (read-only, W7) and for a drink on a
    /// finished day (W7a).
    @discardableResult
    public func delete(_ entry: WaterEntry, at date: Date) async throws -> Bool {
        guard DayEditability.isEditable(day: entry.date, now: date, calendar: calendar),
              try store.deleteWaterEntry(entry, at: date) else { return false }
        await push()
        return true
    }

    @discardableResult
    private func push() async -> WaterPushResult? {
        guard let healthKit else { return nil }
        return await HealthSync(store: store, healthKit: healthKit).pushPending()
    }
}
