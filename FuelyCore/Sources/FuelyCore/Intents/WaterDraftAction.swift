import Foundation
import WidgetKit

/// The work behind the widget amount picker's App Intents (DECISIONS W6b). Each button writes the
/// tiny draft file in the App Group store and reloads the widgets; ✓ then logs through
/// `LogWaterAction` (store first, HealthKit later).
///
/// The `AppIntent` types live in the app and widget targets (`FuelyWidgets/Shared`), not here,
/// for the same reason as `LogWaterIntent` (iOS 26's linkd rejects package-defined intents).
public enum WaterDraftAction {
    /// Applies a picker change and returns the new draft (nil = Idle).
    @discardableResult
    public static func apply(_ change: WaterDraft.Change, store: FuelyStore, now: Date = Date(),
                             reload: Bool = true) throws -> WaterDraft? {
        // Settings are read only to start a draft: keep the common taps to one small file.
        let settings = change == .start ? try store.settings() : .default
        let draft = try store.updateWaterDraft { draft -> WaterDraft? in
            draft = WaterDraft.apply(change, to: draft, settings: settings, now: now)
            return draft
        }
        if reload { WidgetCenter.shared.reloadAllTimelines() }
        return draft
    }

    /// Applies a picker change to the App Group store.
    @discardableResult
    public static func apply(_ change: WaterDraft.Change, now: Date = Date()) throws -> WaterDraft? {
        try apply(change, store: try FuelyStore.appGroup(), now: now)
    }

    /// ✓: clears the draft and returns the amount to log, or nil when it was stale or missing
    /// (a double tap or a late tap logs nothing).
    public static func takeCommit(store: FuelyStore, now: Date) throws -> Int? {
        try store.updateWaterDraft { draft -> Int? in
            let amount = WaterDraft.amountToCommit(draft, now: now)
            draft = nil
            return amount
        }
    }

    /// ✓ on the App Group store: logs the draft amount via `LogWaterAction` and returns to Idle.
    /// Returns the amount logged, or nil when nothing was logged.
    @discardableResult
    public static func commit(now: Date = Date()) async throws -> Int? {
        let store = try FuelyStore.appGroup()
        guard let amount = try takeCommit(store: store, now: now) else {
            WidgetCenter.shared.reloadAllTimelines()
            return nil
        }
        // Reloads the widgets itself.
        try await LogWaterAction.perform(amountML: amount, now: now)
        return amount
    }
}
