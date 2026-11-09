import Foundation
import Testing
@testable import FuelyCore

/// DECISIONS W7a: finished days are final from local midnight.
@Suite struct DayEditabilityTests {
    let cal = Calendar.test()

    @Test func todayIsEditable() {
        let now = cal.at(2026, 11, 9, 15)
        #expect(DayEditability.isEditable(day: cal.at(2026, 11, 9, 0), now: now, calendar: cal))
        #expect(DayEditability.isEditable(day: cal.at(2026, 11, 9, 8, 30), now: now, calendar: cal))
        #expect(DayEditability.isEditable(day: cal.at(2026, 11, 9, 23, 59), now: now, calendar: cal))
    }

    @Test func yesterdayAndEarlierAreReadOnly() {
        let now = cal.at(2026, 11, 9, 15)
        #expect(!DayEditability.isEditable(day: cal.at(2026, 11, 8, 15), now: now, calendar: cal))
        #expect(!DayEditability.isEditable(day: cal.at(2026, 11, 8, 23, 59), now: now, calendar: cal))
        #expect(!DayEditability.isEditable(day: cal.at(2026, 10, 1, 12), now: now, calendar: cal))
    }

    @Test func aDayLocksExactlyAtMidnight() {
        let drink = cal.at(2026, 11, 8, 23, 30)
        let beforeMidnight = cal.at(2026, 11, 8, 23, 59).addingTimeInterval(59)
        let midnight = cal.at(2026, 11, 9, 0, 0)
        #expect(DayEditability.isEditable(day: drink, now: beforeMidnight, calendar: cal))
        #expect(!DayEditability.isEditable(day: drink, now: midnight, calendar: cal))
        // The new day's first instant is editable.
        #expect(DayEditability.isEditable(day: midnight, now: midnight, calendar: cal))
    }

    @Test func laterDaysAreNotFinished() {
        let now = cal.at(2026, 11, 9, 15)
        #expect(DayEditability.isEditable(day: cal.at(2026, 11, 10, 9), now: now, calendar: cal))
    }

    @Test func dstSpringForwardDay() {
        // New York, Sun 8 Mar 2026: 02:00 → 03:00, a 23-hour day.
        let ny = Calendar.test("America/New_York")
        let now = ny.at(2026, 3, 8, 3, 30)
        #expect(DayEditability.isEditable(day: ny.at(2026, 3, 8, 0, 30), now: now, calendar: ny))
        #expect(!DayEditability.isEditable(day: ny.at(2026, 3, 7, 23, 59), now: now, calendar: ny))
        #expect(!DayEditability.isEditable(day: ny.at(2026, 3, 8, 23), now: ny.at(2026, 3, 9, 0, 0), calendar: ny))
    }

    @Test func dstFallBackDay() {
        // New York, Sun 1 Nov 2026: 02:00 → 01:00, a 25-hour day. 24 h after 00:10 is still that day.
        let ny = Calendar.test("America/New_York")
        let early = ny.at(2026, 11, 1, 0, 10)
        let late = ny.at(2026, 11, 1, 23, 50)
        #expect(late.timeIntervalSince(early) > .hours(24))
        #expect(DayEditability.isEditable(day: early, now: late, calendar: ny))
        #expect(!DayEditability.isEditable(day: early, now: ny.at(2026, 11, 2, 0, 0), calendar: ny))
    }

    @Test func usesTheCalendarsTimeZone() {
        // 2026-11-08 16:00 UTC (23:00 in Bangkok) seen at 2026-11-08 18:00 UTC (01:00 on the 9th in Bangkok).
        let bangkok = Calendar.test("Asia/Bangkok")
        let utc = Calendar.test("UTC")
        let drink = utc.at(2026, 11, 8, 16)
        let now = utc.at(2026, 11, 8, 18)
        #expect(!DayEditability.isEditable(day: drink, now: now, calendar: bangkok))
        #expect(DayEditability.isEditable(day: drink, now: now, calendar: utc))
    }
}

/// The service refuses to delete a finished day's drink, whatever the UI shows (W7a).
@Suite struct FinishedDayDeleteTests {
    let store = makeTempStore()
    let health = FakeHealthKit()
    let cal = Calendar.test()
    var service: WaterLogService { WaterLogService(store: store, healthKit: health, calendar: cal) }

    @Test func refusesAPastDaysHealthKitOnlyEntry() async throws {
        let old = WaterEntry(date: cal.at(2026, 11, 8, 9), amountML: 250, source: .fuely)
        health.insertFuelySample(old)
        #expect(try await service.delete(old, at: cal.at(2026, 11, 9, 12)) == false)
        #expect(health.fuelySamples[old.id] != nil)
        let log = try store.waterLog()
        #expect(!log.isDeleted(old.id))
        #expect(log.pending.isEmpty)
    }

    @Test func refusesYesterdaysLocalEntryJustAfterMidnight() async throws {
        let (entry, _) = try await service.log(amountML: 300, at: cal.at(2026, 11, 8, 23, 50))
        let midnight = cal.at(2026, 11, 9, 0, 0)
        #expect(try await service.delete(entry, at: midnight) == false)
        #expect(try await service.delete(entryID: entry.id, at: midnight) == false)
        #expect(try store.waterLog().entry(id: entry.id) != nil)
        #expect(health.fuelySamples[entry.id] != nil)
    }

    @Test func stillDeletesTodaysEntryUpToMidnight() async throws {
        let (a, _) = try await service.log(amountML: 300, at: cal.at(2026, 11, 8, 23, 50))
        let (b, _) = try await service.log(amountML: 200, at: cal.at(2026, 11, 8, 23, 55))
        let justBefore = cal.at(2026, 11, 8, 23, 59)
        #expect(try await service.delete(a, at: justBefore))
        #expect(try await service.delete(entryID: b.id, at: justBefore))
        #expect(try store.waterLog().entries.isEmpty)
        #expect(health.fuelySamples.isEmpty)
    }

    @Test func undoCandidateIsNeverAPastDaysEntry() async throws {
        try await service.log(amountML: 300, at: cal.at(2026, 11, 8, 23, 50))
        #expect(try store.waterLog().undoCandidate(now: cal.at(2026, 11, 9, 0, 0), calendar: cal) == nil)
    }
}
