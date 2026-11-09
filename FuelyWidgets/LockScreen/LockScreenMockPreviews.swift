import FuelyCore
import SwiftUI
import WidgetKit

#if DEBUG
// Xcode 27.1's preview renderer returns empty snapshots for the accessory families, and a widget
// extension can only host widget previews. So this preview-only widget (not in the bundle) draws
// the lock screen views on a mock lock screen inside a Large widget: dark, white content, roughly
// how the vibrant mode draws them. The real `#Preview(as: .accessory…)` previews sit next to each
// widget for Xcode's canvas.

private struct LockScreenMock<Content: View>: View {
    /// The inline widget's slot, next to the date above the clock.
    var inline: FuelyEntry
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 6) {
            FuelyTextView(entry: inline).font(.system(size: 18, weight: .semibold))
            Text("9:41").font(.system(size: 64, weight: .bold, design: .rounded))
            content
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}

/// Accessory sizes on a 6.1" iPhone (points).
private enum AccessorySize {
    static let rectangular = CGSize(width: 160, height: 72)
    static let circular = CGSize(width: 72, height: 72)
}

private struct AccessoryFrame<Content: View>: View {
    var size: CGSize
    var background = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .background {
                if background { Circle().fill(.white.opacity(0.18)) }
            }
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [3])) }
    }
}

/// Preview-only: not part of `FuelyWidgetsBundle`.
struct LockScreenMockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FuelyLockScreenMock", provider: FuelyProvider()) { entry in
            LockScreenMockView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.05, green: 0.2, blue: 0.35), Color(red: 0.1, green: 0.35, blue: 0.45)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .supportedFamilies([.systemLarge])
    }
}

/// `entry.metric` is ignored; each circle shows its own metric. The entry's scenario drives the data.
private struct LockScreenMockView: View {
    let entry: FuelyEntry

    private func with(_ metric: WidgetMetric) -> FuelyEntry {
        FuelyEntry(date: entry.date, summary: entry.summary, settings: entry.settings, metric: metric, draft: entry.draft)
    }

    var body: some View {
        LockScreenMock(inline: entry) {
            VStack(spacing: 10) {
                AccessoryFrame(size: AccessorySize.rectangular) { FuelyLineView(entry: entry) }
                AccessoryFrame(size: AccessorySize.rectangular) { FuelyRingsView(entry: entry) }
                HStack(spacing: 12) {
                    ForEach(WidgetMetric.allCases, id: \.self) { metric in
                        AccessoryFrame(size: AccessorySize.circular, background: true) { FuelyCircleView(entry: with(metric)) }
                    }
                }
            }
        }
    }
}

#Preview("Lock screen mock", as: .systemLarge) {
    LockScreenMockWidget()
} timeline: {
    WidgetSamples.entry(.onTrack)
    WidgetSamples.entry(.behindNoSleep)
    WidgetSamples.entry(.overGoal)
    WidgetSamples.entry(.onTrack, draftML: 250)
}
#endif
