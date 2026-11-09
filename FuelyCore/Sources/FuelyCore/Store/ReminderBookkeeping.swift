import Foundation

/// What reminders already went out, so the policies can enforce their limits (DECISIONS R1, R3, R4).
/// Stores the instants of the last sends; counters roll over by calendar day / Monday week.
///
/// **How Fuely knows a reminder went out (R5).** Reminders are local notifications with a fixed fire
/// date, scheduled ahead of time; iOS gives no callback when one is shown while Fuely isn't running.
/// So `scheduled` remembers every request Fuely handed to iOS. Every reschedule first calls
/// `markDelivered(asOf:)`: a request whose fire date has passed was delivered by iOS (Fuely only ever
/// removes requests at a reschedule, and only those still in the future), so it is counted as sent
/// at its fire date. A request removed before its fire date (a drink moved it, the toggle went off)
/// never counts. Counted even if the user had muted it (Focus, notification settings): it still
/// "went out" as far as the 2-per-day and once-a-week limits are concerned.
public struct ReminderBookkeeping: Codable, Sendable, Hashable {
    /// When the last water reminder was sent, and how many were sent that day.
    public private(set) var lastWaterReminderAt: Date?
    public private(set) var waterRemindersOnLastDay: Int
    /// When the last workout reminder was sent.
    public private(set) var lastWorkoutReminderAt: Date?
    /// When the week's "behind" note was sent (slack < 0, then silent for the week).
    public private(set) var behindNoteSentAt: Date?
    /// Requests currently handed to iOS (pending, or delivered since the last reschedule).
    public private(set) var scheduled: [ScheduledReminder]

    public init() {
        waterRemindersOnLastDay = 0
        scheduled = []
    }

    private enum CodingKeys: String, CodingKey {
        case lastWaterReminderAt, waterRemindersOnLastDay, lastWorkoutReminderAt, behindNoteSentAt, scheduled
    }

    /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastWaterReminderAt = try c.decodeIfPresent(Date.self, forKey: .lastWaterReminderAt)
        waterRemindersOnLastDay = try c.decodeIfPresent(Int.self, forKey: .waterRemindersOnLastDay) ?? 0
        lastWorkoutReminderAt = try c.decodeIfPresent(Date.self, forKey: .lastWorkoutReminderAt)
        behindNoteSentAt = try c.decodeIfPresent(Date.self, forKey: .behindNoteSentAt)
        // An entry Fuely can't read (e.g. a kind from a newer version) is dropped, not fatal.
        let lossy = (try? c.decodeIfPresent([Lossy<ScheduledReminder>].self, forKey: .scheduled)) ?? nil
        scheduled = lossy?.compactMap(\.value) ?? []
    }

    /// Remembers the requests just handed to iOS (replaces the previous set).
    public mutating func setScheduled(_ reminders: [ScheduledReminder]) {
        scheduled = reminders.sorted { $0.fireDate < $1.fireDate }
    }

    /// Counts every scheduled request whose fire date is at or before `now` as sent (see the type's
    /// note) and forgets it. Returns those, oldest first.
    @discardableResult
    public mutating func markDelivered(asOf now: Date, calendar: Calendar) -> [ScheduledReminder] {
        let delivered = scheduled.filter { $0.fireDate <= now }.sorted { $0.fireDate < $1.fireDate }
        for reminder in delivered {
            switch reminder.kind {
            case .water:
                recordWaterReminder(at: reminder.fireDate, calendar: calendar)
            case .workout:
                lastWorkoutReminderAt = reminder.fireDate
            case .workoutBehind:
                lastWorkoutReminderAt = reminder.fireDate
                behindNoteSentAt = reminder.fireDate
            }
        }
        scheduled.removeAll { $0.fireDate <= now }
        return delivered
    }

    /// Water reminders sent on the calendar day of `now` (0 after midnight).
    public func waterRemindersSent(onDayOf now: Date, calendar: Calendar) -> Int {
        guard let last = lastWaterReminderAt, calendar.isDate(last, inSameDayAs: now) else { return 0 }
        return waterRemindersOnLastDay
    }

    public mutating func recordWaterReminder(at date: Date, calendar: Calendar) {
        waterRemindersOnLastDay = waterRemindersSent(onDayOf: date, calendar: calendar) + 1
        lastWaterReminderAt = date
    }

    /// Whether a workout reminder already went out on the day of `now` (max 1 per day, R4).
    public func workoutRemindedToday(now: Date, calendar: Calendar) -> Bool {
        guard let last = lastWorkoutReminderAt else { return false }
        return calendar.isDate(last, inSameDayAs: now)
    }

    /// Whether the "behind" note went out in the Monday–Sunday week of `now` (R3).
    public func behindNoteSentThisWeek(now: Date, calendar: Calendar) -> Bool {
        guard let sent = behindNoteSentAt else { return false }
        return WorkoutAggregation.weekStart(containing: sent, calendar: calendar)
            == WorkoutAggregation.weekStart(containing: now, calendar: calendar)
    }

    /// Records a sent workout reminder; a `.behind` note also silences the rest of the week.
    public mutating func recordWorkoutReminder(_ reminder: WorkoutReminder, at date: Date) {
        lastWorkoutReminderAt = date
        if case .behind = reminder { behindNoteSentAt = date }
    }
}

/// A notification request Fuely handed to iOS: enough to count it once its fire date passes.
public struct ScheduledReminder: Codable, Sendable, Hashable {
    public var id: String
    public var kind: PlannedReminder.Kind
    public var fireDate: Date

    public init(id: String, kind: PlannedReminder.Kind, fireDate: Date) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
    }
}

/// Decodes a value or nil, so one bad element doesn't fail a whole array.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
