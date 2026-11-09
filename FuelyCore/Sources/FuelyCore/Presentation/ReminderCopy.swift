import Foundation

/// The words in reminder notifications (DECISIONS R1, R3, R4). Encouraging, never nagging:
/// no "don't forget", no "you missed", no exclamation marks. English, ml / L (P6).
public enum ReminderCopy {
    /// Water reminder `slot` (1 or 2) of the day, written for its fire time with today's total.
    public static func water(slot: Int, totalML: Int, goalML: Int) -> (title: String, body: String) {
        let first = slot <= 1
        let title = first ? "Time for a glass of water" : "Still time to catch up"
        guard totalML > 0 else {
            return (title, first ? "Nothing logged yet today. A glass now gets you started."
                                 : "Nothing logged yet today. A glass or two gets you going.")
        }
        let soFar = "\(FuelyFormat.water(totalML)) of \(FuelyFormat.water(goalML)) so far."
        return (title, soFar + (first ? " A glass now gets you back on pace." : " A glass or two gets you back on pace."))
    }

    /// The morning workout note.
    public static func workout(_ reminder: WorkoutReminder, minMinutesPerDay: Int) -> (title: String, body: String) {
        switch reminder {
        case let .nudge(toGo, daysLeft):
            ("Room for a workout", "\(weekStatus(toGo, daysLeft)) this week. You've got this.")
        case let .workoutDay(toGo, daysLeft):
            ("Today's a workout day",
             "\(weekStatus(toGo, daysLeft)) this week. \(FuelyFormat.count(minMinutesPerDay, "minute")) today keeps your week on track.")
        case let .behind(toGo, daysLeft):
            ("Your week so far",
             "\(weekStatus(toGo, daysLeft)). Every workout still counts. No more notes this week.")
        }
    }

    /// "2 workouts to go, 3 days left".
    private static func weekStatus(_ toGo: Int, _ daysLeft: Int) -> String {
        "\(FuelyFormat.count(toGo, "workout")) to go, \(FuelyFormat.count(daysLeft, "day")) left"
    }
}

extension SettingsCopy {
    /// The note under the Reminders toggle when iOS won't show Fuely's notifications; nil when fine.
    public static func notificationPermission(_ permission: NotificationPermission) -> String? {
        switch permission {
        case .allowed: nil
        case .denied: "Notifications are off for Fuely. Turn them on in Settings to get reminders."
        case .notDetermined: "Allow notifications so Fuely can send reminders."
        }
    }
}
