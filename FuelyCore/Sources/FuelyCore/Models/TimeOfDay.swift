import Foundation

/// A wall-clock time (hour and minute) with no date, e.g. 05:00 or 22:00.
public struct TimeOfDay: Codable, Sendable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int

    /// Values are clamped to 0–23 and 0–59.
    public init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    private enum CodingKeys: String, CodingKey {
        case hour, minute
    }

    /// Tolerant: missing fields are 0, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hour: try c.decodeIfPresent(Int.self, forKey: .hour) ?? 0,
                  minute: try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// This time on the calendar day containing `day`. A time skipped by a DST jump
    /// resolves to the next valid instant.
    public func date(on day: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
            ?? calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(minutesSinceMidnight * 60))
    }
}

/// The part of the day in which the user drinks; water pace runs over it (DECISIONS W8).
public struct DrinkingWindow: Codable, Sendable, Hashable {
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    /// 05:00–22:00 (DECISIONS W8).
    public static let `default` = DrinkingWindow(start: TimeOfDay(hour: 5), end: TimeOfDay(hour: 22))

    private enum CodingKeys: String, CodingKey {
        case start, end
    }

    /// Tolerant: a missing bound takes the default window's, unknown fields are ignored.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try c.decodeIfPresent(TimeOfDay.self, forKey: .start) ?? Self.default.start,
                  end: try c.decodeIfPresent(TimeOfDay.self, forKey: .end) ?? Self.default.end)
    }

    /// The window must start before it ends on the same day.
    public var isValid: Bool { start < end }

    /// The window on the calendar day containing `day`, or nil when the window is invalid.
    public func interval(on day: Date, calendar: Calendar) -> DateInterval? {
        guard isValid else { return nil }
        let startDate = start.date(on: day, calendar: calendar)
        let endDate = end.date(on: day, calendar: calendar)
        guard endDate > startDate else { return nil }
        return DateInterval(start: startDate, end: endDate)
    }

    /// Whether `date` is inside the window: start inclusive, end exclusive.
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard let interval = interval(on: date, calendar: calendar) else { return false }
        return date >= interval.start && date < interval.end
    }
}
