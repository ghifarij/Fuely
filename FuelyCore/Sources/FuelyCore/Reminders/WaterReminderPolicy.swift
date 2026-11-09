import Foundation

/// When a water reminder may fire (DECISIONS R1): at most 2 per day, only behind pace,
/// only inside the drinking window, only when enabled. Decides; does not schedule.
public enum WaterReminderPolicy {
    public static let maxPerDay = 2

    public static func shouldRemind(now: Date, todayTotalML: Int, goalML: Int, window: DrinkingWindow,
                                    enabled: Bool, remindersSentToday: Int, calendar: Calendar) -> Bool {
        guard enabled, remindersSentToday < maxPerDay, window.contains(now, calendar: calendar) else { return false }
        return WaterPace.progress(totalML: todayTotalML, goalML: goalML, window: window, at: now, calendar: calendar)
            .status == .behind
    }

    /// The earliest moment at or after `now` from which the user is behind pace if they drink
    /// nothing more: `now` if already behind, otherwise the instant the pace overtakes the total
    /// (any moment after it is behind). nil when no reminder can fire today.
    public static func nextReminderDate(after now: Date, todayTotalML: Int, goalML: Int, window: DrinkingWindow,
                                        enabled: Bool, remindersSentToday: Int, calendar: Calendar) -> Date? {
        guard enabled, remindersSentToday < maxPerDay, goalML > 0, todayTotalML < goalML,
              let interval = window.interval(on: now, calendar: calendar), now < interval.end else { return nil }
        if shouldRemind(now: now, todayTotalML: todayTotalML, goalML: goalML, window: window,
                        enabled: enabled, remindersSentToday: remindersSentToday, calendar: calendar) {
            return now
        }
        let fraction = Double(max(todayTotalML, 0)) / Double(goalML)
        let crossing = interval.start.addingTimeInterval(fraction * interval.duration)
        return max(crossing, now)
    }
}
