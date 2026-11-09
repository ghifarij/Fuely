import Foundation

/// Weekly workout goal (DECISIONS K2).
public struct WorkoutGoal: Codable, Sendable, Hashable {
    /// Minutes that make a day count as a workout day.
    public var minMinutesPerDay: Int
    /// Workout days wanted per Monday–Sunday week, 1–7.
    public var daysPerWeek: Int

    public init(minMinutesPerDay: Int, daysPerWeek: Int) {
        self.minMinutesPerDay = max(minMinutesPerDay, 0)
        self.daysPerWeek = min(max(daysPerWeek, 1), 7)
    }

    /// Default goal: 50 min a day, 3 days a week.
    public static let `default` = WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: 3)

    private enum CodingKeys: String, CodingKey {
        case minMinutesPerDay, daysPerWeek
    }

    /// Tolerant: missing fields take the defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(minMinutesPerDay: try c.decodeIfPresent(Int.self, forKey: .minMinutesPerDay) ?? Self.default.minMinutesPerDay,
                  daysPerWeek: try c.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? Self.default.daysPerWeek)
    }
}

/// Everything the user configures in onboarding and Settings (DECISIONS O1).
public struct FuelySettings: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    /// The format version these settings were written with.
    public private(set) var schemaVersion = Self.currentSchemaVersion
    public var heightCM: Double?
    public var weightKG: Double?
    public var waterGoalML: Int
    public var drinkingWindow: DrinkingWindow
    public var widgetAmountML: Int
    /// The one "Reminders" switch for water and workout notes (DECISIONS R1b). Older files stored
    /// it as `waterRemindersEnabled`; that value is read once and written back under this key.
    public var remindersEnabled: Bool
    public var workoutGoal: WorkoutGoal
    public var workoutReminderTime: TimeOfDay
    public var sleepGoalScore: Int
    /// The first-launch onboarding (DECISIONS O1) was finished. Kept here, in the App Group, so
    /// there is one source of truth for every setting.
    public var hasCompletedOnboarding: Bool

    public init(
        heightCM: Double? = nil,
        weightKG: Double? = nil,
        waterGoalML: Int = 2400,
        drinkingWindow: DrinkingWindow = .default,
        widgetAmountML: Int = WaterLogging.defaultWidgetAmountML,
        remindersEnabled: Bool = true,
        workoutGoal: WorkoutGoal = .default,
        workoutReminderTime: TimeOfDay = TimeOfDay(hour: 8),
        sleepGoalScore: Int = 80,
        hasCompletedOnboarding: Bool = false
    ) {
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.waterGoalML = waterGoalML
        self.drinkingWindow = drinkingWindow
        self.widgetAmountML = widgetAmountML
        self.remindersEnabled = remindersEnabled
        self.workoutGoal = workoutGoal
        self.workoutReminderTime = workoutReminderTime
        self.sleepGoalScore = sleepGoalScore
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let `default` = FuelySettings()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, heightCM, weightKG, waterGoalML, drinkingWindow, widgetAmountML,
             remindersEnabled, workoutGoal, workoutReminderTime, sleepGoalScore, hasCompletedOnboarding
    }

    /// Keys read only to migrate older files.
    private enum LegacyCodingKeys: String, CodingKey {
        /// Phase 1–5 water-only toggle, now `remindersEnabled` (R1b).
        case waterRemindersEnabled
    }

    /// Tolerant: missing fields take the defaults, unknown ones are ignored (schema evolution).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let d = Self.default
        self.init(
            heightCM: try c.decodeIfPresent(Double.self, forKey: .heightCM),
            weightKG: try c.decodeIfPresent(Double.self, forKey: .weightKG),
            waterGoalML: try c.decodeIfPresent(Int.self, forKey: .waterGoalML) ?? d.waterGoalML,
            drinkingWindow: try c.decodeIfPresent(DrinkingWindow.self, forKey: .drinkingWindow) ?? d.drinkingWindow,
            widgetAmountML: try c.decodeIfPresent(Int.self, forKey: .widgetAmountML) ?? d.widgetAmountML,
            remindersEnabled: try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled)
                ?? legacy.decodeIfPresent(Bool.self, forKey: .waterRemindersEnabled)
                ?? d.remindersEnabled,
            workoutGoal: try c.decodeIfPresent(WorkoutGoal.self, forKey: .workoutGoal) ?? d.workoutGoal,
            workoutReminderTime: try c.decodeIfPresent(TimeOfDay.self, forKey: .workoutReminderTime) ?? d.workoutReminderTime,
            sleepGoalScore: try c.decodeIfPresent(Int.self, forKey: .sleepGoalScore) ?? d.sleepGoalScore,
            hasCompletedOnboarding: try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
                ?? d.hasCompletedOnboarding
        )
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    }
}
