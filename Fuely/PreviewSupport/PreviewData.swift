import FuelyCore
import Foundation

/// Sample data for SwiftUI previews: a throwaway store in a temporary directory, no HealthKit,
/// no widget reloads. "Now" is today at 14:00 so pace states are predictable.
@MainActor
enum PreviewData {
    enum Scenario {
        /// 1.65 L incl. 300 ml from other apps, sleep 84, 2/3 workouts.
        case onTrack
        /// 600 ml, no sleep data ("—"), 0/3 workouts, "Health access off".
        case behindNoSleep
        /// 3.1 L (over 100%), sleep 72, 3/3 workouts.
        case overGoal
        /// Fresh install: nothing logged, no snapshot.
        case empty
    }

    static let calendar = Calendar.current

    static var now: Date {
        calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// `onboarded: false` shows the onboarding flow (fresh settings). `history: true` adds a fake
    /// HealthKit with past weeks of data (week view, day detail).
    static func model(_ scenario: Scenario, onboarded: Bool = true, history: Bool = false) -> AppModel {
        let store = store(scenario)
        try? store.updateSettings {
            $0.hasCompletedOnboarding = onboarded
            if onboarded { $0.weightKG = 70 }
        }
        return AppModel(store: store, healthKit: history ? PreviewHealthKit() : nil, calendar: calendar, now: { now }, reloadsWidgets: false,
                        asksSystemPermissions: false)
    }

    static func summary(_ scenario: Scenario) -> TodaySummary {
        model(scenario).summary
    }

    static func store(_ scenario: Scenario) -> FuelyStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FuelyPreview-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FuelyStore(directory: directory)
        let (drinks, external, sleep, workoutDays, issue): ([Int], Int, Int?, Int, HealthSyncIssue?) = switch scenario {
        case .onTrack: ([250, 500, 150, 450], 300, 84, 2, nil)
        case .behindNoSleep: ([250, 350], 0, nil, 0, .notAuthorized)
        case .overGoal: ([500, 500, 250, 500, 600, 750], 0, 72, 3, nil)
        case .empty: ([], 0, nil, 0, nil)
        }
        let start = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: now) ?? now
        for (index, amount) in drinks.enumerated() {
            let date = start.addingTimeInterval(Double(index) * 80 * 60)
            _ = try? store.logWater(amountML: amount, at: min(date, now))
        }
        if let issue {
            try? store.updateWaterLog { log in
                if let job = log.nextPending() { log.recordFailure(job.id, issue: issue) }
            }
        }
        guard scenario != .empty else { return store }
        let weekStart = WorkoutAggregation.weekStart(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let workouts = (0..<workoutDays).map { offset in
            let day = min(calendar.date(byAdding: .day, value: offset * 2, to: weekStart) ?? today, today)
            let begin = calendar.date(byAdding: .hour, value: 6 + offset, to: day) ?? day
            return WorkoutSample(start: begin, end: begin.addingTimeInterval(55 * 60), duration: 55 * 60)
        }
        try? store.saveHealthSnapshot(HealthSnapshot(refreshedAt: now, externalWaterML: external,
                                                     sleepScore: sleep, workouts: workouts))
        return store
    }
}
