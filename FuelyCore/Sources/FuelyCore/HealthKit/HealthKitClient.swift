import Foundation

/// The HealthKit operations Fuely uses, behind a protocol so sync logic can be tested with a fake.
/// The live implementation is `LiveHealthKitClient`; only the app process should create one
/// (the widget extension has no HealthKit entitlement and reads the App Group cache, W4).
public protocol HealthKitClient: Sendable {
    /// Asks for read access to water, sleep and workouts and write access to water (DECISIONS O1).
    func requestAuthorization() async throws

    /// Water samples that started in `interval`, from every source. Fuely's own samples come back
    /// with `source == .fuely` and `id` = the local entry id; other apps' as `.external(name:)`.
    func waterEntries(in interval: DateInterval) async throws -> [WaterEntry]

    /// Sleep analysis samples overlapping `interval`, each with its source (Apple Watch or not).
    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample]

    /// Workouts of any type that started in `interval` (DECISIONS K1).
    func workouts(in interval: DateInterval) async throws -> [WorkoutSample]

    /// Writes a Fuely entry as a `dietaryWater` sample (sync identifier = entry id) and returns a
    /// sample UUID. Idempotent: if a sample for this entry id is already stored, HealthKit keeps it
    /// and the new one is dropped. The returned UUID is the stored sample's when the client can tell,
    /// but callers must not rely on it: `WaterLog.reconcile` corrects `healthKitSampleID` from reads.
    func saveWater(_ entry: WaterEntry) async throws -> UUID

    /// Deletes Fuely's sample for `entryID`. Succeeds when there is nothing to delete.
    func deleteWater(entryID: UUID) async throws

    /// Whether Fuely may write water. This is the only Health permission an app can see: read
    /// access is private by design, so a denied read just returns no data.
    func waterWriteAccess() -> HealthAccessStatus
}

extension HealthKitClient {
    public func waterWriteAccess() -> HealthAccessStatus { .notDetermined }
}

/// Fuely's write access to Apple Health water, shown in Settings.
public enum HealthAccessStatus: String, Sendable, Hashable {
    /// Health isn't available on this device (or in previews).
    case unavailable
    /// Fuely hasn't asked yet.
    case notDetermined
    case allowed
    case denied
}

/// The result of pushing the pending queue to HealthKit.
public struct WaterPushResult: Sendable {
    /// Operations applied in this push.
    public var applied: Int
    /// Operations still queued (to retry on the next foreground / sync).
    public var remaining: Int
    /// The first error of this push, e.g. protected data unavailable while locked.
    public var failure: (any Error)?
    /// `failure` classified; nil when every attempted job succeeded.
    public var issue: HealthSyncIssue?

    public init(applied: Int, remaining: Int, failure: (any Error)?, issue: HealthSyncIssue? = nil) {
        self.applied = applied
        self.remaining = remaining
        self.failure = failure
        self.issue = issue
    }
}
