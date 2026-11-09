import Foundation

/// DECISIONS W7a, "finished days are final": from local midnight every earlier day is read-only.
/// Only drinks on today (by `calendar`, so its time zone and DST) can be deleted; nothing is ever
/// added to a past day. Pass the current time on every check: never cache the answer, so a screen
/// left open across midnight locks its day.
public enum DayEditability {
    /// True when `day` (any instant in it) is today or later relative to `now`.
    public static func isEditable(day: Date, now: Date, calendar: Calendar) -> Bool {
        day >= calendar.startOfDay(for: now)
    }
}
