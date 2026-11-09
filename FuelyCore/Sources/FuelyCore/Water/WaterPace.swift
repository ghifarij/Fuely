import Foundation

public enum WaterPaceStatus: String, Codable, Sendable, Hashable {
    case goalMet, onTrack, behind
}

/// Today's water progress against the goal and the drinking-window pace.
public struct WaterProgress: Sendable, Hashable {
    public let totalML: Int
    public let goalML: Int
    /// What the pace expects by now: goal × elapsed fraction of the window.
    public let expectedML: Double
    /// total / goal; can exceed 1 (DECISIONS W3). 0 when the goal is 0.
    public let fraction: Double
    public let status: WaterPaceStatus
}

/// Water pace over the drinking window (DECISIONS W8).
public enum WaterPace {
    /// 0 before the window, 1 after it, linear in real elapsed time in between.
    /// An invalid window yields 0, so nobody is ever marked behind by a bad setting.
    public static func elapsedFraction(of window: DrinkingWindow, at now: Date, calendar: Calendar) -> Double {
        guard let interval = window.interval(on: now, calendar: calendar) else { return 0 }
        let elapsed = now.timeIntervalSince(interval.start)
        return min(max(elapsed / interval.duration, 0), 1)
    }

    public static func expectedIntakeML(goalML: Int, window: DrinkingWindow, at now: Date, calendar: Calendar) -> Double {
        Double(max(goalML, 0)) * elapsedFraction(of: window, at: now, calendar: calendar)
    }

    public static func progress(totalML: Int, goalML: Int, window: DrinkingWindow, at now: Date, calendar: Calendar) -> WaterProgress {
        let expected = expectedIntakeML(goalML: goalML, window: window, at: now, calendar: calendar)
        let status: WaterPaceStatus =
            totalML >= goalML ? .goalMet
            : Double(totalML) >= expected ? .onTrack
            : .behind
        return WaterProgress(
            totalML: totalML,
            goalML: goalML,
            expectedML: expected,
            fraction: goalML > 0 ? Double(totalML) / Double(goalML) : 0,
            status: status
        )
    }

    /// Sum of all entries (any source) on the calendar day containing `now`.
    public static func totalML(of entries: [WaterEntry], onDayOf now: Date, calendar: Calendar) -> Int {
        entries.lazy
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .reduce(0) { $0 + $1.amountML }
    }
}
