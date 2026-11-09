import Foundation

public enum FuelyStoreError: Error, Sendable, Equatable {
    /// The App Group container is missing (entitlement not set for this process).
    case appGroupUnavailable
    /// Water amounts must be positive.
    case invalidAmount(Int)
}

/// Shared state in the App Group container, used by the app, the widget extension and the
/// App Intent (DECISIONS W4).
///
/// Storage: one small JSON file per concern in `directory`
/// (`settings.json`, `water-log.json`, `health-snapshot.json`, `reminders.json`, `water-draft.json`).
///
/// Cross-process safety: every read takes a coordinated read and every change is a single
/// read-modify-write inside a coordinated write (`NSFileCoordinator`, which serialises access
/// across processes sharing the container and across threads in one process). Files are replaced
/// atomically, so a reader never sees a half-written file. Each file is self-contained, so one
/// change never has to span two files (entries and their sync queue live together in
/// `water-log.json`). Files use `completeUntilFirstUserAuthentication` protection, so the store
/// stays usable while the phone is locked, unlike HealthKit.
///
/// A missing file reads as its default. Calls are synchronous and short; keep them off hot UI paths
/// if needed.
public final class FuelyStore: Sendable {
    public let directory: URL

    /// A store in `directory` (tests pass a temporary directory). The directory is created on first write.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The store in the shared App Group container.
    public static func appGroup(identifier: String = FuelyCore.appGroupID) throws -> FuelyStore {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw FuelyStoreError.appGroupUnavailable
        }
        return FuelyStore(directory: container.appending(path: "Fuely", directoryHint: .isDirectory))
    }

    // MARK: Settings

    public func settings() throws -> FuelySettings {
        try read(.settings, default: .default)
    }

    public func saveSettings(_ settings: FuelySettings) throws {
        try update(.settings, default: FuelySettings.default) { $0 = settings }
    }

    @discardableResult
    public func updateSettings<R>(_ body: (inout FuelySettings) throws -> R) throws -> R {
        try update(.settings, default: .default, body)
    }

    // MARK: Water

    public func waterLog() throws -> WaterLog {
        try read(.waterLog, default: WaterLog())
    }

    /// Atomic read-modify-write of the water log (entries + sync queue).
    @discardableResult
    public func updateWaterLog<R>(_ body: (inout WaterLog) throws -> R) throws -> R {
        try update(.waterLog, default: WaterLog(), body)
    }

    /// Saves a new Fuely entry and queues it for HealthKit. Never touches HealthKit.
    @discardableResult
    public func logWater(amountML: Int, at date: Date) throws -> WaterEntry {
        guard amountML > 0 else { throw FuelyStoreError.invalidAmount(amountML) }
        let entry = WaterEntry(date: date, amountML: amountML, source: .fuely)
        try updateWaterLog { $0.log(entry, enqueuedAt: date) }
        return entry
    }

    /// Removes a Fuely entry and queues its HealthKit delete. False if there is no such entry.
    @discardableResult
    public func deleteWaterEntry(id: UUID, at date: Date) throws -> Bool {
        try updateWaterLog { $0.delete(entryID: id, enqueuedAt: date) }
    }

    /// Removes a Fuely entry, also one that is only in HealthKit (History), and queues its
    /// HealthKit delete. False for other apps' entries or one already deleted.
    @discardableResult
    public func deleteWaterEntry(_ entry: WaterEntry, at date: Date) throws -> Bool {
        try updateWaterLog { $0.delete(entry, enqueuedAt: date) }
    }

    // MARK: HealthKit snapshot (widget cache)

    public func healthSnapshot() throws -> HealthSnapshot? {
        try read(.healthSnapshot, default: HealthSnapshot?.none)
    }

    public func saveHealthSnapshot(_ snapshot: HealthSnapshot) throws {
        try update(.healthSnapshot, default: HealthSnapshot?.none) { $0 = snapshot }
    }

    // MARK: Reminders

    public func reminders() throws -> ReminderBookkeeping {
        try read(.reminders, default: ReminderBookkeeping())
    }

    @discardableResult
    public func updateReminders<R>(_ body: (inout ReminderBookkeeping) throws -> R) throws -> R {
        try update(.reminders, default: ReminderBookkeeping(), body)
    }

    // MARK: Widget amount picker (DECISIONS W6b)

    /// The stored picker draft, possibly stale. Prefer `activeWaterDraft(now:)`.
    public func waterDraft() throws -> WaterDraft? {
        try read(.waterDraft, default: WaterDraft?.none)
    }

    /// The draft if it is still active at `now`; a stale draft reads as nil (Idle).
    public func activeWaterDraft(now: Date) throws -> WaterDraft? {
        WaterDraft.active(try waterDraft(), at: now)
    }

    /// Atomic read-modify-write of the picker draft (nil = Idle).
    @discardableResult
    public func updateWaterDraft<R>(_ body: (inout WaterDraft?) throws -> R) throws -> R {
        try update(.waterDraft, default: WaterDraft?.none, body)
    }

    // MARK: Summary

    /// What the Today screen and the widgets show, from the stored state only (no HealthKit).
    public func todaySummary(now: Date, calendar: Calendar) throws -> TodaySummary {
        TodaySummary.make(settings: try settings(), waterLog: try waterLog(), snapshot: try healthSnapshot(),
                          now: now, calendar: calendar)
    }

    // MARK: - Files

    enum File: String, CaseIterable {
        case settings = "settings.json"
        case waterLog = "water-log.json"
        case healthSnapshot = "health-snapshot.json"
        case reminders = "reminders.json"
        case waterDraft = "water-draft.json"
    }

    func url(for file: File) -> URL {
        directory.appending(path: file.rawValue, directoryHint: .notDirectory)
    }

    private func read<T: Codable>(_ file: File, default defaultValue: T) throws -> T {
        try coordinate(file, writing: false) { url in try load(url, default: defaultValue) }
    }

    private func update<T: Codable, R>(_ file: File, default defaultValue: T, _ body: (inout T) throws -> R) throws -> R {
        try coordinate(file, writing: true) { url in
            var value = try load(url, default: defaultValue)
            let result = try body(&value)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return result
        }
    }

    private func load<T: Codable>(_ url: URL, default defaultValue: T) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return defaultValue
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func coordinate<R>(_ file: File, writing: Bool, _ body: (URL) throws -> R) throws -> R {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<R, any Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url(for: file), options: .forMerging, error: &coordinationError) { url in
                result = Result { try body(url) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url(for: file), options: [], error: &coordinationError) { url in
                result = Result { try body(url) }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileLocking) }
        return try result.get()
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
