import Foundation
import Testing
@testable import FuelyCore

@Suite struct WeeklyRecapArchiveTests {
    let cal = Calendar.test()
    let store = makeTempStore()

    private func week(_ index: Int) -> RecapWeek {
        RecapWeek(mondayYear: 2026, month: 1, day: 5).advanced(by: index, calendar: cal)
    }

    @Test func frozenRecapHoldsEverythingTheScreenShows() {
        let judgement = makeJudgement(week: week(0), waterDays: 6, sleep: [84, 86, 79, 90], workoutDays: 4)
        let created = cal.at(2026, 1, 12, 8)
        let recap = WeeklyRecap.make(from: judgement, createdAt: created, calendar: cal, locale: Locale(identifier: "en_US"))
        #expect(recap.week == week(0))
        #expect(recap.id == week(0))
        #expect(recap.createdAt == created)
        #expect(recap.mood == .allStrong)
        #expect(!recap.headline.isEmpty)
        #expect(!recap.supporting.isEmpty)
        #expect(!recap.closing.isEmpty)
        #expect(!recap.closingIsSuggestion)
        #expect(recap.rows.map(\.ring) == [.water, .sleep, .workouts])
        #expect(recap.rows.allSatisfy { !$0.line.isEmpty })
        #expect(recap.row(.workouts)?.fraction == 4.0 / 3)
        #expect(recap.numbers == WeeklyRecap.Numbers(waterDaysReached: 6, waterGoalML: 2400, bestWaterDayML: 2400,
                                                     sleepTrackedNights: 4, sleepAverage: 85, sleepNightsAtGoal: 3,
                                                     sleepGoal: 80, workoutDays: 4, workoutGoalDays: 3))
        #expect(recap.weekStart(calendar: cal) == cal.at(2026, 1, 5))
        #expect(recap.weekEnd(calendar: cal) == cal.at(2026, 1, 11))
    }

    @Test func recapRoundTripsThroughJSON() throws {
        let recap = sampleRecap(week: week(3))
        let data = try JSONEncoder().encode(recap)
        #expect(try JSONDecoder().decode(WeeklyRecap.self, from: data) == recap)
    }

    @Test func savesOnePerWeekOldestFirstAndNeverOverwrites() {
        var archive = WeeklyRecapArchive()
        let saved1 = archive.save(sampleRecap(week: week(2)))
        #expect(saved1)
        let saved2 = archive.save(sampleRecap(week: week(0)))
        #expect(saved2)
        let saved3 = archive.save(sampleRecap(week: week(1)))
        #expect(saved3)
        #expect(archive.recaps.map(\.week) == [week(0), week(1), week(2)])

        // Frozen (WR8): a second recap for the same week is refused.
        let first = archive.recap(for: week(1))
        let saved4 = archive.save(sampleRecap(week: week(1), waterDays: 1))
        #expect(!saved4)
        #expect(archive.recap(for: week(1)) == first)
        #expect(archive.recap(for: week(9)) == nil)
        #expect(archive.weeks == [week(0), week(1), week(2)])
    }

    @Test func keepsTheLatestTwelveWeeks() {
        var archive = WeeklyRecapArchive()
        for index in 0..<15 { archive.save(sampleRecap(week: week(index))) }
        #expect(archive.recaps.count == 12)
        #expect(archive.recaps.first?.week == week(3))
        #expect(archive.recaps.last?.week == week(14))
        // Older than everything kept: not saved.
        let saved5 = archive.save(sampleRecap(week: week(0)))
        #expect(!saved5)
        #expect(archive.recaps.count == 12)
        #expect(archive.recap(for: week(0)) == nil)
    }

    @Test func lastShownWeekOnlyMovesForward() {
        var archive = WeeklyRecapArchive()
        #expect(archive.lastShownWeek == nil)
        #expect(!archive.hasBeenShown(week(0)))
        archive.markShown(week(4))
        #expect(archive.hasBeenShown(week(4)))
        #expect(archive.hasBeenShown(week(2)))
        #expect(!archive.hasBeenShown(week(5)))
        archive.markShown(week(1))
        #expect(archive.lastShownWeek == week(4))
    }

    // MARK: Store

    @Test func emptyStoreHasNoRecaps() throws {
        #expect(try store.weeklyRecaps() == WeeklyRecapArchive())
    }

    @Test func storeRoundTrip() throws {
        let recap = sampleRecap(week: week(0))
        try store.updateWeeklyRecaps {
            $0.save(recap)
            $0.markShown(recap.week)
        }
        let archive = try FuelyStore(directory: store.directory).weeklyRecaps()
        #expect(archive.recaps == [recap])
        #expect(archive.lastShownWeek == week(0))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: .weeklyRecaps)))
        #expect(object is [String: Any])
        #expect(store.url(for: .weeklyRecaps).lastPathComponent == "weekly-recaps.json")
    }

    private func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.url(for: .weeklyRecaps))
    }

    @Test func tolerantDecoding() throws {
        try write("{}")
        #expect(try store.weeklyRecaps() == WeeklyRecapArchive())

        // Missing fields take defaults; an unreadable recap or row is dropped, the rest stays.
        try write(#"""
        {"lastShownWeek": "2026-01-12", "future": 1, "recaps": [
            {"week": "2026-01-12", "headline": "A good week.", "mood": "somethingNew",
             "rows": [{"ring": "water", "number": "6"}, {"ring": "steps"}], "extra": true},
            {"headline": "No week"},
            {"week": "2026-01-05", "mood": "low"},
            {"week": "2026-01-05", "mood": "mixed"},
            "junk"
        ]}
        """#)
        let archive = try store.weeklyRecaps()
        #expect(archive.recaps.map(\.week.description) == ["2026-01-05", "2026-01-12"])
        #expect(archive.lastShownWeek == week(1))
        let recap = try #require(archive.recap(for: week(1)))
        #expect(recap.headline == "A good week.")
        #expect(recap.mood == .notEnoughData)
        #expect(recap.rows.map(\.ring) == [.water])
        #expect(recap.rows.first?.number == "6")
        #expect(recap.rows.first?.unit == "")
        #expect(recap.rows.first?.shortNumber == "6")
        #expect(recap.rows.first?.caption == "")
        #expect(recap.rows.first?.line == "")
        #expect(recap.rows.first?.spokenSummary == "Water, 6.")
        #expect(recap.numbers == WeeklyRecap.Numbers())
        #expect(recap.closingIsSuggestion)
        // The first of two recaps for one week is kept.
        #expect(archive.recap(for: week(0))?.mood == .low)

        try write(#"{"lastShownWeek": 12, "recaps": []}"#)
        #expect(try store.weeklyRecaps().lastShownWeek == nil)
    }

    @Test func corruptFileThrows() throws {
        try write("not json")
        #expect(throws: (any Error).self) { try store.weeklyRecaps() }
    }
}
