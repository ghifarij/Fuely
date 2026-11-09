import Foundation

/// The amount being picked in a widget before it is logged (DECISIONS W6b).
///
/// Idle = no draft (or a stale one). Tapping (+) starts a draft at the Settings widget amount;
/// −/+ step it by 50 ml, presets set it, ✓ logs it and ✕ drops it. Nothing is logged before ✓.
/// A draft lasts `lifetime` after the last tap, then every widget reads it as Idle again.
///
/// One draft is shared by all widgets: they all show the picker while it is active. That is the
/// simplest model (one tiny App Group file, no per-widget ids, which a Button intent can't learn
/// anyway) and matches how one person uses one phone.
public struct WaterDraft: Codable, Sendable, Hashable {
    /// The amount to log, inside `SettingsLimits.widgetDraftML`.
    public var amountML: Int
    /// When editing started, or the last tap that changed it; the draft expires `lifetime` later.
    public var startedAt: Date

    /// How long the picker stays open without a tap: about 2 minutes.
    public static let lifetime: TimeInterval = 120
    /// The preset chips on the medium Home Screen widget.
    public static let presetsML = [150, 250, 500]
    /// What tapping the amount on Fuely Circle cycles through.
    public static let circlePresetsML = [150, 250, 400, 500]

    public init(amountML: Int, startedAt: Date) {
        self.amountML = amountML
        self.startedAt = startedAt
    }

    /// A new draft at the Settings widget amount (W6, W6a), clamped to the picker range.
    public static func start(settings: FuelySettings, now: Date) -> WaterDraft {
        WaterDraft(amountML: clamp(LogWaterAction.widgetAmountML(settings: settings)), startedAt: now)
    }

    public var expiresAt: Date { startedAt.addingTimeInterval(Self.lifetime) }

    /// Still editing at `date`. A draft dated in the future (clock moved back) counts as stale, so
    /// a widget can never get stuck in the picker.
    public func isActive(at date: Date) -> Bool {
        startedAt <= date && date < expiresAt
    }

    /// `draft` if it is still active at `date`, else nil (Idle).
    public static func active(_ draft: WaterDraft?, at date: Date) -> WaterDraft? {
        guard let draft, draft.isActive(at: date) else { return nil }
        return draft
    }

    public static func clamp(_ amountML: Int) -> Int {
        SettingsLimits.clamp(amountML, SettingsLimits.widgetDraftML)
    }

    /// −/+ by `delta`, landing on the 50 ml grid and inside the range.
    public func adjusted(by delta: Int) -> WaterDraft {
        let step = SettingsLimits.widgetDraftStepML
        var amount = amountML
        if amount % step != 0 {
            // Off the grid: the first step goes to the neighbouring grid value in that direction.
            let below = (amount / step) * step
            amount = delta > 0 ? below + step : (delta < 0 ? below : amount)
        } else {
            amount += delta
        }
        var copy = self
        copy.amountML = Self.clamp(amount)
        return copy
    }

    public var canDecrease: Bool { amountML > SettingsLimits.widgetDraftML.lowerBound }
    public var canIncrease: Bool { amountML < SettingsLimits.widgetDraftML.upperBound }

    /// Fuely Circle's preset after `amountML`: 150 → 250 → 400 → 500 → 150. An amount between
    /// presets goes to the next larger one.
    public static func nextCirclePreset(after amountML: Int) -> Int {
        circlePresetsML.first { $0 > amountML } ?? circlePresetsML[0]
    }

    /// What a picker button does.
    public enum Change: Sendable, Hashable {
        /// (+) on an Idle widget: open the picker at the Settings amount.
        case start
        /// − / +.
        case adjust(Int)
        /// A preset chip.
        case set(Int)
        /// Tapping the amount on Fuely Circle.
        case cyclePreset
        /// ✕.
        case cancel
    }

    /// The draft after `change` at `now`; nil = Idle. Edits on a stale or missing draft do nothing
    /// (the widget simply redraws Idle). Every edit restarts the 2 minutes.
    public static func apply(_ change: Change, to draft: WaterDraft?, settings: FuelySettings, now: Date) -> WaterDraft? {
        if change == .start { return start(settings: settings, now: now) }
        guard var current = active(draft, at: now) else { return nil }
        switch change {
        case .start, .cancel:
            return nil
        case .adjust(let delta):
            current = current.adjusted(by: delta)
        case .set(let amount):
            current.amountML = clamp(amount)
        case .cyclePreset:
            current.amountML = nextCirclePreset(after: current.amountML)
        }
        current.startedAt = now
        return current
    }

    /// The amount ✓ should log: the active draft's, or nil (stale / no draft: log nothing).
    public static func amountToCommit(_ draft: WaterDraft?, now: Date) -> Int? {
        active(draft, at: now)?.amountML
    }
}
