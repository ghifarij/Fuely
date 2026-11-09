import Foundation

public enum WaterGoal {
    /// Suggested daily goal: weight × 35 ml, rounded to the nearest 100 ml (DECISIONS W2).
    /// Height is not used (W2 calls it only a minor adjustment and gives no formula).
    public static func suggestedML(weightKG: Double) -> Int {
        guard weightKG > 0 else { return 0 }
        return Int((weightKG * 35 / 100).rounded(.toNearestOrAwayFromZero)) * 100
    }
}
