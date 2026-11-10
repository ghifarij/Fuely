import AppIntents
import FuelyCore
import SwiftUI
import WidgetKit

// The in-widget amount picker (DECISIONS W6b): `✕  −  250 ml  +  ✓`. Each control is a
// `Button(intent:)` (WaterDraftIntents.swift). Full color uses the brand aqua on the ocean
// gradient; the tinted / clear Home Screen and the lock screen draw in primary with the main
// action in the accent group (G7).

/// What one picker control does, with its glyph and VoiceOver label.
enum DraftControl {
    case cancel, decrease, increase, commit

    var systemImage: String {
        switch self {
        case .cancel: "xmark"
        case .decrease: "minus"
        case .increase: "plus"
        case .commit: "checkmark"
        }
    }

    func accessibility(_ draft: WaterDraft) -> String {
        switch self {
        case .cancel: WidgetCopy.cancelAccessibility
        case .decrease: WidgetCopy.decreaseAccessibility
        case .increase: WidgetCopy.increaseAccessibility
        case .commit: WidgetCopy.addAccessibility(amountML: draft.amountML)
        }
    }

    func isEnabled(_ draft: WaterDraft) -> Bool {
        switch self {
        case .decrease: draft.canDecrease
        case .increase: draft.canIncrease
        case .cancel, .commit: true
        }
    }
}

/// Runs the intent behind a picker control.
struct DraftButton<Label: View>: View {
    var control: DraftControl
    var draft: WaterDraft
    @ViewBuilder var label: Label

    var body: some View {
        Group {
            switch control {
            case .cancel: Button(intent: CancelWaterDraftIntent()) { label }
            case .decrease: Button(intent: AdjustWaterDraftIntent(deltaML: -SettingsLimits.widgetDraftStepML)) { label }
            case .increase: Button(intent: AdjustWaterDraftIntent(deltaML: SettingsLimits.widgetDraftStepML)) { label }
            case .commit: Button(intent: CommitWaterDraftIntent()) { label }
            }
        }
        .buttonStyle(.plain)
        .disabled(!control.isEnabled(draft))
        .accessibilityLabel(control.accessibility(draft))
    }
}

// MARK: - Home Screen

/// A round Home Screen control: − / + filled aqua, ✕ a quiet translucent disc.
struct HomeDraftCircle: View {
    var control: DraftControl
    var draft: WaterDraft
    var diameter: CGFloat = 34
    @Environment(\.widgetRenderingMode) private var mode

    private var isQuiet: Bool { control == .cancel }
    private var isEnabled: Bool { control.isEnabled(draft) }

    var body: some View {
        DraftButton(control: control, draft: draft) {
            Image(systemName: control.systemImage)
                .font(.system(size: diameter * (isQuiet ? 0.38 : 0.45), weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(fill))
                .widgetAccentable(!isQuiet)
                .opacity(isEnabled ? 1 : 0.4)
                // ≥ 44 pt hit area around the visible circle.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var foreground: Color {
        guard mode == .fullColor else { return .primary }
        return isQuiet ? WidgetColor.ocean : .white
    }

    private var fill: AnyShapeStyle {
        if mode != .fullColor { return AnyShapeStyle(Color.primary.opacity(isQuiet ? 0.12 : 0.2)) }
        return isQuiet ? AnyShapeStyle(WidgetColor.ocean.opacity(0.1)) : AnyShapeStyle(WidgetColor.action)
    }
}

/// ✓ on the Home Screen: the picker's main action, the checkmark glyph only (no text, like ✕;
/// DECISIONS W6). Filled aqua and larger than − / +, so it reads as the primary action next to the
/// quiet ✕. Small: a full-width capsule; medium: a round button. VoiceOver: "Log 250 milliliters
/// of water".
struct HomeCommitButton: View {
    var draft: WaterDraft
    var fillsWidth = false
    var diameter: CGFloat = 44
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        DraftButton(control: .commit, draft: draft) {
            Image(systemName: DraftControl.commit.systemImage)
                .font(.system(size: fillsWidth ? 18 : diameter * 0.43, weight: .bold))
                .foregroundStyle(mode == .fullColor ? Color.white : Color.primary)
                .frame(maxWidth: fillsWidth ? .infinity : diameter)
                .frame(width: fillsWidth ? nil : diameter, height: fillsWidth ? 38 : diameter)
                .background {
                    if fillsWidth { Capsule().fill(fill) } else { Circle().fill(fill) }
                }
                .widgetAccentable()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var fill: AnyShapeStyle {
        mode == .fullColor ? AnyShapeStyle(WidgetColor.action) : AnyShapeStyle(Color.primary.opacity(0.2))
    }
}

/// "250" big with "ml" small, the picked amount. Changes snap (G8): no numeric roll, no dimming
/// while an intent runs.
struct HomeDraftAmount: View {
    var draft: WaterDraft
    var font: Font.TextStyle = .title2
    var unitBelow = true
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let layout = unitBelow ? AnyLayout(VStackLayout(spacing: -2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 3))
        layout {
            Text(WidgetCopy.draftAmount(draft.amountML))
                .font(.system(font))
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(mode == .fullColor ? WidgetColor.ocean : .primary)
            Text(WidgetCopy.draftUnit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.draftAmountAccessibility(draft.amountML))
    }
}

/// A preset chip (medium widget): the current amount is filled.
struct HomePresetChip: View {
    var amountML: Int
    var draft: WaterDraft
    @Environment(\.widgetRenderingMode) private var mode

    private var isSelected: Bool { draft.amountML == amountML }

    var body: some View {
        Button(intent: SetWaterDraftIntent(amountML: amountML)) {
            Text(WidgetCopy.draftAmount(amountML))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 46, minHeight: 30)
                .background(Capsule().fill(fill))
                .widgetAccentable(isSelected)
                .frame(minHeight: 40)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WidgetCopy.presetAccessibility(amountML))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        guard mode == .fullColor else { return .primary }
        return isSelected ? .white : WidgetColor.ocean
    }

    private var fill: AnyShapeStyle {
        if mode != .fullColor { return AnyShapeStyle(Color.primary.opacity(isSelected ? 0.3 : 0.1)) }
        return isSelected ? AnyShapeStyle(WidgetColor.action) : AnyShapeStyle(WidgetColor.ocean.opacity(0.1))
    }
}

/// The picker heading: "💧 Log water".
struct HomeDraftTitle: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Label(WidgetCopy.draftTitle, systemImage: "drop.fill")
            .font(.caption.weight(.semibold))
            .widgetTint(WidgetColor.water, mode)
            .widgetAccentable()
            .lineLimit(1)
    }
}

// MARK: - Lock screen

/// Fuely Line and Fuely Rings while picking (`accessoryRectangular`): one row
/// `✕  −  250  +  ✓` with "ml" under the number. ✕ is an outlined circle, − / + filled, ✓ a
/// larger filled circle in the accent group, so each control stays distinct in vibrant mode.
struct AccessoryDraftPicker: View {
    let draft: WaterDraft

    var body: some View {
        HStack(spacing: 0) {
            glyph(.cancel, "xmark.circle", size: 20)
            glyph(.decrease, "minus.circle.fill", size: 21)
            VStack(spacing: -3) {
                Text(WidgetCopy.draftAmount(draft.amountML))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text(WidgetCopy.draftUnit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.8)
            }
            .lineLimit(1)
            .padding(.horizontal, 2)
            .frame(minWidth: 36, maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.draftAmountAccessibility(draft.amountML))
            glyph(.increase, "plus.circle.fill", size: 21)
            glyph(.commit, "checkmark.circle.fill", size: 25, accented: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func glyph(_ control: DraftControl, _ symbol: String, size: CGFloat, accented: Bool = false) -> some View {
        DraftButton(control: control, draft: draft) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .widgetAccentable(accented)
                .opacity(control.isEnabled(draft) ? 1 : 0.35)
                // 28 pt wide where the slot allows (a 6.1" iPhone's ~160 pt slot), narrower rather
                // than running off the right edge on a smaller slot.
                .frame(minWidth: 22, maxWidth: 28, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

/// Fuely Circle (water) while picking (`accessoryCircular`): the top half is the amount, tap it to
/// cycle 150 → 250 → 400 → 500; the bottom half is ✕ (left) and ✓ (right). It also closes by
/// itself after ~2 min.
struct CircleDraftPicker: View {
    let draft: WaterDraft

    var body: some View {
        VStack(spacing: 0) {
            Button(intent: CycleWaterDraftIntent()) {
                VStack(spacing: -3) {
                    Text(WidgetCopy.draftAmount(draft.amountML))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                    Text(WidgetCopy.draftUnit)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .opacity(0.8)
                }
                .lineLimit(1)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WidgetCopy.cycleAccessibility(draft.amountML))

            HStack(spacing: 0) {
                DraftButton(control: .cancel, draft: draft) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .opacity(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                DraftButton(control: .commit, draft: draft) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .widgetAccentable()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .frame(height: 30)
        }
    }
}
