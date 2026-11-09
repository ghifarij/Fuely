import AppIntents
import FuelyCore

// The widget amount picker's buttons (DECISIONS W6b): (+) opens it, − / + / presets change the
// amount, ✓ logs, ✕ cancels. Each intent writes the small draft file in the App Group store and
// reloads the widgets (logic in FuelyCore `WaterDraftAction`); they run in the widget process and
// never open the app. Like `LogWaterIntent`, these are compiled into both the app and the widget
// extension, because iOS 26's linkd rejects intents declared in the FuelyCore package.
// Hidden from Shortcuts: they only make sense as widget buttons.

/// (+) on an Idle widget: show the picker at the Settings widget amount.
struct StartWaterDraftIntent: AppIntent {
    static var title: LocalizedStringResource { "Choose Water Amount" }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        try WaterDraftAction.apply(.start)
        return .result()
    }
}

/// − / + in the picker.
struct AdjustWaterDraftIntent: AppIntent {
    static var title: LocalizedStringResource { "Change Water Amount" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Change (ml)")
    var deltaML: Int

    init() {}

    init(deltaML: Int) {
        self.deltaML = deltaML
    }

    func perform() async throws -> some IntentResult {
        try WaterDraftAction.apply(.adjust(deltaML))
        return .result()
    }
}

/// A preset chip in the picker (medium Home Screen widget).
struct SetWaterDraftIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Water Amount" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Amount (ml)")
    var amountML: Int

    init() {}

    init(amountML: Int) {
        self.amountML = amountML
    }

    func perform() async throws -> some IntentResult {
        try WaterDraftAction.apply(.set(amountML))
        return .result()
    }
}

/// Tapping the amount on Fuely Circle: 150 → 250 → 400 → 500 → 150.
struct CycleWaterDraftIntent: AppIntent {
    static var title: LocalizedStringResource { "Next Water Amount" }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        try WaterDraftAction.apply(.cyclePreset)
        return .result()
    }
}

/// ✓: log the picked amount (App Group store first, HealthKit later) and close the picker.
/// A stale picker (older than ~2 min) logs nothing.
struct CommitWaterDraftIntent: AppIntent {
    static var title: LocalizedStringResource { "Log Chosen Water Amount" }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        try await WaterDraftAction.commit()
        return .result()
    }
}

/// ✕: close the picker without logging.
struct CancelWaterDraftIntent: AppIntent {
    static var title: LocalizedStringResource { "Cancel Water Amount" }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        try WaterDraftAction.apply(.cancel)
        return .result()
    }
}
