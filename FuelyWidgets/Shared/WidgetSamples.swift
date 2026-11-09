import FuelyCore
import Foundation

/// Sample entries for placeholders, the widget gallery and #Previews. Built through a throwaway
/// store in a temporary directory (never the App Group). "Now" is today at 14:00.
enum WidgetSamples {
    enum Scenario {
        /// 1.65 L of 2.4 L incl. 300 ml from other apps, on track, sleep 84, 2/3 workouts.
        case onTrack
        /// 600 ml, behind pace, no sleep data ("—"), 0/3 workouts.
        case behindNoSleep
        /// 3.1 L (past 100%), sleep 72, 3/3 workouts.
        case overGoal
    }

    static let calendar = Calendar.current

    static var now: Date {
        calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// `draftML`: show the amount picker (W6b) at that amount.
    static func entry(_ scenario: Scenario, metric: WidgetMetric = .water, draftML: Int? = nil) -> FuelyEntry {
        let store = FuelyStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "FuelyWidgetSample-\(UUID().uuidString)", directoryHint: .isDirectory))
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let (drinks, external, sleep, workoutDays): ([Int], Int, Int?, Int) = switch scenario {
        case .onTrack: ([250, 500, 150, 450], 300, 84, 2)
        case .behindNoSleep: ([250, 350], 0, nil, 0)
        case .overGoal: ([500, 500, 250, 500, 600, 750], 0, 72, 3)
        }
        let first = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: now) ?? now
        for (index, amount) in drinks.enumerated() {
            _ = try? store.logWater(amountML: amount, at: min(first.addingTimeInterval(Double(index) * 80 * 60), now))
        }
        let monday = WorkoutAggregation.weekStart(containing: now, calendar: calendar)
        let workouts = (0..<workoutDays).map { day in
            let start = (calendar.date(byAdding: .day, value: day, to: monday) ?? monday).addingTimeInterval(7 * 3600)
            return WorkoutSample(start: start, end: start.addingTimeInterval(3600), duration: 3600)
        }
        try? store.saveHealthSnapshot(HealthSnapshot(refreshedAt: now, externalWaterML: external,
                                                     sleepScore: sleep, workouts: workouts))
        let settings = FuelySettings(weightKG: 70, hasCompletedOnboarding: true)
        try? store.saveSettings(settings)
        let summary = (try? store.todaySummary(now: now, calendar: calendar))
            ?? TodaySummary.make(settings: settings, waterLog: WaterLog(), snapshot: nil, now: now, calendar: calendar)
        return FuelyEntry(date: now, summary: summary, settings: settings, metric: metric,
                          draft: draftML.map { WaterDraft(amountML: $0, startedAt: now) })
    }
}
