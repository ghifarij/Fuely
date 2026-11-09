import Foundation
import Testing
@testable import FuelyCore

@Suite struct ReminderCopyTests {
    @Test func firstWaterReminder() {
        let copy = ReminderCopy.water(slot: 1, totalML: 1200, goalML: 2400)
        #expect(copy.title == "Time for a glass of water")
        #expect(copy.body == "1.2 L of 2.4 L so far. A glass now gets you back on pace.")
    }

    @Test func secondWaterReminder() {
        let copy = ReminderCopy.water(slot: 2, totalML: 850, goalML: 2400)
        #expect(copy.title == "Still time to catch up")
        #expect(copy.body == "850 ml of 2.4 L so far. A glass or two gets you back on pace.")
    }

    @Test func waterWithNothingLoggedYet() {
        #expect(ReminderCopy.water(slot: 1, totalML: 0, goalML: 2400).body
            == "Nothing logged yet today. A glass now gets you started.")
        #expect(ReminderCopy.water(slot: 2, totalML: 0, goalML: 2400).body
            == "Nothing logged yet today. A glass or two gets you going.")
    }

    @Test func workoutNudgeMatchesTheDecisionExample() {
        let copy = ReminderCopy.workout(.nudge(workoutsToGo: 2, daysLeft: 3), minMinutesPerDay: 50)
        #expect(copy.title == "Room for a workout")
        #expect(copy.body == "2 workouts to go, 3 days left this week. You've got this.")
    }

    @Test func workoutDay() {
        let copy = ReminderCopy.workout(.workoutDay(workoutsToGo: 1, daysLeft: 1), minMinutesPerDay: 50)
        #expect(copy.title == "Today's a workout day")
        #expect(copy.body == "1 workout to go, 1 day left this week. 50 minutes today keeps your week on track.")
    }

    @Test func behindIsQuietAndKind() {
        let copy = ReminderCopy.workout(.behind(workoutsToGo: 3, daysLeft: 2), minMinutesPerDay: 50)
        #expect(copy.title == "Your week so far")
        #expect(copy.body == "3 workouts to go, 2 days left. Every workout still counts. No more notes this week.")
    }

    @Test func neverNags() {
        let all = [
            ReminderCopy.water(slot: 1, totalML: 500, goalML: 2400),
            ReminderCopy.water(slot: 2, totalML: 500, goalML: 2400),
            ReminderCopy.workout(.nudge(workoutsToGo: 2, daysLeft: 3), minMinutesPerDay: 50),
            ReminderCopy.workout(.workoutDay(workoutsToGo: 2, daysLeft: 2), minMinutesPerDay: 50),
            ReminderCopy.workout(.behind(workoutsToGo: 2, daysLeft: 1), minMinutesPerDay: 50),
        ]
        for copy in all {
            let text = (copy.title + " " + copy.body).lowercased()
            for word in ["don't forget", "you missed", "failed", "must", "behind", "!"] {
                #expect(!text.contains(word), "\(text) contains \(word)")
            }
        }
    }

    @Test func permissionNotes() {
        #expect(SettingsCopy.notificationPermission(.allowed) == nil)
        #expect(SettingsCopy.notificationPermission(.denied)
            == "Notifications are off for Fuely. Turn them on in Settings to get reminders.")
        #expect(SettingsCopy.notificationPermission(.notDetermined)
            == "Allow notifications so Fuely can send reminders.")
    }
}

@Suite struct RemindersSettingMigrationTests {
    func decode(_ json: String) throws -> FuelySettings {
        try JSONDecoder().decode(FuelySettings.self, from: Data(json.utf8))
    }

    @Test func defaultsOn() throws {
        #expect(FuelySettings.default.remindersEnabled)
        #expect(try decode("{}").remindersEnabled)
    }

    @Test func oldWaterToggleCarriesOver() throws {
        #expect(try !decode(#"{"waterRemindersEnabled": false}"#).remindersEnabled)
        #expect(try decode(#"{"waterRemindersEnabled": true}"#).remindersEnabled)
    }

    @Test func newKeyWins() throws {
        #expect(try decode(#"{"waterRemindersEnabled": false, "remindersEnabled": true}"#).remindersEnabled)
    }

    @Test func writesOnlyTheNewKey() throws {
        var settings = FuelySettings.default
        settings.remindersEnabled = false
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        #expect(json.contains("\"remindersEnabled\":false"))
        #expect(!json.contains("waterRemindersEnabled"))
        #expect(try !decode(json).remindersEnabled)
    }
}
