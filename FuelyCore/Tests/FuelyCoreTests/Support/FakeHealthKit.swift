import Foundation
import HealthKit
@testable import FuelyCore

/// An error HealthSync doesn't recognise (classified `.other`).
struct FakeHealthKitError: Error, Equatable {
    var reason = "something else"
}

/// What HealthKit throws while the phone is locked (protected data unavailable).
let lockedError = HKError(.errorDatabaseInaccessible)

/// In-memory HealthKit stand-in. Mimics HealthKit: a save with an existing sync identifier (same
/// version) keeps the stored sample and returns the new, unstored sample's UUID; deletes of missing
/// samples succeed; reads return Fuely's own samples as `.fuely`.
final class FakeHealthKit: HealthKitClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _fuelySamples: [UUID: WaterEntry] = [:]
    private var _externalWater: [WaterEntry] = []
    private var _sleep: [SleepSample] = []
    private var _workouts: [WorkoutSample] = []
    private var _failing = false
    private var _failAfter: Int?
    private var _calls: [String] = []
    private var _writeErrors: [UUID: any Error] = [:]
    private var _beforeSaveStores: (@Sendable () async -> Void)?
    private var _afterWaterRead: (@Sendable () async -> Void)?

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    var fuelySamples: [UUID: WaterEntry] { locked { _fuelySamples } }
    var calls: [String] { locked { _calls } }
    /// Every call fails while true (e.g. phone locked).
    var failing: Bool {
        get { locked { _failing } }
        set { locked { _failing = newValue } }
    }
    /// Fails every write after this many successful ones.
    var failAfterWrites: Int? {
        get { locked { _failAfter } }
        set { locked { _failAfter = newValue } }
    }

    /// Writes (save or delete) for this entry id throw `error`; nil clears it.
    func setWriteError(_ error: (any Error)?, forEntry id: UUID) { locked { _writeErrors[id] = error } }
    /// Runs once inside the next save, after the call started and before the sample is stored
    /// (an in-flight save).
    func setBeforeSaveStores(_ hook: @escaping @Sendable () async -> Void) { locked { _beforeSaveStores = hook } }
    /// Runs once inside the next water read, after the results were taken (a stale read).
    func setAfterWaterRead(_ hook: @escaping @Sendable () async -> Void) { locked { _afterWaterRead = hook } }

    func setExternalWater(_ entries: [WaterEntry]) { locked { _externalWater = entries } }
    func setSleep(_ samples: [SleepSample]) { locked { _sleep = samples } }
    func setWorkouts(_ samples: [WorkoutSample]) { locked { _workouts = samples } }
    /// Simulates a sample written by Fuely earlier (e.g. before a reinstall).
    func insertFuelySample(_ entry: WaterEntry) { locked { _fuelySamples[entry.id] = entry } }
    /// Simulates the user deleting Fuely's sample in the Health app.
    func removeFuelySample(_ id: UUID) { _ = locked { _fuelySamples.removeValue(forKey: id) } }

    private func check(_ call: String, write: Bool = false, entryID: UUID? = nil) throws {
        try locked {
            _calls.append(call)
            if _failing { throw lockedError }
            if write, let entryID, let error = _writeErrors[entryID] { throw error }
            if write, let remaining = _failAfter {
                if remaining <= 0 { throw lockedError }
                _failAfter = remaining - 1
            }
        }
    }

    func requestAuthorization() async throws { try check("auth") }

    func waterEntries(in interval: DateInterval) async throws -> [WaterEntry] {
        try check("water")
        let (result, hook) = locked {
            let result = (Array(_fuelySamples.values) + _externalWater)
                .filter { interval.containsHalfOpen($0.date) }
                .sorted { $0.date < $1.date }
            defer { _afterWaterRead = nil }
            return (result, _afterWaterRead)
        }
        await hook?()
        return result
    }

    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
        try check("sleep")
        return locked { _sleep.filter { $0.end > interval.start && $0.start < interval.end } }
    }

    func workouts(in interval: DateInterval) async throws -> [WorkoutSample] {
        try check("workouts")
        return locked { _workouts.filter { interval.containsHalfOpen($0.start) } }
    }

    func saveWater(_ entry: WaterEntry) async throws -> UUID {
        try check("save", write: true, entryID: entry.id)
        let hook = locked { defer { _beforeSaveStores = nil }; return _beforeSaveStores }
        await hook?()
        let sampleID = UUID()
        locked {
            // Same sync identifier and version: HealthKit keeps the stored sample.
            guard _fuelySamples[entry.id] == nil else { return }
            var stored = entry
            stored.source = .fuely
            stored.healthKitSampleID = sampleID
            _fuelySamples[entry.id] = stored
        }
        return sampleID
    }

    func deleteWater(entryID: UUID) async throws {
        try check("delete", write: true, entryID: entryID)
        _ = locked { _fuelySamples.removeValue(forKey: entryID) }
    }
}

/// A store in a fresh temporary directory.
func makeTempStore() -> FuelyStore {
    FuelyStore(directory: FileManager.default.temporaryDirectory
        .appending(path: "FuelyStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory))
}
