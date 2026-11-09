import AppIntents
import FuelyCore
import SwiftUI
import WidgetKit

/// Fuely's brand colors for the widgets (DECISIONS D1). Copies of the app's color sets live in the
/// widget's asset catalog, because the extension can't use the app target's code.
enum WidgetColor {
    static let ocean = Color(.fuelyOcean)
    static let water = Color(.fuelyAqua)
    static let sleep = Color(.fuelySleep)
    static let workout = Color(.fuelyWorkout)
    static let nudge = Color(.fuelyNudge)
    static let action = Color(.fuelyAction)

    /// The calm ocean gradient behind the Home Screen widgets (removed by the system in tinted / clear modes).
    static let background = LinearGradient(
        colors: [Color(.fuelyBackgroundTop), Color(.fuelyBackgroundBottom)],
        startPoint: .top, endPoint: .bottom)

    static func tint(_ metric: WidgetMetric) -> Color {
        switch metric {
        case .water: water
        case .sleep: sleep
        case .workouts: workout
        }
    }
}

extension WidgetMetric {
    var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .sleep: "moon.zzz.fill"
        case .workouts: "figure.run"
        }
    }
}

/// A progress ring for the widgets. Water can lap past 100% (DECISIONS W3). In full color it uses
/// the brand tint; in the lock screen's vibrant mode and the tinted Home Screen it draws in the
/// primary color, with the progress arc in the accent group (G7).
struct WidgetRing<Content: View>: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isFullColor: Bool { renderingMode == .fullColor }
    private var clamped: Double { fraction.isFinite ? max(fraction, 0) : 0 }
    private var overflow: Double {
        guard clamped > 1 else { return 0 }
        let rest = clamped.truncatingRemainder(dividingBy: 1)
        return rest == 0 ? 1 : rest
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(isFullColor ? tint.opacity(0.2) : Color.primary.opacity(0.25), lineWidth: lineWidth)
            arc(to: min(clamped, 1))
            if overflow > 0 {
                arc(to: overflow)
                    .shadow(color: .black.opacity(isFullColor ? 0.3 : 0), radius: lineWidth / 3)
            }
            content
        }
        .padding(lineWidth / 2)
    }

    private func arc(to end: Double) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .stroke(isFullColor ? tint : Color.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .widgetAccentable()
    }
}

extension WidgetRing where Content == EmptyView {
    init(fraction: Double, tint: Color, lineWidth: CGFloat) {
        self.init(fraction: fraction, tint: tint, lineWidth: lineWidth) { EmptyView() }
    }
}

/// The interactive (+) on an Idle widget: opens the in-widget amount picker (DECISIONS W6b) via
/// `StartWaterDraftIntent`, in the widget process; nothing is logged until ✓. Works only while
/// the phone is unlocked (G6).
struct AddWaterButton<Label: View>: View {
    @ViewBuilder var label: Label

    var body: some View {
        Button(intent: StartWaterDraftIntent()) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WidgetCopy.startAccessibility)
    }
}

/// The lock screen (+): a filled plus circle with the plus cut out, so it reads in vibrant mode.
struct AccessoryAddGlyph: View {
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .widgetAccentable()
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Content color that follows the rendering mode: the brand tint in full color, primary otherwise.
    func widgetTint(_ color: Color, _ mode: WidgetRenderingMode) -> some View {
        foregroundStyle(mode == .fullColor ? color : Color.primary)
    }
}
