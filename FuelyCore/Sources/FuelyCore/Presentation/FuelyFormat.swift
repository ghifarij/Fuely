import Foundation

/// Text formatting shared by the app and the widgets. English only, ml / L (DECISIONS P6).
/// Formatting is fixed (not locale-dependent) so the app and the widgets always agree.
public enum FuelyFormat {
    /// "850 ml" below one litre, otherwise litres rounded to 10 ml with trailing zeros trimmed:
    /// "1.25 L", "1.2 L", "2 L". Negative amounts read as 0.
    public static func water(_ ml: Int) -> String {
        let ml = max(ml, 0)
        if ml < 1000 { return "\(ml) ml" }
        return "\(litres(ml)) L"
    }

    /// Litres with one decimal, rounded **down** so a total never reads as the goal before it is
    /// reached (2390 ml → "2.3"). For tight spaces such as the widgets (G1: "1.2L").
    public static func compactLitres(_ ml: Int) -> String {
        let decilitres = max(ml, 0) / 100
        return "\(decilitres / 10).\(decilitres % 10)"
    }

    /// For VoiceOver: "850 milliliters", "1 liter", "1.25 liters".
    public static func waterSpoken(_ ml: Int) -> String {
        let ml = max(ml, 0)
        if ml < 1000 { return ml == 1 ? "1 milliliter" : "\(ml) milliliters" }
        let text = litres(ml)
        return text == "1" ? "1 liter" : "\(text) liters"
    }

    /// Whole percent, may exceed 100 (DECISIONS W3): 0.524 → "52%".
    public static func percent(_ fraction: Double) -> String {
        "\(percentValue(fraction))%"
    }

    public static func percentValue(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((max(fraction, 0) * 100).rounded())
    }

    /// The score, or "—" when there is no data (DECISIONS S7). Never "0" for a missing night.
    public static func sleepScore(_ score: Int?) -> String {
        score.map(String.init) ?? "—"
    }

    /// "2/3" (DECISIONS T1, G1).
    public static func workoutDays(_ week: WorkoutWeek) -> String {
        "\(week.workoutDays)/\(week.goal.daysPerWeek)"
    }

    /// "1 day" / "3 days".
    public static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Litres rounded to 10 ml, trailing zeros trimmed: 1250 → "1.25", 1200 → "1.2", 2000 → "2".
    private static func litres(_ ml: Int) -> String {
        let centilitres = Int((Double(ml) / 10).rounded())
        let whole = centilitres / 100
        let fraction = centilitres % 100
        if fraction == 0 { return "\(whole)" }
        if fraction % 10 == 0 { return "\(whole).\(fraction / 10)" }
        return "\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}
