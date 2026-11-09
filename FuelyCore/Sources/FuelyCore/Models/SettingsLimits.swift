import Foundation

/// Accepted ranges for everything editable in onboarding and Settings, so the UI controls and the
/// stored values agree. Values outside a range are clamped by `FuelySettings.sanitized()`.
public enum SettingsLimits {
    public static let weightKG: ClosedRange<Double> = 30...250
    public static let waterGoalML: ClosedRange<Int> = 500...6000
    public static let waterGoalStepML = 100
    public static let widgetAmountML: ClosedRange<Int> = 50...1000
    public static let widgetAmountStepML = 50
    /// The in-widget amount picker (DECISIONS W6b): 50 ml steps from 50 ml to 2 L.
    public static let widgetDraftML: ClosedRange<Int> = 50...2000
    public static let widgetDraftStepML = 50
    public static let workoutMinutes: ClosedRange<Int> = 5...240
    public static let workoutMinutesStep = 5
    public static let workoutDaysPerWeek: ClosedRange<Int> = 1...7
    public static let sleepGoal: ClosedRange<Int> = 50...100
    public static let sleepGoalStep = 5
    /// The drinking window is at least this long (same day, start before end; DECISIONS W8a).
    public static let minimumDrinkingWindowMinutes = 60
    /// The latest a window can end: 23:59 (it can't cross midnight, W8a).
    public static let latestWindowEnd = TimeOfDay(hour: 23, minute: 59)

    /// A weight the user can save, or nil when it is outside `weightKG` (or not a number).
    /// Rounded to 0.1 kg.
    public static func validWeight(_ kg: Double?) -> Double? {
        guard let kg, kg.isFinite, weightKG.contains(kg) else { return nil }
        return (kg * 10).rounded() / 10
    }

    /// Parses the weight field ("70", "70.5", "70,5", "70 kg"); nil when empty, not a number or
    /// outside `weightKG`.
    public static func parseWeight(_ text: String) -> Double? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix("kg") { text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        text = text.replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, text.count <= 6, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let value = Double(text) else { return nil }
        return validWeight(value)
    }

    /// The weight as the field shows it: "70", "70.5".
    public static func weightText(_ kg: Double?) -> String {
        guard let kg else { return "" }
        let tenths = Int((kg * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    /// Whether `window` is a usable drinking window: same day, at least `minimumDrinkingWindowMinutes`.
    public static func isValid(_ window: DrinkingWindow) -> Bool {
        window.end.minutesSinceMidnight - window.start.minutesSinceMidnight >= minimumDrinkingWindowMinutes
    }

    /// The latest start allowed for a window ending at `end`.
    public static func latestStart(forEnd end: TimeOfDay) -> TimeOfDay {
        TimeOfDay(minutesSinceMidnight: max(end.minutesSinceMidnight - minimumDrinkingWindowMinutes, 0))
    }

    /// The earliest end allowed for a window starting at `start`.
    public static func earliestEnd(forStart start: TimeOfDay) -> TimeOfDay {
        TimeOfDay(minutesSinceMidnight: min(start.minutesSinceMidnight + minimumDrinkingWindowMinutes,
                                            latestWindowEnd.minutesSinceMidnight))
    }

    static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension TimeOfDay {
    /// A time from minutes since midnight, clamped to 00:00–23:59.
    public init(minutesSinceMidnight minutes: Int) {
        let minutes = min(max(minutes, 0), 23 * 60 + 59)
        self.init(hour: minutes / 60, minute: minutes % 60)
    }
}

extension FuelySettings {
    /// The settings with every value inside `SettingsLimits` (an out-of-range weight is dropped,
    /// an invalid drinking window falls back to the default 05:00–22:00).
    public func sanitized() -> FuelySettings {
        var copy = self
        copy.weightKG = SettingsLimits.validWeight(weightKG)
        copy.waterGoalML = SettingsLimits.clamp(waterGoalML, SettingsLimits.waterGoalML)
        copy.widgetAmountML = SettingsLimits.clamp(widgetAmountML, SettingsLimits.widgetAmountML)
        copy.workoutGoal = WorkoutGoal(
            minMinutesPerDay: SettingsLimits.clamp(workoutGoal.minMinutesPerDay, SettingsLimits.workoutMinutes),
            daysPerWeek: SettingsLimits.clamp(workoutGoal.daysPerWeek, SettingsLimits.workoutDaysPerWeek))
        copy.sleepGoalScore = SettingsLimits.clamp(sleepGoalScore, SettingsLimits.sleepGoal)
        if !SettingsLimits.isValid(drinkingWindow) { copy.drinkingWindow = .default }
        return copy
    }

    /// The suggested water goal for the stored weight (DECISIONS W2), clamped to the goal range;
    /// nil without a weight.
    public var suggestedWaterGoalML: Int? {
        guard let weight = SettingsLimits.validWeight(weightKG) else { return nil }
        return SettingsLimits.clamp(WaterGoal.suggestedML(weightKG: weight), SettingsLimits.waterGoalML)
    }
}
