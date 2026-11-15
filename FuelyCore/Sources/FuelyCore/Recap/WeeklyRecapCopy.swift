import Foundation

/// The final words of one recap (DECISIONS WR2, WR5).
public struct WeeklyRecapText: Sendable, Hashable {
    public var headline: String
    /// One short sentence about the three rings together.
    public var supporting: String
    public var waterLine: String
    public var sleepLine: String
    public var workoutLine: String
    /// The suggestion without any lead-in (starts lower-case), or a congratulation sentence.
    public var closing: String
    public var closingIsSuggestion: Bool

    public func line(_ ring: WeeklyRecap.Ring) -> String {
        switch ring {
        case .water: waterLine
        case .sleep: sleepLine
        case .workouts: workoutLine
        }
    }
}

/// The words of the weekly recap (DECISIONS WR2): layered templates, no model. A tier per ring
/// picks the case, pattern facts fill it in, and each case has several phrasings chosen by the
/// week's number, so a given week always reads the same. English only; weekday names come from the
/// calendar in the phone's region format (D3). Tone as R4: encouraging, never nagging.
///
/// Every string keeps to `Limit`, so the screen fits a 4.7" iPhone without scrolling (WR3).
public enum WeeklyRecapCopy {
    /// The most characters each text may have.
    public enum Limit {
        public static let headline = 22
        public static let supporting = 45
        public static let ringLine = 34
        public static let closing = 60
    }

    /// Seeds from 0 up to this cover every phrasing of every case (cases have 1–4 phrasings).
    public static let variantCycle = 12

    public static let noSleepLine = "No sleep tracked."
    public static let noWaterLine = "No water logged."

    /// The phrasing seed of a week: its ISO week number plus the year, so week 1 of two years differs.
    public static func variant(for week: RecapWeek) -> Int {
        week.isoWeekNumber + week.year
    }

    public static func text(for judgement: WeekJudgement, calendar: Calendar,
                            locale: Locale = .autoupdatingCurrent) -> WeeklyRecapText {
        text(for: judgement, variant: variant(for: judgement.week), calendar: calendar, locale: locale)
    }

    /// The same with an explicit phrasing seed (tests enumerate them).
    public static func text(for judgement: WeekJudgement, variant: Int, calendar: Calendar,
                            locale: Locale = .autoupdatingCurrent) -> WeeklyRecapText {
        let names = (0..<7).map { weekdayName($0, of: judgement.week, calendar: calendar, locale: locale) }
        return text(for: judgement, variant: variant, weekdayNames: names)
    }

    /// - `weekdayNames`: Monday first, 7 names.
    static func text(for judgement: WeekJudgement, variant: Int, weekdayNames names: [String]) -> WeeklyRecapText {
        let closing = closing(judgement, variant)
        return WeeklyRecapText(headline: headline(judgement.mood, variant),
                               supporting: supporting(judgement, variant),
                               waterLine: waterLine(judgement.water, names, variant),
                               sleepLine: sleepLine(judgement.sleep, variant),
                               workoutLine: workoutLine(judgement.workouts, variant),
                               closing: closing.text, closingIsSuggestion: closing.isSuggestion)
    }

    /// The three card rows (WR3): ring fill, the stat ("6 of 7 days", short "6/7") and the line.
    public static func rows(for judgement: WeekJudgement, text: WeeklyRecapText) -> [WeeklyRecap.Row] {
        let water = judgement.water, workouts = judgement.workouts
        let waterUnit = "of 7 days"
        let workoutUnit = "of \(FuelyFormat.count(workouts.goalDays, "day"))"
        return [
            WeeklyRecap.Row(ring: .water, fraction: water.fraction, number: "\(water.daysReached)", unit: waterUnit,
                            shortNumber: "\(water.daysReached)/7", caption: waterUnit, line: text.waterLine),
            sleepRow(judgement.sleep, line: text.sleepLine),
            WeeklyRecap.Row(ring: .workouts, fraction: workouts.fraction, number: "\(workouts.workoutDays)",
                            unit: workoutUnit, shortNumber: "\(workouts.workoutDays)/\(workouts.goalDays)",
                            caption: workoutUnit, line: text.workoutLine),
        ]
    }

    /// The average when the week is judged; otherwise why there is none (WR4).
    private static func sleepRow(_ sleep: SleepWeekJudgement, line: String) -> WeeklyRecap.Row {
        if sleep.isJudged, let average = sleep.average {
            let unit = "avg sleep score"
            return WeeklyRecap.Row(ring: .sleep, fraction: sleep.fraction, number: "\(average)", unit: unit,
                                   shortNumber: "\(average)", caption: unit, line: line)
        }
        let tracked = "\(FuelyFormat.count(sleep.trackedNights, "night")) tracked"
        let none = sleep.trackedNights == 0
        return WeeklyRecap.Row(ring: .sleep, fraction: 0, number: nil, unit: none ? "No sleep tracked" : tracked,
                               shortNumber: WeeklyRecap.Row.noVerdict, caption: none ? "not tracked" : tracked,
                               line: line)
    }

    /// Monday to Sunday in the region's format: "Nov 2 – 8" (US), "2 – 8 Nov" (UK).
    public static func dateRange(_ week: RecapWeek, calendar: Calendar,
                                 locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.IntervalFormatStyle(date: .omitted, time: .omitted,
                                             locale: DisplayLocale.english(keepingRegionOf: locale),
                                             calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day()
        return (week.start(calendar: calendar)..<week.lastDay(calendar: calendar)).formatted(style)
    }

    /// "Monday" … "Sunday" for day 0…6 of the week.
    static func weekdayName(_ index: Int, of week: RecapWeek, calendar: Calendar, locale: Locale) -> String {
        let noon = week.date(ofDay: index, calendar: calendar).addingTimeInterval(12 * 3600)
        return noon.formatted(Date.FormatStyle(locale: DisplayLocale.english(keepingRegionOf: locale),
                                               calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
    }

    // MARK: - Headline

    static func headline(_ mood: WeeklyRecap.Mood, _ variant: Int) -> String {
        let options = switch mood {
        case .allStrong: ["A strong week.", "What a week.", "Everything landed.", "A week to be proud of."]
        case .twoStrong: ["A good week.", "A solid week.", "Nicely done.", "Two out of three."]
        case .oneStrong: ["A steady week.", "A fair week.", "Something to build on.", "One ring led the way."]
        case .mixed: ["A mixed week.", "A bit of everything.", "An in-between week.", "Close in places."]
        case .low: ["A quiet week.", "A slow week.", "An off week.", "A week to reset."]
        case .notEnoughData: ["Not much to go on.", "A blank week.", "Nothing to show yet.", "Not enough to tell."]
        }
        return pick(options, variant, salt: 0)
    }

    // MARK: - Supporting line

    static func supporting(_ judgement: WeekJudgement, _ variant: Int) -> String {
        let strong = list(judgement.strongRings), weak = list(judgement.weakRings)
        let all = list(judgement.judgedRings)
        let three = judgement.judgedRings.count == 3
        let options: [String]
        switch judgement.mood {
        case .allStrong:
            options = three
                ? ["\(cap(all)) all landed.", "All three rings came through.",
                   "Hydrated, rested and active all week.", "\(cap(all)): all strong."]
                : ["\(cap(all)) both landed.", "\(cap(all)) both came through.",
                   "Hydrated and active all week.", "\(cap(all)): both strong."]
        case .twoStrong:
            options = ["\(cap(strong)) held up, \(weak) lagged.", "Strong \(strong), \(weak) fell behind.",
                       "\(cap(strong)) on track, \(weak) less so.", "\(cap(strong)) carried the week."]
        case .oneStrong:
            options = judgement.weakRings.count > 1
                ? ["\(cap(strong)) held up, \(weak) slipped.", "\(cap(strong)) led the way, the rest fell behind.",
                   "\(cap(strong)) stood out, \(weak) less so.", "\(cap(strong)) came through, the others lagged."]
                : ["\(cap(strong)) held up, \(weak) came up short.", "\(cap(strong)) led the way, \(weak) fell behind.",
                   "\(cap(strong)) stood out, \(weak) less so.", "\(cap(strong)) came through, \(weak) lagged."]
        case .mixed:
            let close = judgement.judgedRings.filter(judgement.isMidTier)
            options = ["A bit of everything, nothing quite there yet.",
                       close.count == 3 ? "All three rings got close." : "\(cap(list(close))) got close to the goal.",
                       "Close in places, not quite there yet.", "Some good days, no ring quite made it."]
        case .low:
            options = ["Some weeks are like that. A fresh start now.", "\(cap(all)) \(three ? "all" : "both") ran low.",
                       "Every ring had a slow week. It happens.", "Not the week you planned. On to the next."]
        case .notEnoughData:
            options = ["Fuely saw very little of this week.", "No water, sleep or workouts recorded.",
                       "Nothing was logged this week.", "Too little logged to sum the week up."]
        }
        return pick(options, variant, salt: 1)
    }

    // MARK: - Ring lines

    static func waterLine(_ water: WaterWeekJudgement, _ names: [String], _ variant: Int) -> String {
        guard water.hasData, let best = water.bestDay else { return noWaterLine }
        let weekend = [5, 6]
        let bestName = names[best], amount = FuelyFormat.water(water.bestDayML)
        let bestDay = ["Best day: \(bestName), \(amount).", "\(bestName) led with \(amount).",
                       "Top day: \(bestName), \(amount).", "\(bestName) was highest, \(amount)."]
        let options: [String]
        switch (water.reachedDays.count, water.slippedDays.count) {
        case (7, _):
            options = ["Every day reached the goal.", "A full week at the goal.", "Seven for seven.",
                       "Not a single day missed."]
        case (_, 1):
            let day = names[water.slippedDays[0]]
            options = ["Only \(day) slipped.", "All but \(day) on goal.", "Just \(day) fell short.",
                       "\(day) was the only miss."]
        case (_, 2):
            let days = water.slippedDays.map { names[$0] }.joined(separator: " and ")
            options = water.slippedDays == weekend
                ? ["Only the weekend slipped.", "Every weekday reached the goal.", "Weekdays all on goal.",
                   "Just the weekend fell short."]
                : ["\(days) slipped.", "Missed \(days).", "All but \(days)."]
        case (1, _):
            let day = names[water.reachedDays[0]]
            options = ["\(day) reached the goal.", "Goal met on \(day).", "\(day) was the best day."]
        case (2, _):
            let days = water.reachedDays.map { names[$0] }.joined(separator: " and ")
            options = water.reachedDays == weekend
                ? ["The weekend reached the goal.", "Goal met on both weekend days.", "Best at the weekend."]
                : ["\(days) got there.", "Goal met \(days).", "\(days) made it."]
        default:
            // 3–4 days, or none at the goal: the best day says the most.
            options = bestDay
        }
        return pick(options, variant, salt: 2)
    }

    static func sleepLine(_ sleep: SleepWeekJudgement, _ variant: Int) -> String {
        let nights = FuelyFormat.count(sleep.trackedNights, "night")
        let options: [String]
        switch sleep.state {
        case .noneTracked:
            return noSleepLine
        case .tooFewNights:
            options = ["\(nights) tracked. Wear your Watch.", "Only \(nights). Wear your Watch.",
                       "Wear your Watch: only \(nights)."]
        case .judged:
            let total = sleep.trackedNights, atGoal = sleep.nightsAtGoal, goal = sleep.goal
            if atGoal == total {
                options = ["All \(total) tracked nights at \(goal)+.", "\(nights) tracked, all at \(goal)+.",
                           "Every tracked night reached \(goal)."]
            } else if atGoal == 0 {
                options = ["\(nights) tracked, none at \(goal)+.", "No tracked night reached \(goal).",
                           "None of \(total) tracked nights hit \(goal)."]
            } else {
                options = ["\(nights) tracked, \(atGoal) at \(goal)+.", "\(atGoal) of \(total) tracked nights at \(goal)+.",
                           "\(nights) tracked, \(atGoal) reached \(goal)."]
            }
        }
        return pick(options, variant, salt: 3)
    }

    static func workoutLine(_ workouts: WorkoutWeekJudgement, _ variant: Int) -> String {
        let options: [String]
        switch workouts.tier {
        case .beyond:
            let extra = workouts.extraDays
            options = extra == 1
                ? ["One more than planned.", "One extra day on top.", "Goal reached, plus one."]
                : ["\(extra) more than planned.", "\(extra) extra days on top.", "Goal reached, plus \(extra)."]
        case .met:
            options = ["Goal reached.", "Right on the goal.", "Every planned day done.", "Just as planned."]
        case .oneShort:
            options = ["One day short of the goal.", "Just one day short.", "One more day would do it.",
                       "So close, one day short."]
        case .missed:
            if workouts.workoutDays > 0 {
                let short = workouts.daysShort
                options = ["\(short) days short of the goal.",
                           "\(workouts.workoutDays) of \(workouts.goalDays) planned days done.",
                           "\(short) more days were planned."]
            } else if workouts.hasData {
                options = ["No day reached \(workouts.minMinutesPerDay) min.",
                           "Workouts stayed under \(workouts.minMinutesPerDay) min."]
            } else {
                options = ["No workouts logged.", "No workouts this week.", "No workouts found."]
            }
        }
        return pick(options, variant, salt: 4)
    }

    // MARK: - Closing line

    static func closing(_ judgement: WeekJudgement, _ variant: Int) -> (text: String, isSuggestion: Bool) {
        guard judgement.hasEnoughData else {
            return (pick(["log your first glass and the rest follows.", "log a glass of water today to get going.",
                          "start with water, one glass at a time.", "open Fuely once a day and log what you drink."],
                         variant, salt: 5), true)
        }
        guard let ring = judgement.weakestRing else {
            return (pick(["Nothing to fix. Enjoy it, and keep the rhythm.", "Keep doing what you're doing.",
                          "Whatever you did, it worked. Same again.", "A week to repeat. Enjoy it."],
                         variant, salt: 5), false)
        }
        let close = judgement.isMidTier(ring)
        let options: [String]
        switch ring {
        case .water:
            let weekendSlipped = judgement.water.slippedDays.contains(5) && judgement.water.slippedDays.contains(6)
            if close, weekendSlipped {
                options = ["keep a bottle in sight at the weekend too.", "plan your weekend water like a weekday.",
                           "take a bottle along on Saturday and Sunday."]
            } else if close {
                options = ["keep a filled bottle where you can see it.", "a glass with every meal adds up quickly.",
                           "start each morning with a full glass.", "top up at lunch, afternoons are easy to miss."]
            } else {
                options = ["start small, a glass of water each morning.", "one glass after waking up is a good first step.",
                           "log each glass, seeing the total helps it grow.", "try a glass with breakfast, lunch and dinner."]
            }
        case .sleep:
            options = close
                ? ["start winding down 20 minutes earlier.", "a steadier bedtime could lift the average.",
                   "put the phone down a little sooner at night.", "aim for the same bedtime most nights."]
                : ["pick a bedtime and protect it for a few nights.", "an earlier night or two would help the average.",
                   "try a calmer last half hour before bed.", "go to bed a little earlier, one night at a time."]
        case .workouts:
            options = close
                ? ["one more workout day gets you there.", "pick the extra day now and keep it free.",
                   "add one session early in the week.", "plan the last workout before the weekend."]
                : ["pick your workout days now and keep them free.", "start with one session early in the week.",
                   "plan the first workout for Monday or Tuesday.", "put the first workout in your calendar today."]
        }
        return (pick(options, variant, salt: 5), true)
    }

    // MARK: - Helpers

    private static func pick(_ options: [String], _ variant: Int, salt: Int) -> String {
        guard !options.isEmpty else { return "" }
        let index = (variant + salt) % options.count
        return options[index < 0 ? index + options.count : index]
    }

    /// "water", "water and workouts", "water, sleep and workouts".
    private static func list(_ rings: [WeeklyRecap.Ring]) -> String {
        let words = rings.map(\.rawValue)
        guard let last = words.last, words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func cap(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
