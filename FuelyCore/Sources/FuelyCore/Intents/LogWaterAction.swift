import Foundation
import WidgetKit

/// The work behind the "Log Water (amount)" App Intent (DECISIONS W5c) and the widget (+) button.
/// Writes to the App Group store first, syncs to HealthKit when this process may use it (the app,
/// not the widget extension), reschedules the reminders (R5; also from the widget extension, from
/// the stored state), then reloads the widgets.
///
/// The `AppIntent` type itself (`LogWaterIntent`) is declared in the app and widget targets, not
/// here: iOS 26's App Intents indexer (`linkd`) rejects a bundle whose metadata includes an
/// `AppIntentsPackage` from a statically linked Swift package ("did not match any imported
/// symbol"), which left the widget (+) dead on device.
public enum LogWaterAction {
    /// The widget (+) amount: the default widget amount from Settings (DECISIONS W5a, W6).
    public static func widgetAmountML(settings: FuelySettings) -> Int {
        settings.widgetAmountML
    }

    /// Logs `amountML` and returns today's water total in ml.
    @discardableResult
    public static func perform(amountML: Int, now: Date = Date()) async throws -> Int {
        let store = try FuelyStore.appGroup()
        try await WaterLogService.current(store: store).log(amountML: amountML, at: now)
        WidgetCenter.shared.reloadAllTimelines()
        await ReminderScheduler(store: store).rescheduleQuietly(now: now)
        let summary = try store.todaySummary(now: now, calendar: .current)
        return summary.water.totalML
    }
}
