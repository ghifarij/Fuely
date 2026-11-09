import Foundation

/// When the widgets need a fresh entry (DECISIONS W8 pace, S7a midnight rollover). The widget
/// can't read HealthKit, so each entry is recomputed from the App Group store for its own date:
/// pace moves through the drinking window, and at midnight other apps' water, the sleep score
/// ("—") and, on Mondays, the workout week roll over.
public enum WidgetTimelinePlan {
    /// 15 minutes: pace text stays current without wasting entries.
    public static let defaultStep: TimeInterval = 15 * 60

    /// `now`, then every `step` inside today's drinking window (aligned to the window start, e.g.
    /// 05:00, 05:15, …), the window's end, and the next midnight. Strictly increasing. The
    /// timeline should reload after the last date (`.atEnd`), i.e. just after midnight.
    /// Outside the window pace doesn't change, so no entries are spent there.
    ///
    /// `draftExpiry` (DECISIONS W6b): when an amount picker is open, an extra entry at its expiry
    /// turns the widget back to Idle without a reload.
    public static func entryDates(from now: Date, window: DrinkingWindow, calendar: Calendar,
                                  step: TimeInterval = defaultStep, draftExpiry: Date?) -> [Date] {
        var dates = entryDates(from: now, window: window, calendar: calendar, step: step)
        if let draftExpiry, draftExpiry > now, !dates.contains(draftExpiry) {
            dates.append(draftExpiry)
            dates.sort()
        }
        return dates
    }

    public static func entryDates(from now: Date, window: DrinkingWindow, calendar: Calendar,
                                  step: TimeInterval = defaultStep) -> [Date] {
        var dates = [now]
        if step > 0, let interval = window.interval(on: now, calendar: calendar) {
            var next = interval.start
            if now >= interval.start {
                let stepsDone = ((now.timeIntervalSince(interval.start)) / step).rounded(.down) + 1
                next = interval.start.addingTimeInterval(stepsDone * step)
            }
            while next < interval.end {
                dates.append(next)
                next = next.addingTimeInterval(step)
            }
            if interval.end > now { dates.append(interval.end) }
        }
        let midnight = nextMidnight(after: now, calendar: calendar)
        if midnight > dates[dates.count - 1] { dates.append(midnight) }
        return dates
    }

    /// The start of the day after the one containing `date`.
    public static func nextMidnight(after date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
}

/// What a single-metric widget shows (Fuely Circle, DECISIONS G4).
public enum WidgetMetric: String, CaseIterable, Sendable, Hashable {
    case water, sleep, workouts
}

/// Ring progress for the widgets. Water may pass 100% (laps, DECISIONS W3); sleep and workouts
/// close their ring at the goal and stop there.
public enum WidgetRings {
    public static func fraction(_ metric: WidgetMetric, in summary: TodaySummary) -> Double {
        switch metric {
        case .water:
            return summary.water.fraction.isFinite ? max(summary.water.fraction, 0) : 0
        case .sleep:
            guard let score = summary.sleepScore else { return 0 }
            guard summary.sleepGoal > 0 else { return 1 }
            return min(max(Double(score) / Double(summary.sleepGoal), 0), 1)
        case .workouts:
            let week = summary.workoutWeek
            return min(Double(week.workoutDays) / Double(max(week.goal.daysPerWeek, 1)), 1)
        }
    }

    /// Whether the metric's goal is met (used for a checkmark / emphasis).
    public static func isGoalMet(_ metric: WidgetMetric, in summary: TodaySummary) -> Bool {
        switch metric {
        case .water: summary.water.status == .goalMet
        case .sleep: summary.sleepGoalMet == true
        case .workouts: summary.workoutWeek.isGoalReached
        }
    }
}

/// The words on the widgets (DECISIONS G1–G5, S7, P6). Kept here so they are tested.
public enum WidgetCopy {
    /// Fuely Text, `accessoryInline` (G1): "💧1.2L · 😴82 · 🏃2/3".
    public static func inline(_ summary: TodaySummary) -> String {
        "💧\(FuelyFormat.compactLitres(summary.water.totalML))L · 😴\(FuelyFormat.sleepScore(summary.sleepScore))"
            + " · 🏃\(FuelyFormat.workoutDays(summary.workoutWeek))"
    }

    /// Shorter inline fallback when the slot is too narrow: "💧1.2L 😴82 🏃2/3".
    public static func inlineCompact(_ summary: TodaySummary) -> String {
        "💧\(FuelyFormat.compactLitres(summary.water.totalML))L 😴\(FuelyFormat.sleepScore(summary.sleepScore))"
            + " 🏃\(FuelyFormat.workoutDays(summary.workoutWeek))"
    }

    /// Fuely Line, `accessoryRectangular` (G2): three rows, "💧 1.2/2.4L" / "😴 82" / "🏃 2/3".
    /// The widget draws the emoji smaller than the value so it matches the text size.
    public static func lineEmoji(_ metric: WidgetMetric) -> String {
        switch metric {
        case .water: "💧"
        case .sleep: "😴"
        case .workouts: "🏃"
        }
    }

    /// A Fuely Line row's value: water "1.2/2.4L", sleep "82" / "—", workouts "2/3".
    public static func lineValue(_ metric: WidgetMetric, in summary: TodaySummary) -> String {
        switch metric {
        case .water: waterFraction(summary)
        case .sleep, .workouts: value(metric, in: summary)
        }
    }

    /// A whole Fuely Line row as text: "💧 1.2/2.4L".
    public static func lineRow(_ metric: WidgetMetric, in summary: TodaySummary) -> String {
        "\(lineEmoji(metric)) \(lineValue(metric, in: summary))"
    }

    /// "1.2/2.4L" (G2).
    public static func waterFraction(_ summary: TodaySummary) -> String {
        "\(FuelyFormat.compactLitres(summary.water.totalML))/\(FuelyFormat.compactLitres(summary.water.goalML))L"
    }

    /// The short value inside a ring: water "1.2" (litres), sleep "82" / "—", workouts "2/3".
    public static func value(_ metric: WidgetMetric, in summary: TodaySummary) -> String {
        switch metric {
        case .water: FuelyFormat.compactLitres(summary.water.totalML)
        case .sleep: FuelyFormat.sleepScore(summary.sleepScore)
        case .workouts: FuelyFormat.workoutDays(summary.workoutWeek)
        }
    }

    /// The label under a ring on the Home Screen: "Water", "Sleep", "Workouts".
    public static func title(_ metric: WidgetMetric) -> String {
        switch metric {
        case .water: "Water"
        case .sleep: "Sleep"
        case .workouts: "Workouts"
        }
    }

    /// A short detail under a value: water "On track" / "350 ml behind pace" / "Goal reached",
    /// sleep "Goal 80" / "No data", workouts "this week".
    public static func detail(_ metric: WidgetMetric, in summary: TodaySummary) -> String {
        switch metric {
        case .water: TodayCopy.paceText(summary.water)
        case .sleep: summary.sleepScore == nil ? "No data" : "Goal \(summary.sleepGoal)"
        case .workouts: "This week"
        }
    }

    /// Pace for tight spaces (small widget): "On track", "Goal reached" or "350 ml behind".
    public static func shortPace(_ water: WaterProgress) -> String {
        water.status == .behind ? "\(FuelyFormat.water(TodayCopy.catchUpML(water))) behind" : TodayCopy.paceText(water)
    }

    /// VoiceOver for one metric.
    public static func accessibility(_ metric: WidgetMetric, in summary: TodaySummary) -> String {
        switch metric {
        case .water:
            "Water, \(FuelyFormat.waterSpoken(summary.water.totalML)) of "
                + "\(FuelyFormat.waterSpoken(summary.water.goalML)), \(TodayCopy.paceText(summary.water).lowercased())"
        case .sleep:
            summary.sleepScore.map { "Sleep score \($0), goal \(summary.sleepGoal)" } ?? "Sleep score, no data"
        case .workouts:
            "Workouts, \(summary.workoutWeek.workoutDays) of "
                + "\(FuelyFormat.count(summary.workoutWeek.goal.daysPerWeek, "day")) this week"
        }
    }

    /// VoiceOver for a whole widget: the three metrics in order.
    public static func accessibility(_ summary: TodaySummary) -> String {
        WidgetMetric.allCases.map { accessibility($0, in: summary) }.joined(separator: ". ")
    }

    // MARK: Amount picker (DECISIONS W6b)

    /// The Idle (+) for VoiceOver: it opens the picker, it doesn't log yet.
    public static let startAccessibility = "Log water, choose an amount"
    /// The picker's heading on the Home Screen.
    public static let draftTitle = "Log water"
    public static let draftUnit = "ml"

    /// The picked amount without the unit: "250".
    public static func draftAmount(_ ml: Int) -> String { "\(ml)" }

    /// "250 ml".
    public static func draftAmountWithUnit(_ ml: Int) -> String { "\(ml) \(draftUnit)" }

    public static let cancelAccessibility = "Cancel"
    public static var decreaseAccessibility: String {
        "Decrease by \(FuelyFormat.waterSpoken(SettingsLimits.widgetDraftStepML))"
    }
    public static var increaseAccessibility: String {
        "Increase by \(FuelyFormat.waterSpoken(SettingsLimits.widgetDraftStepML))"
    }

    /// The amount for VoiceOver: "250 milliliters".
    public static func draftAmountAccessibility(_ ml: Int) -> String { FuelyFormat.waterSpoken(ml) }

    /// A preset chip: "Set 500 milliliters".
    public static func presetAccessibility(_ ml: Int) -> String { "Set \(FuelyFormat.waterSpoken(ml))" }

    /// Fuely Circle's amount, which cycles the presets.
    public static func cycleAccessibility(_ ml: Int) -> String {
        "\(FuelyFormat.waterSpoken(ml)). Tap for another amount"
    }

    /// ✓ (and the Shortcuts-style log) for VoiceOver: "Log 250 milliliters of water".
    public static func addAccessibility(amountML: Int) -> String {
        "Log \(FuelyFormat.waterSpoken(amountML)) of water"
    }
}
