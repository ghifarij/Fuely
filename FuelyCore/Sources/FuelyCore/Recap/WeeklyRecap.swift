import Foundation

/// One saved weekly recap (DECISIONS WR1, WR8): everything the recap screen shows, frozen when it
/// was made. Later goal changes or late Health syncs never rewrite it, and it is never recomputed.
public struct WeeklyRecap: Codable, Sendable, Hashable, Identifiable {
    public static let currentSchemaVersion = 1

    /// One emoji for the whole week (WR6).
    public enum Mood: String, Codable, Sendable, Hashable, CaseIterable {
        /// Every judged ring strong.
        case allStrong
        /// Two of three judged rings strong.
        case twoStrong
        /// One ring strong, but not all judged ones.
        case oneStrong
        /// None strong, at least one close.
        case mixed
        /// None strong, none close.
        case low
        /// No water logged, no sleep tracked, no workouts (WR4a).
        case notEnoughData
    }

    public enum Ring: String, Codable, Sendable, Hashable, CaseIterable {
        case water, sleep, workouts

        public var title: String {
            switch self {
            case .water: "Water"
            case .sleep: "Sleep"
            case .workouts: "Workouts"
            }
        }
    }

    /// One ring of the card (WR3): ring fill, the stat in a long and a short form, one short line.
    /// All words are frozen here (WR8); the screen only lays them out.
    public struct Row: Codable, Sendable, Hashable, Identifiable {
        /// The short number when there is no verdict (WR4).
        public static let noVerdict = "—"

        public var ring: Ring
        /// Ring fill, 0…∞ (extra workout days go past 1). 0 when there is no verdict.
        public var fraction: Double
        /// The emphasized number of the stat: "6", "84". nil when there is no verdict.
        public var number: String?
        /// The words after the number: "of 7 days", "avg sleep score". Without a verdict the whole
        /// stat: "No sleep tracked", "2 nights tracked".
        public var unit: String
        /// The short form inside a ring: "6/7", "84", "—".
        public var shortNumber: String
        /// The words under a ring: "of 7 days", "avg sleep score", "not tracked", "2 nights tracked".
        public var caption: String
        /// One short detail line.
        public var line: String

        public var id: Ring { ring }

        public init(ring: Ring, fraction: Double, number: String?, unit: String, shortNumber: String,
                    caption: String, line: String) {
            self.ring = ring
            self.fraction = fraction
            self.number = number
            self.unit = unit
            self.shortNumber = shortNumber
            self.caption = caption
            self.line = line
        }

        /// False when there was too little to judge the ring (WR4): no number, an empty ring.
        public var hasVerdict: Bool { number != nil }

        /// The stat in words: "6 of 7 days", "84 avg sleep score", "No sleep tracked".
        public var stat: String {
            [number, unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }

        /// One VoiceOver element per ring: "Water, 6 of 7 days. Only Saturday slipped."
        public var spokenSummary: String {
            let lead = [ring.title, stat].filter { !$0.isEmpty }.joined(separator: ", ")
            return line.isEmpty ? "\(lead)." : "\(lead). \(line)"
        }

        private enum CodingKeys: String, CodingKey {
            case ring, fraction, number, unit, shortNumber, caption, line
        }

        /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let number = try c.decodeIfPresent(String.self, forKey: .number)
            let unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
            self.init(ring: try c.decode(Ring.self, forKey: .ring),
                      fraction: try c.decodeIfPresent(Double.self, forKey: .fraction) ?? 0,
                      number: number, unit: unit,
                      shortNumber: try c.decodeIfPresent(String.self, forKey: .shortNumber) ?? number ?? Self.noVerdict,
                      caption: try c.decodeIfPresent(String.self, forKey: .caption) ?? unit,
                      line: try c.decodeIfPresent(String.self, forKey: .line) ?? "")
        }
    }

    /// The numbers behind the rows, with the goals in force when the recap was made (WR8).
    public struct Numbers: Codable, Sendable, Hashable {
        public var waterDaysReached: Int
        public var waterGoalML: Int
        /// The best day's total; 0 when no water was logged.
        public var bestWaterDayML: Int
        public var sleepTrackedNights: Int
        /// nil without a tracked night.
        public var sleepAverage: Int?
        public var sleepNightsAtGoal: Int
        public var sleepGoal: Int
        public var workoutDays: Int
        public var workoutGoalDays: Int

        public init(waterDaysReached: Int = 0, waterGoalML: Int = 0, bestWaterDayML: Int = 0,
                    sleepTrackedNights: Int = 0, sleepAverage: Int? = nil, sleepNightsAtGoal: Int = 0,
                    sleepGoal: Int = 0, workoutDays: Int = 0, workoutGoalDays: Int = 0) {
            self.waterDaysReached = waterDaysReached
            self.waterGoalML = waterGoalML
            self.bestWaterDayML = bestWaterDayML
            self.sleepTrackedNights = sleepTrackedNights
            self.sleepAverage = sleepAverage
            self.sleepNightsAtGoal = sleepNightsAtGoal
            self.sleepGoal = sleepGoal
            self.workoutDays = workoutDays
            self.workoutGoalDays = workoutGoalDays
        }

        public init(_ judgement: WeekJudgement) {
            self.init(waterDaysReached: judgement.water.daysReached, waterGoalML: judgement.water.goalML,
                      bestWaterDayML: judgement.water.bestDayML,
                      sleepTrackedNights: judgement.sleep.trackedNights, sleepAverage: judgement.sleep.average,
                      sleepNightsAtGoal: judgement.sleep.nightsAtGoal, sleepGoal: judgement.sleep.goal,
                      workoutDays: judgement.workouts.workoutDays, workoutGoalDays: judgement.workouts.goalDays)
        }

        private enum CodingKeys: String, CodingKey {
            case waterDaysReached, waterGoalML, bestWaterDayML, sleepTrackedNights, sleepAverage,
                 sleepNightsAtGoal, sleepGoal, workoutDays, workoutGoalDays
        }

        /// Tolerant: missing fields take defaults, unknown ones are ignored (schema evolution).
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let int = { (key: CodingKeys) in try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
            self.init(waterDaysReached: try int(.waterDaysReached), waterGoalML: try int(.waterGoalML),
                      bestWaterDayML: try int(.bestWaterDayML), sleepTrackedNights: try int(.sleepTrackedNights),
                      sleepAverage: try c.decodeIfPresent(Int.self, forKey: .sleepAverage),
                      sleepNightsAtGoal: try int(.sleepNightsAtGoal), sleepGoal: try int(.sleepGoal),
                      workoutDays: try int(.workoutDays), workoutGoalDays: try int(.workoutGoalDays))
        }
    }

    /// The format version this recap was written with.
    public private(set) var schemaVersion = Self.currentSchemaVersion
    /// The Monday–Sunday week (K2) this recap is about.
    public var week: RecapWeek
    /// When it was made and frozen.
    public var createdAt: Date
    public var mood: Mood
    public var headline: String
    /// One short sentence under the headline, about the three rings together.
    public var supporting: String
    /// Water, sleep, workouts.
    public var rows: [Row]
    /// The last line (WR5). A suggestion has no prefix and starts lower-case: the screen puts its
    /// own lead-in before it. A congratulation is a full sentence shown as is.
    public var closing: String
    /// True: `closing` is a suggestion for the weakest ring. False: a congratulation.
    public var closingIsSuggestion: Bool
    public var numbers: Numbers

    public var id: RecapWeek { week }

    public init(week: RecapWeek, createdAt: Date, mood: Mood, headline: String, supporting: String,
                rows: [Row], closing: String, closingIsSuggestion: Bool, numbers: Numbers) {
        self.week = week
        self.createdAt = createdAt
        self.mood = mood
        self.headline = headline
        self.supporting = supporting
        self.rows = rows
        self.closing = closing
        self.closingIsSuggestion = closingIsSuggestion
        self.numbers = numbers
    }

    /// Judges and words a finished week (WR2, WR4). Call once per week, then save the result.
    public static func make(from history: WeekHistory, createdAt: Date, calendar: Calendar,
                            locale: Locale = .autoupdatingCurrent,
                            config: WeeklyRecapConfig = .default) -> WeeklyRecap {
        make(from: WeekJudgement(history, calendar: calendar, config: config), createdAt: createdAt,
             calendar: calendar, locale: locale)
    }

    public static func make(from judgement: WeekJudgement, createdAt: Date, calendar: Calendar,
                            locale: Locale = .autoupdatingCurrent) -> WeeklyRecap {
        let text = WeeklyRecapCopy.text(for: judgement, calendar: calendar, locale: locale)
        return WeeklyRecap(week: judgement.week, createdAt: createdAt, mood: judgement.mood,
                           headline: text.headline, supporting: text.supporting,
                           rows: WeeklyRecapCopy.rows(for: judgement, text: text),
                           closing: text.closing, closingIsSuggestion: text.closingIsSuggestion,
                           numbers: Numbers(judgement))
    }

    public func row(_ ring: Ring) -> Row? {
        rows.first { $0.ring == ring }
    }

    /// Monday 00:00 and Sunday 00:00 of the week in `calendar`.
    public func weekStart(calendar: Calendar) -> Date { week.start(calendar: calendar) }
    public func weekEnd(calendar: Calendar) -> Date { week.lastDay(calendar: calendar) }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, week, createdAt, mood, headline, supporting, rows, closing,
             closingIsSuggestion, numbers
    }

    /// Tolerant: only the week is required; missing fields take defaults, unknown ones are ignored.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(week: try c.decode(RecapWeek.self, forKey: .week),
                  createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast,
                  mood: (try? c.decodeIfPresent(Mood.self, forKey: .mood)) ?? .notEnoughData,
                  headline: try c.decodeIfPresent(String.self, forKey: .headline) ?? "",
                  supporting: try c.decodeIfPresent(String.self, forKey: .supporting) ?? "",
                  rows: (try c.decodeIfPresent([LossyRecapElement<Row>].self, forKey: .rows) ?? []).compactMap(\.value),
                  closing: try c.decodeIfPresent(String.self, forKey: .closing) ?? "",
                  closingIsSuggestion: try c.decodeIfPresent(Bool.self, forKey: .closingIsSuggestion) ?? true,
                  numbers: try c.decodeIfPresent(Numbers.self, forKey: .numbers) ?? Numbers())
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    }
}

/// Decodes to nil instead of failing, so one unreadable element doesn't lose the whole list.
struct LossyRecapElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// The saved recaps plus which week was last shown (DECISIONS WR7, WR8), in `weekly-recaps.json`.
public struct WeeklyRecapArchive: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    /// The format version this archive was written with.
    public private(set) var schemaVersion: Int
    /// One per week, oldest week first.
    public private(set) var recaps: [WeeklyRecap]
    /// The newest week whose recap popped up; that week and every earlier one never pops up again.
    public private(set) var lastShownWeek: RecapWeek?

    public init(recaps: [WeeklyRecap] = [], lastShownWeek: RecapWeek? = nil) {
        schemaVersion = Self.currentSchemaVersion
        self.recaps = []
        self.lastShownWeek = lastShownWeek
        for recap in recaps.sorted(by: { $0.week < $1.week }) where recap.week != self.recaps.last?.week {
            self.recaps.append(recap)
        }
    }

    public var weeks: Set<RecapWeek> { Set(recaps.map(\.week)) }

    public func recap(for week: RecapWeek) -> WeeklyRecap? {
        recaps.first { $0.week == week }
    }

    public func hasBeenShown(_ week: RecapWeek) -> Bool {
        lastShownWeek.map { week <= $0 } ?? false
    }

    /// Adds a recap and keeps the newest `limit` weeks (WR8). A week that already has a recap keeps
    /// it (frozen); returns false then, and when the recap is older than the kept ones.
    @discardableResult
    public mutating func save(_ recap: WeeklyRecap, keeping limit: Int = WeeklyRecapConfig.default.keptRecaps) -> Bool {
        guard self.recap(for: recap.week) == nil else { return false }
        recaps.append(recap)
        recaps.sort { $0.week < $1.week }
        if recaps.count > max(limit, 0) { recaps.removeFirst(recaps.count - max(limit, 0)) }
        return self.recap(for: recap.week) != nil
    }

    /// Records that the recap of `week` popped up. Never moves backwards.
    public mutating func markShown(_ week: RecapWeek) {
        lastShownWeek = max(lastShownWeek ?? week, week)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, recaps, lastShownWeek
    }

    /// Tolerant: missing fields take defaults, unknown ones and unreadable recaps are ignored.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(recaps: (try c.decodeIfPresent([LossyRecapElement<WeeklyRecap>].self, forKey: .recaps) ?? [])
                    .compactMap(\.value),
                  lastShownWeek: try? c.decodeIfPresent(RecapWeek.self, forKey: .lastShownWeek))
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    }
}
