import Foundation
import Testing
@testable import FuelyCore

struct WaterLogTests {
    let cal = Calendar.test()
    var t0: Date { cal.at(2026, 11, 9, 9) }

    @Test func logQueuesASave() {
        var log = WaterLog()
        let entry = WaterEntry(date: t0, amountML: 250)
        log.log(entry, enqueuedAt: t0)
        #expect(log.entries == [entry])
        #expect(log.pending.map(\.kind) == [.save])
        #expect(log.pending.first?.entryID == entry.id)
    }

    @Test func entriesStaySortedByDate() {
        var log = WaterLog()
        let late = WaterEntry(date: t0.addingTimeInterval(3600), amountML: 150)
        let early = WaterEntry(date: t0, amountML: 500)
        log.log(late, enqueuedAt: t0)
        log.log(early, enqueuedAt: t0)
        #expect(log.entries.map(\.id) == [early.id, late.id])
        #expect(log.latestEntry?.id == late.id)
    }

    @Test func deleteBeforeSyncDropsTheSaveAndQueuesADelete() {
        var log = WaterLog()
        let entry = WaterEntry(date: t0, amountML: 250)
        log.log(entry, enqueuedAt: t0)
        let deleted = log.delete(entryID: entry.id, enqueuedAt: t0)
        #expect(deleted)
        #expect(log.entries.isEmpty)
        #expect(log.pending.map(\.kind) == [.delete])
    }

    @Test func deleteUnknownOrExternalEntryIsRejected() {
        var log = WaterLog(entries: [WaterEntry(date: t0, amountML: 200, source: .external(name: "Other"))])
        let unknown = log.delete(entryID: UUID(), enqueuedAt: t0)
        let external = log.delete(entryID: log.entries[0].id, enqueuedAt: t0)
        #expect(!unknown)
        #expect(!external)
        #expect(log.pending.isEmpty)
    }

    @Test func completeSaveStoresTheSampleID() throws {
        var log = WaterLog()
        let entry = WaterEntry(date: t0, amountML: 250)
        log.log(entry, enqueuedAt: t0)
        let op = try #require(log.nextPending())
        let sample = UUID()
        log.completeSave(op.id, entryID: entry.id, healthKitSampleID: sample, at: t0)
        #expect(log.pending.isEmpty)
        #expect(log.entry(id: entry.id)?.healthKitSampleID == sample)
    }

    @Test func nextPendingIsFIFOAndSkipsExcluded() throws {
        var log = WaterLog()
        let a = WaterEntry(date: t0, amountML: 100), b = WaterEntry(date: t0, amountML: 200)
        log.log(a, enqueuedAt: t0)
        log.log(b, enqueuedAt: t0)
        let first = try #require(log.nextPending())
        #expect(first.entryID == a.id)
        #expect(log.nextPending(excluding: [first.id])?.entryID == b.id)
    }

    @Test func reconcileMirrorsHealthKit() {
        let today = DateInterval(start: cal.at(2026, 11, 9), end: cal.at(2026, 11, 10))
        let synced = WaterEntry(date: t0, amountML: 250, healthKitSampleID: UUID())
        let deletedInHealth = WaterEntry(date: t0, amountML: 300, healthKitSampleID: UUID())
        let unsynced = WaterEntry(date: t0, amountML: 150)
        let yesterday = WaterEntry(date: cal.at(2026, 11, 8, 9), amountML: 400, healthKitSampleID: UUID())
        var log = WaterLog(entries: [synced, deletedInHealth, yesterday])
        log.log(unsynced, enqueuedAt: t0)

        let restored = WaterEntry(date: t0.addingTimeInterval(60), amountML: 500, healthKitSampleID: UUID())
        let external = WaterEntry(date: t0, amountML: 999, source: .external(name: "Other"), healthKitSampleID: UUID())
        log.reconcile(withHealthKit: [synced, restored, external], in: today, readStartedAt: t0)

        #expect(Set(log.entries.map(\.id)) == [synced.id, unsynced.id, yesterday.id, restored.id])
    }

    @Test func reconcileDoesNotResurrectAnEntryWithAQueuedDelete() {
        let today = DateInterval(start: cal.at(2026, 11, 9), end: cal.at(2026, 11, 10))
        let entry = WaterEntry(date: t0, amountML: 250, healthKitSampleID: UUID())
        var log = WaterLog(entries: [entry])
        log.delete(entryID: entry.id, enqueuedAt: t0)
        log.reconcile(withHealthKit: [entry], in: today, readStartedAt: t0)
        #expect(log.entries.isEmpty)
    }

    @Test func pruneKeepsUnsyncedAndRecentEntries() {
        let old = WaterEntry(date: cal.at(2026, 10, 1, 9), amountML: 250, healthKitSampleID: UUID())
        let oldUnsynced = WaterEntry(date: cal.at(2026, 10, 1, 10), amountML: 250)
        let recent = WaterEntry(date: t0, amountML: 250, healthKitSampleID: UUID())
        var log = WaterLog(entries: [old, recent])
        log.log(oldUnsynced, enqueuedAt: t0)
        log.pruneSyncedEntries(before: cal.at(2026, 11, 2))
        #expect(log.entries.map(\.id) == [oldUnsynced.id, recent.id])
    }

    // MARK: Tombstones (an undo racing an in-flight save)

    @Test func saveThatLandsAfterADeleteQueuesAnotherDelete() throws {
        var log = WaterLog()
        let entry = WaterEntry(date: t0, amountML: 250)
        log.log(entry, enqueuedAt: t0)
        let save = try #require(log.nextPending())
        // Undo while the save is in flight; another push applies the delete first.
        log.delete(entryID: entry.id, enqueuedAt: t0)
        let delete = try #require(log.nextPending())
        log.complete(delete.id)
        #expect(log.pending.isEmpty)

        log.completeSave(save.id, entryID: entry.id, healthKitSampleID: UUID(), at: t0)
        #expect(log.entry(id: entry.id) == nil)
        #expect(log.pending.map(\.kind) == [.delete])
        #expect(log.pending.first?.entryID == entry.id)
    }

    @Test func reconcileNeverRestoresADeletedEntryAndDeletesItAgain() throws {
        let today = DateInterval(start: cal.at(2026, 11, 9), end: cal.at(2026, 11, 10))
        var log = WaterLog()
        let entry = WaterEntry(date: t0, amountML: 250)
        log.log(entry, enqueuedAt: t0)
        log.delete(entryID: entry.id, enqueuedAt: t0)
        log.complete(try #require(log.nextPending()).id)

        var orphan = entry
        orphan.healthKitSampleID = UUID()
        log.reconcile(withHealthKit: [orphan], in: today, readStartedAt: t0 + 60)
        #expect(log.entries.isEmpty)
        #expect(log.pending.map(\.kind) == [.delete])
        // Reconciling again does not queue a second delete.
        log.reconcile(withHealthKit: [orphan], in: today, readStartedAt: t0 + 120)
        #expect(log.pending.count == 1)
    }

    @Test func tombstonesArePrunedAfterTheirRetention() throws {
        var log = WaterLog()
        let old = WaterEntry(date: cal.at(2026, 11, 1, 9), amountML: 250)
        let recent = WaterEntry(date: t0, amountML: 250)
        log.log(old, enqueuedAt: old.date)
        log.log(recent, enqueuedAt: t0)
        log.delete(entryID: old.id, enqueuedAt: old.date)
        log.delete(entryID: recent.id, enqueuedAt: t0)
        while let op = log.nextPending() { log.complete(op.id) }
        log.pruneTombstones(deletedBefore: cal.at(2026, 11, 2))
        #expect(!log.isDeleted(old.id))
        #expect(log.isDeleted(recent.id))
    }

    // MARK: Stale reads

    @Test func reconcileKeepsEntriesSyncedAfterTheReadStarted() throws {
        let today = DateInterval(start: cal.at(2026, 11, 9), end: cal.at(2026, 11, 10))
        var log = WaterLog()
        let before = WaterEntry(date: t0, amountML: 100)
        let during = WaterEntry(date: t0, amountML: 200)
        log.log(before, enqueuedAt: t0)
        log.log(during, enqueuedAt: t0)
        let readStart = t0 + 60
        log.completeSave(try #require(log.nextPending()).id, entryID: before.id, healthKitSampleID: UUID(), at: t0 + 30)
        log.completeSave(try #require(log.nextPending()).id, entryID: during.id, healthKitSampleID: UUID(), at: t0 + 90)

        // The read saw neither: `before` was deleted in Health, `during` landed after the read.
        log.reconcile(withHealthKit: [], in: today, readStartedAt: readStart)
        #expect(log.entries.map(\.id) == [during.id])
    }
}
