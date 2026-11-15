#if DEBUG && targetEnvironment(simulator)
import FuelyCore
import Foundation

/// DEBUG, SIMULATOR ONLY: runs the real weekly recap path (trigger, saving, Week button) on
/// invented data, to check it by hand. Never compiled into a device or release build.
///
///     -recapDemo YES      (a launch argument, or the `recapDemo` user default)
///
/// The app then uses a throwaway store in its own Application Support folder (not the App Group,
/// so the widgets are untouched), onboarded 24 days ago, with `PreviewHealthKit`'s invented water,
/// sleep and workouts instead of HealthKit. Delete the app to start over.
@MainActor
enum RecapDemo {
    static let key = "recapDemo"

    static func modelIfRequested() -> AppModel? {
        guard UserDefaults.standard.bool(forKey: key) else { return nil }
        let directory = URL.applicationSupportDirectory.appending(path: "RecapDemo", directoryHint: .isDirectory)
        let store = FuelyStore(directory: directory)
        let started = Calendar.current.date(byAdding: .day, value: -24, to: Date()) ?? Date()
        try? store.updateSettings { settings in
            guard !settings.hasCompletedOnboarding else { return }
            settings.weightKG = 70
            settings.completeOnboarding(at: started)
        }
        return AppModel(store: store, healthKit: PreviewHealthKit(), reloadsWidgets: false,
                        asksSystemPermissions: false)
    }
}
#endif
