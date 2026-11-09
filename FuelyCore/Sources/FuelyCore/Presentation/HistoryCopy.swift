import Foundation

/// The words on the week view and day detail (DECISIONS T3, W7, S7). English words; dates in the
/// phone's region format (D3). Pass a fixed `locale` for deterministic output (tests).
public enum HistoryCopy {
    /// "This week", "Last week", or the week's range ("Oct 19 – 25" / "19 – 25 Oct").
    public static func weekTitle(_ week: WeekHistory, now: Date, calendar: Calendar,
                                 locale: Locale = .autoupdatingCurrent) -> String {
        let thisMonday = WorkoutAggregation.weekStart(containing: now, calendar: calendar)
        if week.start == thisMonday { return "This week" }
        if let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday), week.start == lastMonday {
            return "Last week"
        }
        return weekRange(week, calendar: calendar, locale: locale)
    }

    /// Monday to Sunday in the region's format: "Nov 2 – 8" (US), "2 – 8 Nov" (UK), across months
    /// "Oct 26 – Nov 1" / "26 Oct – 1 Nov".
    public static func weekRange(_ week: WeekHistory, calendar: Calendar,
                                 locale: Locale = .autoupdatingCurrent) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: week.start) ?? week.start
        let style = Date.IntervalFormatStyle(date: .omitted, time: .omitted, locale: displayLocale(locale),
                                             calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day()
        return (week.start..<end).formatted(style)
    }

    /// "Nov 3" / "3 Nov".
    public static func shortDate(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(style(calendar, locale).month(.abbreviated).day())
    }

    /// "Today", "Yesterday" or the weekday name ("Monday").
    public static func dayTitle(_ day: HistoryDay, now: Date, calendar: Calendar,
                                locale: Locale = .autoupdatingCurrent) -> String {
        if calendar.isDate(day.date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day.date, inSameDayAs: yesterday) { return "Yesterday" }
        return day.date.formatted(style(calendar, locale).weekday(.wide))
    }

    /// "Monday, November 3" (US), "Monday 3 November" (UK).
    public static func longDate(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(style(calendar, locale).weekday(.wide).day().month(.wide))
    }

    /// Single-letter weekday for the chart axis: "M", "T", … "S".
    public static func weekdayInitial(_ date: Date, calendar: Calendar,
                                      locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(style(calendar, locale).weekday(.narrow))
    }

    private static func style(_ calendar: Calendar, _ locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: displayLocale(locale), calendar: calendar, timeZone: calendar.timeZone)
    }

    private static func displayLocale(_ locale: Locale) -> Locale {
        DisplayLocale.english(keepingRegionOf: locale)
    }

    /// "Goal met 3 of 5 days" (days so far this week).
    public static func waterSummary(_ week: WeekHistory) -> String {
        let elapsed = week.elapsedDays.count
        return "Goal met \(week.waterGoalDays) of \(FuelyFormat.count(elapsed, "day"))"
    }

    /// "Average of 4 nights", or the no-data hint (S7). The average itself is shown big.
    public static func sleepSummary(_ week: WeekHistory) -> String {
        guard week.averageSleepScore != nil else { return "No scores yet. " + TodayCopy.noSleepHint }
        return "Average of \(FuelyFormat.count(week.scoredNights.count, "night"))"
    }

    /// "2/3 days" or "3/3 days · Goal reached".
    public static func workoutSummary(_ week: WeekHistory) -> String {
        let text = "\(FuelyFormat.workoutDays(week.workoutWeek)) days"
        return week.workoutWeek.isGoalReached ? text + " · Goal reached" : text
    }

    /// "55 min" (rounded down, like Today), or "—" when there were none.
    public static func workoutMinutes(_ day: HistoryDay) -> String {
        let minutes = Int(day.workoutMinutes.rounded(.down))
        return minutes > 0 ? "\(minutes) min" : "—"
    }

    /// "Health app · read-only".
    public static func externalSubtitle(_ entry: WaterEntry) -> String {
        if case .external(let name) = entry.source, !name.isEmpty { return "\(name) · read-only" }
        return "Other app · read-only"
    }

    /// VoiceOver for a day row.
    public static func dayAccessibility(_ day: HistoryDay, now: Date, calendar: Calendar,
                                        locale: Locale = .autoupdatingCurrent) -> String {
        let title = "\(dayTitle(day, now: now, calendar: calendar, locale: locale)), "
            + longDate(day.date, calendar: calendar, locale: locale)
        guard !day.isFuture else { return "\(title). No data yet." }
        let water = "Water \(FuelyFormat.waterSpoken(day.waterTotalML)), "
            + "\(FuelyFormat.percentValue(day.waterFraction)) percent of goal"
        let sleep = day.sleepScore.map { "sleep score \($0)" } ?? "no sleep score"
        let minutes = Int(day.workoutMinutes.rounded(.down))
        let workout = minutes > 0
            ? "\(FuelyFormat.count(minutes, "minute")) of workouts" + (day.isWorkoutDay ? ", workout day" : "")
            : "no workouts"
        return "\(title). \(water), \(sleep), \(workout)."
    }
}

/// The words in Settings.
public enum SettingsCopy {
    /// "17 h" or "16 h 30 min" for a drinking window.
    public static func windowLength(_ window: DrinkingWindow) -> String {
        let minutes = max(window.end.minutesSinceMidnight - window.start.minutesSinceMidnight, 0)
        let hours = minutes / 60, rest = minutes % 60
        if rest == 0 { return "\(hours) h" }
        return hours == 0 ? "\(rest) min" : "\(hours) h \(rest) min"
    }

    /// "70 kg", "70.5 kg".
    public static func weight(_ kg: Double) -> String {
        let tenths = Int((kg * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10) kg" : "\(tenths / 10).\(tenths % 10) kg"
    }

    /// The Apple Health row in Settings.
    public static func healthAccess(_ status: HealthAccessStatus) -> (title: String, detail: String) {
        switch status {
        case .allowed:
            ("Connected", "Fuely saves your water to Apple Health and reads sleep and workouts.")
        case .denied:
            ("Water sync off", "Allow Fuely to write water in Settings → Privacy & Security → Health → Fuely. Your drinks stay saved in Fuely meanwhile.")
        case .notDetermined:
            ("Not connected", "Connect Apple Health to sync water and read sleep and workouts.")
        case .unavailable:
            ("Unavailable", "Apple Health isn't available on this device. Your water is saved in Fuely only.")
        }
    }
}
