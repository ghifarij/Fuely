import Foundation

/// Every tunable number of the weekly recap (DECISIONS WR4, WR4a, WR8) in one place.
public struct WeeklyRecapConfig: Sendable, Hashable {
    /// Water: days at the goal for a perfect week (7 of 7).
    public var waterPerfectDays: Int
    /// Water: days at the goal from which the ring is strong (WR4a: ≥ 5 of 7).
    public var waterStrongDays: Int
    /// Water: days at the goal from which the week is mixed (3–4); fewer is low.
    public var waterMixedDays: Int
    /// Sleep: tracked nights needed for a verdict (WR4: fewer than 3 → none).
    public var minimumSleepNights: Int
    /// Sleep: an average this many points or fewer below the goal is mid-tier, lower is low
    /// (goal 80 → 70–79 mid, below 70 low). At or above the goal is strong (WR4a).
    public var sleepMidMargin: Int
    /// Recaps kept, newest weeks first (WR8).
    public var keptRecaps: Int

    public init(waterPerfectDays: Int = 7, waterStrongDays: Int = 5, waterMixedDays: Int = 3,
                minimumSleepNights: Int = 3, sleepMidMargin: Int = 10, keptRecaps: Int = 12) {
        self.waterPerfectDays = waterPerfectDays
        self.waterStrongDays = waterStrongDays
        self.waterMixedDays = waterMixedDays
        self.minimumSleepNights = minimumSleepNights
        self.sleepMidMargin = sleepMidMargin
        self.keptRecaps = keptRecaps
    }

    public static let `default` = WeeklyRecapConfig()
}

/// A Monday–Sunday week (DECISIONS K2), named by its Monday's calendar date. Unlike an instant,
/// the name survives time zone changes, so a saved recap always belongs to the same week.
public struct RecapWeek: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The Monday.
    public let year: Int
    public let month: Int
    public let day: Int

    public init(mondayYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The week containing `date`, regardless of the calendar's `firstWeekday`.
    public init(containing date: Date, calendar: Calendar) {
        let monday = WorkoutAggregation.weekStart(containing: date, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: monday)
        self.init(mondayYear: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Monday 00:00 in `calendar`.
    public func start(calendar: Calendar) -> Date {
        date(ofDay: 0, calendar: calendar)
    }

    /// Sunday 00:00 in `calendar`.
    public func lastDay(calendar: Calendar) -> Date {
        date(ofDay: 6, calendar: calendar)
    }

    /// The start of a day of the week, 0 = Monday … 6 = Sunday.
    public func date(ofDay index: Int, calendar: Calendar) -> Date {
        // Via noon, so a day whose midnight is skipped by a DST change still resolves.
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
        let day = calendar.date(byAdding: .day, value: index, to: noon) ?? noon
        return calendar.startOfDay(for: day)
    }

    /// The week `weeks` later (negative = earlier).
    public func advanced(by weeks: Int, calendar: Calendar) -> RecapWeek {
        let noon = start(calendar: calendar).addingTimeInterval(12 * 3600)
        let moved = calendar.date(byAdding: .day, value: 7 * weeks, to: noon) ?? noon
        return RecapWeek(containing: moved, calendar: calendar)
    }

    /// The ISO 8601 week number (1–53); the same in every time zone.
    public var isoWeekNumber: Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .gmt
        let date = iso.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
        return iso.component(.weekOfYear, from: date)
    }

    public static func < (lhs: RecapWeek, rhs: RecapWeek) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// "2026-11-09", also the stored form.
    public var description: String {
        let pad = { (value: Int, width: Int) in
            String(repeating: "0", count: max(width - String(value).count, 0)) + String(value)
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }
}

extension RecapWeek: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not a week: \(text)"))
        }
        self.init(mondayYear: parts[0], month: parts[1], day: parts[2])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
