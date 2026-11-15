import FuelyCore
import SwiftUI

// How the app draws a saved `WeeklyRecap` (DECISIONS §11). The words are frozen in FuelyCore
// (WR8); the emoji, glyphs and colours live here.

extension WeeklyRecap.Mood {
    /// One emoji for the whole week (WR6).
    var emoji: String {
        switch self {
        case .allStrong: "🤩"
        case .twoStrong: "😄"
        case .oneStrong: "🙂"
        case .mixed: "😅"
        case .low: "😴"
        case .notEnoughData: "👀"
        }
    }
}

extension WeeklyRecap.Ring {
    var systemImage: String {
        switch self {
        case .water: "drop.fill"
        case .sleep: "moon.zzz.fill"
        case .workouts: "figure.run"
        }
    }

    var color: Color {
        switch self {
        case .water: FuelyColor.water
        case .sleep: FuelyColor.sleep
        case .workouts: FuelyColor.workout
        }
    }
}
