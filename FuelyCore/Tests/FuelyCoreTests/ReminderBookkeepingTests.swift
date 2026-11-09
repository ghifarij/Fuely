import Foundation
import Testing
@testable import FuelyCore

struct ReminderBookkeepingTests {
    let cal = Calendar.test()

    @Test func waterCounterCountsWithinADay() {
        var book = ReminderBookkeeping()
        let morning = cal.at(2026, 11, 9, 10)
        #expect(book.waterRemindersSent(onDayOf: morning, calendar: cal) == 0)
        book.recordWaterReminder(at: morning, calendar: cal)
        book.recordWaterReminder(at: cal.at(2026, 11, 9, 15), calendar: cal)
        #expect(book.waterRemindersSent(onDayOf: cal.at(2026, 11, 9, 21), calendar: cal) == WaterReminderPolicy.maxPerDay)
    }

    @Test func waterCounterRollsOverAtMidnight() {
        var book = ReminderBookkeeping()
        book.recordWaterReminder(at: cal.at(2026, 11, 9, 10), calendar: cal)
        book.recordWaterReminder(at: cal.at(2026, 11, 9, 15), calendar: cal)
        #expect(book.waterRemindersSent(onDayOf: cal.at(2026, 11, 10, 0, 1), calendar: cal) == 0)
        book.recordWaterReminder(at: cal.at(2026, 11, 10, 9), calendar: cal)
        #expect(book.waterRemindersSent(onDayOf: cal.at(2026, 11, 10, 12), calendar: cal) == 1)
    }

    @Test func workoutReminderIsPerDay() {
        var book = ReminderBookkeeping()
        let day = cal.at(2026, 11, 9, 8)
        book.recordWorkoutReminder(.nudge(workoutsToGo: 2, daysLeft: 3), at: day)
        #expect(book.workoutRemindedToday(now: cal.at(2026, 11, 9, 20), calendar: cal))
        #expect(!book.workoutRemindedToday(now: cal.at(2026, 11, 10, 8), calendar: cal))
        #expect(!book.behindNoteSentThisWeek(now: day, calendar: cal))
    }

    @Test func behindNoteLastsUntilSunday() {
        var book = ReminderBookkeeping()
        // Wednesday 2026-11-11.
        book.recordWorkoutReminder(.behind(workoutsToGo: 3, daysLeft: 2), at: cal.at(2026, 11, 11, 8))
        #expect(book.behindNoteSentThisWeek(now: cal.at(2026, 11, 15, 23, 59), calendar: cal)) // Sunday
        #expect(!book.behindNoteSentThisWeek(now: cal.at(2026, 11, 16, 0, 1), calendar: cal))  // next Monday
    }

    @Test func persistsThroughTheStore() throws {
        let store = makeTempStore()
        let now = cal.at(2026, 11, 9, 8)
        try store.updateReminders { $0.recordWorkoutReminder(.behind(workoutsToGo: 1, daysLeft: 0), at: now) }
        let book = try FuelyStore(directory: store.directory).reminders()
        #expect(book.workoutRemindedToday(now: now, calendar: cal))
        #expect(book.behindNoteSentThisWeek(now: now, calendar: cal))
    }
}
