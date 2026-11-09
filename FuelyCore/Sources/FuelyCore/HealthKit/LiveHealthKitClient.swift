import Foundation
import HealthKit

public enum HealthKitClientError: Error, Sendable, Equatable {
    /// HealthKit is not available on this device.
    case unavailable
}

/// `HealthKitClient` backed by `HKHealthStore`. The only file in FuelyCore that talks to HealthKit.
/// Create it only in the app process: the widget extension links HealthKit through FuelyCore but has
/// no entitlement and never calls it.
public struct LiveHealthKitClient: HealthKitClient {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let waterType = HKQuantityType(.dietaryWater)
    private static let sleepType = HKCategoryType(.sleepAnalysis)
    private static let milliliters = HKUnit.literUnit(with: .milli)

    public func requestAuthorization() async throws {
        try ensureAvailable()
        try await healthStore.requestAuthorization(
            toShare: [Self.waterType],
            read: [Self.waterType, Self.sleepType, HKObjectType.workoutType()]
        )
    }

    public func waterWriteAccess() -> HealthAccessStatus {
        guard Self.isAvailable else { return .unavailable }
        switch healthStore.authorizationStatus(for: Self.waterType) {
        case .sharingAuthorized: return .allowed
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public func waterEntries(in interval: DateInterval) async throws -> [WaterEntry] {
        try ensureAvailable()
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.waterType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: healthStore)
        let ownBundleID = HKSource.default().bundleIdentifier
        return samples.map { sample in
            let amount = Int(sample.quantity.doubleValue(for: Self.milliliters).rounded())
            let source = sample.sourceRevision.source
            if source.bundleIdentifier == ownBundleID {
                let syncID = (sample.metadata?[HKMetadataKeySyncIdentifier] as? String).flatMap(UUID.init(uuidString:))
                return WaterEntry(id: syncID ?? sample.uuid, date: sample.startDate, amountML: amount,
                                  source: .fuely, healthKitSampleID: sample.uuid)
            }
            return WaterEntry(id: sample.uuid, date: sample.startDate, amountML: amount,
                              source: .external(name: source.name), healthKitSampleID: sample.uuid)
        }
    }

    public func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
        try ensureAvailable()
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: healthStore).compactMap { sample in
            let revision = sample.sourceRevision
            let source = SleepSampleSource(bundleIdentifier: revision.source.bundleIdentifier,
                                           isAppleWatch: revision.productType?.hasPrefix("Watch") ?? false,
                                           name: revision.source.name)
            return Self.stage(rawValue: sample.value).map {
                SleepSample(start: sample.startDate, end: sample.endDate, stage: $0, source: source)
            }
        }
    }

    public func workouts(in interval: DateInterval) async throws -> [WorkoutSample] {
        try ensureAvailable()
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: healthStore).map {
            WorkoutSample(start: $0.startDate, end: $0.endDate, duration: $0.duration)
        }
    }

    public func saveWater(_ entry: WaterEntry) async throws -> UUID {
        try ensureAvailable()
        let sample = HKQuantitySample(
            type: Self.waterType,
            quantity: HKQuantity(unit: Self.milliliters, doubleValue: Double(entry.amountML)),
            start: entry.date,
            end: entry.date,
            metadata: [
                // A sample with this sync identifier and the same (or a higher) version already
                // stored makes HealthKit keep that one and drop the new sample, so a retried save
                // (e.g. after a crash) never duplicates.
                HKMetadataKeySyncIdentifier: entry.id.uuidString,
                HKMetadataKeySyncVersion: 1,
            ]
        )
        try await healthStore.save(sample)
        // On a retry `sample` was not stored; report the stored sample's id when it can be read.
        return (try? await storedWaterSampleID(entryID: entry.id)) ?? sample.uuid
    }

    private func storedWaterSampleID(entryID: UUID) async throws -> UUID? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.waterType, predicate: ownSamplePredicate(entryID: entryID))],
            sortDescriptors: [],
            limit: 1
        )
        return try await descriptor.result(for: healthStore).first?.uuid
    }

    private func ownSamplePredicate(entryID: UUID) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [entryID.uuidString]),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
    }

    public func deleteWater(entryID: UUID) async throws {
        try ensureAvailable()
        _ = try await healthStore.deleteObjects(of: Self.waterType, predicate: ownSamplePredicate(entryID: entryID))
    }

    private func ensureAvailable() throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitClientError.unavailable }
    }

    static func stage(rawValue: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
        case .inBed: .inBed
        case .awake: .awake
        case .asleepUnspecified: .asleepUnspecified
        case .asleepCore: .asleepCore
        case .asleepDeep: .asleepDeep
        case .asleepREM: .asleepREM
        default: nil
        }
    }
}
