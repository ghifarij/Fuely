import Foundation

/// A HealthKit change that Fuely still owes Apple Health (DECISIONS W4: local first, then sync).
public struct PendingWaterSync: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        /// Write the local entry with `entryID` to HealthKit.
        case save
        /// Delete Fuely's HealthKit sample for `entryID` (matched by its sync identifier).
        case delete
    }

    public var id: UUID
    public var kind: Kind
    public var entryID: UUID
    public var enqueuedAt: Date
    /// Failed attempts so far, and the issue of the last one.
    public var attempts: Int
    public var lastIssue: HealthSyncIssue?

    public init(id: UUID = UUID(), kind: Kind, entryID: UUID, enqueuedAt: Date, attempts: Int = 0,
                lastIssue: HealthSyncIssue? = nil) {
        self.id = id
        self.kind = kind
        self.entryID = entryID
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
        self.lastIssue = lastIssue
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, entryID, enqueuedAt, attempts, lastIssue
    }

    /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .save,
                  entryID: try c.decodeIfPresent(UUID.self, forKey: .entryID) ?? UUID(),
                  enqueuedAt: try c.decodeIfPresent(Date.self, forKey: .enqueuedAt) ?? .distantPast,
                  attempts: try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0,
                  lastIssue: try? c.decodeIfPresent(HealthSyncIssue.self, forKey: .lastIssue))
    }
}

/// Fuely's own water entries plus the queue of HealthKit changes not yet applied.
/// Entries from other apps are never stored here; they come from HealthKit (see `HealthSnapshot`).
public struct WaterLog: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    /// The format version this log was written with.
    public private(set) var schemaVersion: Int
    /// Fuely's entries, oldest first.
    public private(set) var entries: [WaterEntry]
    /// HealthKit work in FIFO order. At most one `.save` and one `.delete` per entry.
    public private(set) var pending: [PendingWaterSync]
    /// Tombstones: ids of deleted Fuely entries and when they were deleted. A deleted entry is never
    /// restored from HealthKit; a sample that shows up for one (a save that was in flight during the
    /// delete) gets deleted again. Pruned after `HealthSync.localRetentionDays`.
    public private(set) var deletedEntries: [UUID: Date]
    /// The issue of the last push that failed a job; nil once a push succeeds without failures.
    /// Lets the UI show e.g. "Health access off".
    public private(set) var lastSyncIssue: HealthSyncIssue?

    public init(entries: [WaterEntry] = [], pending: [PendingWaterSync] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.entries = entries.sorted { $0.date < $1.date }
        self.pending = pending
        self.deletedEntries = [:]
        self.lastSyncIssue = nil
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, entries, pending, deletedEntries, lastSyncIssue
    }

    /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try c.decodeIfPresent([WaterEntry].self, forKey: .entries) ?? [],
                  pending: try c.decodeIfPresent([PendingWaterSync].self, forKey: .pending) ?? [])
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        deletedEntries = try c.decodeIfPresent([UUID: Date].self, forKey: .deletedEntries) ?? [:]
        lastSyncIssue = try? c.decodeIfPresent(HealthSyncIssue.self, forKey: .lastSyncIssue)
    }

    public func entry(id: UUID) -> WaterEntry? { entries.first { $0.id == id } }

    /// Fuely's entries on the calendar day containing `now`.
    public func entries(onDayOf now: Date, calendar: Calendar) -> [WaterEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// The newest entry, for Undo (DECISIONS W7).
    public var latestEntry: WaterEntry? { entries.max { $0.date < $1.date } }

    /// Whether the Fuely entry with this id was deleted (tombstoned).
    public func isDeleted(_ entryID: UUID) -> Bool { deletedEntries[entryID] != nil }

    /// Adds a Fuely entry and queues its HealthKit save.
    public mutating func log(_ entry: WaterEntry, enqueuedAt: Date) {
        insert(entry)
        pending.append(PendingWaterSync(kind: .save, entryID: entry.id, enqueuedAt: enqueuedAt))
    }

    /// Removes a Fuely entry, tombstones it and queues the HealthKit delete. Any queued save for it
    /// is dropped. The delete is queued even when the save never ran: another process may be saving
    /// it right now, and deleting a sample that doesn't exist is harmless. If that save lands after
    /// the delete ran, `completeSave` and `reconcile` queue another delete. Returns false when there
    /// is no such Fuely entry.
    @discardableResult
    public mutating func delete(entryID: UUID, enqueuedAt: Date) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), entries[index].isDeletable else { return false }
        entries.remove(at: index)
        deletedEntries[entryID] = enqueuedAt
        pending.removeAll { $0.entryID == entryID }
        pending.append(PendingWaterSync(kind: .delete, entryID: entryID, enqueuedAt: enqueuedAt))
        return true
    }

    /// Deletes a Fuely entry seen in History. Unlike `delete(entryID:enqueuedAt:)` it also works for
    /// an entry that is only in HealthKit (older than the local retention, or restored by a read):
    /// that one is tombstoned and its HealthKit delete queued. Other apps' entries are read-only
    /// (DECISIONS W7). Returns false for a read-only or already deleted entry.
    @discardableResult
    public mutating func delete(_ entry: WaterEntry, enqueuedAt: Date) -> Bool {
        if self.entry(id: entry.id) != nil { return delete(entryID: entry.id, enqueuedAt: enqueuedAt) }
        guard entry.isDeletable, !isDeleted(entry.id) else { return false }
        deletedEntries[entry.id] = enqueuedAt
        pending.removeAll { $0.entryID == entry.id }
        pending.append(PendingWaterSync(kind: .delete, entryID: entry.id, enqueuedAt: enqueuedAt))
        return true
    }

    /// The first queued operation whose id is not in `excluding`.
    public func nextPending(excluding: Set<UUID> = []) -> PendingWaterSync? {
        pending.first { !excluding.contains($0.id) }
    }

    /// Records a finished HealthKit save: drops the operation and stores the sample id and `syncedAt`.
    /// If the entry was deleted meanwhile, the sample just written is an orphan: queues its delete
    /// (unless one is still queued).
    public mutating func completeSave(_ operationID: UUID, entryID: UUID, healthKitSampleID: UUID, at syncedAt: Date) {
        pending.removeAll { $0.id == operationID }
        if let index = entries.firstIndex(where: { $0.id == entryID }) {
            entries[index].healthKitSampleID = healthKitSampleID
            entries[index].syncedAt = syncedAt
        } else if isDeleted(entryID) {
            queueDeleteIfNeeded(entryID, at: syncedAt)
        }
    }

    /// Drops a finished (or obsolete) operation.
    public mutating func complete(_ operationID: UUID) {
        pending.removeAll { $0.id == operationID }
    }

    /// Records a failed attempt; the operation stays queued.
    public mutating func recordFailure(_ operationID: UUID, issue: HealthSyncIssue) {
        if let index = pending.firstIndex(where: { $0.id == operationID }) {
            pending[index].attempts += 1
            pending[index].lastIssue = issue
        }
        lastSyncIssue = issue
    }

    /// A push applied jobs without any failure.
    public mutating func clearSyncIssue() {
        lastSyncIssue = nil
    }

    /// Makes the local entries inside `interval` mirror Fuely's samples in HealthKit, as read by a
    /// query that started at `readStartedAt`.
    /// - Entries with queued work are left alone.
    /// - Synced entries missing from HealthKit were deleted in the Health app: removed, but only if
    ///   their sync finished before the read started (a later save may simply not be in the read).
    /// - HealthKit samples missing locally (e.g. after a reinstall) are added, unless a delete is
    ///   queued. Samples of deleted (tombstoned) entries are never added; their delete is queued again.
    /// `healthKitEntries` must be Fuely's own samples (`source == .fuely`); others are ignored.
    public mutating func reconcile(withHealthKit healthKitEntries: [WaterEntry], in interval: DateInterval, readStartedAt: Date) {
        let queued = Set(pending.map(\.entryID))
        let remote = Dictionary(healthKitEntries.filter { $0.source == .fuely }.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        var kept: [WaterEntry] = []
        var seen = Set<UUID>()
        for entry in entries {
            seen.insert(entry.id)
            guard interval.containsHalfOpen(entry.date), !queued.contains(entry.id) else { kept.append(entry); continue }
            if let match = remote[entry.id] {
                var updated = entry
                updated.healthKitSampleID = match.healthKitSampleID ?? entry.healthKitSampleID
                kept.append(updated)
            } else if entry.healthKitSampleID == nil || (entry.syncedAt ?? .distantPast) >= readStartedAt {
                kept.append(entry)
            }
        }
        for (id, entry) in remote where !seen.contains(id) && !queued.contains(id) && interval.containsHalfOpen(entry.date) {
            if isDeleted(id) {
                queueDeleteIfNeeded(id, at: readStartedAt)
            } else {
                var restored = entry
                restored.syncedAt = readStartedAt
                kept.append(restored)
            }
        }
        entries = kept.sorted { $0.date < $1.date }
    }

    /// Forgets synced entries older than `date`; Apple Health keeps the history.
    /// Entries with queued work are always kept.
    public mutating func pruneSyncedEntries(before date: Date) {
        let queued = Set(pending.map(\.entryID))
        entries.removeAll { $0.date < date && $0.healthKitSampleID != nil && !queued.contains($0.id) }
    }

    /// Forgets tombstones of entries deleted before `date`, unless their delete is still queued.
    public mutating func pruneTombstones(deletedBefore date: Date) {
        let queued = Set(pending.map(\.entryID))
        deletedEntries = deletedEntries.filter { $0.value >= date || queued.contains($0.key) }
    }

    private mutating func queueDeleteIfNeeded(_ entryID: UUID, at date: Date) {
        guard !pending.contains(where: { $0.entryID == entryID && $0.kind == .delete }) else { return }
        pending.append(PendingWaterSync(kind: .delete, entryID: entryID, enqueuedAt: date))
    }

    private mutating func insert(_ entry: WaterEntry) {
        entries.removeAll { $0.id == entry.id }
        let index = entries.firstIndex { $0.date > entry.date } ?? entries.endIndex
        entries.insert(entry, at: index)
    }
}

extension DateInterval {
    /// start ≤ date < end (Foundation's `contains` includes the end).
    func containsHalfOpen(_ date: Date) -> Bool { date >= start && date < end }
}
