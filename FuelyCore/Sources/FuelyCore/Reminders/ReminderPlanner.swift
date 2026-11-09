import Foundation

/// One local notification Fuely wants pending: when it fires and what it says.
public struct PlannedReminder: Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        /// Behind water pace (R1).
        case water
        /// Workout nudge (slack 1) or "today's a workout day" (slack 0) (R3).
        case workout
        /// The week's one quiet "behind" note (slack < 0), then silence (R3).
        case workoutBehind
    }

    /// Stable per slot and day ("fuely.water.2026-11-09.1", "fuely.workout.2026-11-10"), so a
    /// reschedule replaces the same request instead of adding another.
    public let id: String
    public let kind: Kind
    public let fireDate: Date
    public let title: String
    public let body: String

    /// Delivered without sound or banner emphasis (the "quiet note", R3).
    public var isQuiet: Bool { kind == .workoutBehind }

    public var scheduled: ScheduledReminder { ScheduledReminder(id: id, kind: kind, fireDate: fireDate) }
}

/// Works out which reminders should be pending right now (DECISIONS R1, R1a, R2–R5b). Pure: it is
/// recomputed on every change (water logged anywhere, launch / foreground, settings, background
/// refresh) and the result replaces Fuely's pending notifications.
///
/// - Water: the moment the user would be `minimumShortfallML` behind pace if nothing more is
///   logged (expected − total ≥ 250 ml; merely behind is not enough, R5b), and a second one 2 h
///   later, both inside today's drinking window. With less than 250 ml left to drink, none. At most 2 per day counting the ones already sent, at least 2 h after the last
///   one sent. Nothing once the goal is met. Never sooner than `leadTime` from now: after the user
///   just did something in Fuely, a reminder seconds later would be noise.
/// - Workout: the note for the next reminder time (today's if still ahead, else tomorrow's), from
///   the slack rules of `WorkoutReminderPolicy`.
public enum ReminderPlanner {
    /// Every Fuely request id starts with this; requests without it are never touched.
    public static let idPrefix = "fuely."
    /// R1a.
    public static let waterSpacing: TimeInterval = 2 * 3600
    /// The lead after the user did something in Fuely (log, open, change settings).
    public static let leadAfterActivity: TimeInterval = 30 * 60
    /// The smallest lead (background refresh): a request can't fire in the past.
    public static let minimumLead: TimeInterval = 60
    /// How far behind pace (expected − total) the user must be before a water reminder (R5b).
    public static let minimumShortfallML = 250

    public static func isFuelyID(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    /// Everything that should be pending at `now`, sorted by fire date.
    /// - Parameters:
    ///   - todayTotalML: today's water from every source Fuely knows (log + snapshot).
    ///   - workouts: this week's workouts (the HealthKit snapshot).
    ///   - bookkeeping: what already went out; call `markDelivered(asOf:)` on it first.
    public static func plan(settings: FuelySettings, todayTotalML: Int, workouts: [WorkoutSample],
                            bookkeeping: ReminderBookkeeping, now: Date, leadTime: TimeInterval,
                            calendar: Calendar) -> [PlannedReminder] {
        var reminders = water(settings: settings, todayTotalML: todayTotalML, bookkeeping: bookkeeping,
                              now: now, leadTime: leadTime, calendar: calendar)
        if let note = workout(settings: settings, workouts: workouts, bookkeeping: bookkeeping,
                              now: now, calendar: calendar) {
            reminders.append(note)
        }
        return reminders.sorted { $0.fireDate < $1.fireDate }
    }

    /// Today's remaining water reminders (0–2).
    public static func water(settings: FuelySettings, todayTotalML: Int, bookkeeping: ReminderBookkeeping,
                             now: Date, leadTime: TimeInterval, calendar: Calendar) -> [PlannedReminder] {
        let goal = settings.waterGoalML
        let sent = bookkeeping.waterRemindersSent(onDayOf: now, calendar: calendar)
        guard settings.remindersEnabled, goal > 0, todayTotalML < goal, sent < WaterReminderPolicy.maxPerDay,
              let window = settings.drinkingWindow.interval(on: now, calendar: calendar), now < window.end
        else { return [] }

        // Far enough behind from the instant the pace reaches total + 250 ml. The pace ends at the
        // goal at the window end (exclusive), so with ≤ 250 ml left that instant never comes.
        let threshold = Double(max(todayTotalML, 0) + minimumShortfallML)
        guard threshold < Double(goal) else { return [] }
        let farEnoughBehindFrom = window.start.addingTimeInterval(threshold * window.duration / Double(goal))
        var earliest = max(farEnoughBehindFrom, now.addingTimeInterval(max(leadTime, minimumLead)))
        if let last = bookkeeping.lastWaterReminderAt {
            earliest = max(earliest, last.addingTimeInterval(waterSpacing))
        }
        earliest = wholeSecond(earliest)

        var reminders: [PlannedReminder] = []
        var fireDate = earliest
        for slot in (sent + 1)...WaterReminderPolicy.maxPerDay {
            guard fireDate < window.end else { break }
            let copy = ReminderCopy.water(slot: slot, totalML: todayTotalML, goalML: goal)
            reminders.append(PlannedReminder(id: "\(idPrefix)water.\(dayKey(now, calendar)).\(slot)",
                                             kind: .water, fireDate: fireDate, title: copy.title, body: copy.body))
            fireDate = fireDate.addingTimeInterval(waterSpacing)
        }
        return reminders
    }

    /// The workout note for the next reminder time, or nil.
    public static func workout(settings: FuelySettings, workouts: [WorkoutSample], bookkeeping: ReminderBookkeeping,
                               now: Date, calendar: Calendar) -> PlannedReminder? {
        guard settings.remindersEnabled else { return nil }
        let fireDate = WorkoutReminderPolicy.nextReminderDate(after: now, reminderTime: settings.workoutReminderTime,
                                                              calendar: calendar)
        guard let reminder = WorkoutReminderPolicy.reminder(
            now: fireDate, samples: workouts, goal: settings.workoutGoal, reminderTime: settings.workoutReminderTime,
            alreadyRemindedToday: bookkeeping.workoutRemindedToday(now: fireDate, calendar: calendar),
            behindNoteSentThisWeek: bookkeeping.behindNoteSentThisWeek(now: fireDate, calendar: calendar),
            calendar: calendar) else { return nil }
        let kind: PlannedReminder.Kind = if case .behind = reminder { .workoutBehind } else { .workout }
        let copy = ReminderCopy.workout(reminder, minMinutesPerDay: settings.workoutGoal.minMinutesPerDay)
        return PlannedReminder(id: "\(idPrefix)workout.\(dayKey(fireDate, calendar))", kind: kind,
                               fireDate: fireDate, title: copy.title, body: copy.body)
    }

    /// "2026-11-09" in `calendar`'s time zone (no formatter, no locale).
    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = c.year ?? 0, month = c.month ?? 0, day = c.day ?? 0
        return "\(year)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
    }

    /// Rounds up to a whole second so ids and stored dates stay tidy.
    private static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.up))
    }
}
