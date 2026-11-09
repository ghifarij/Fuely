import AppIntents
import FuelyCore

/// "Log Water (amount)" (DECISIONS W5c): for the user's own Shortcuts and the widget (+) button.
/// Compiled into both the app and the widget extension (target membership), so each bundle's own
/// App Intents metadata declares it; the logic lives in `LogWaterAction` (FuelyCore).
/// No App Shortcuts / Siri phrases (P5).
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource { "Log Water" }
    static var description: IntentDescription {
        IntentDescription("Adds water to today's total in Fuely and saves it to Apple Health.")
    }

    @Parameter(title: "Amount (ml)", default: 250)
    var amountML: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amountML) ml of water")
    }

    init() {}

    init(amountML: Int) {
        self.amountML = amountML
    }

    /// The widget (+) intent, using the default widget amount from Settings (DECISIONS W5a, W6).
    static func widgetButton(settings: FuelySettings) -> LogWaterIntent {
        LogWaterIntent(amountML: LogWaterAction.widgetAmountML(settings: settings))
    }

    /// Returns today's water total in ml.
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: try await LogWaterAction.perform(amountML: amountML))
    }
}
