import FuelyCore
import SwiftUI
import WidgetKit

/// Fuely Text (DECISIONS G1): `accessoryInline`, the slot above the clock.
/// "💧1.2L · 😴82 · 🏃2/3". Text only (inline widgets can't hold buttons).
struct FuelyTextWidget: Widget {
    static let kind = "FuelyText"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FuelyProvider()) { entry in
            FuelyTextView(entry: entry)
        }
        .configurationDisplayName("Fuely Text")
        .description("Water, sleep score and workouts above the clock.")
        .supportedFamilies([.accessoryInline])
    }
}

struct FuelyTextView: View {
    let entry: FuelyEntry

    var body: some View {
        ViewThatFits {
            Text(WidgetCopy.inline(entry.summary))
            Text(WidgetCopy.inlineCompact(entry.summary))
        }
        .accessibilityLabel(WidgetCopy.accessibility(entry.summary))
        .widgetSnaps(entry: entry)
        .widgetURL(FuelyDeepLink.today.url)
        .containerBackground(for: .widget) {}
    }
}

#Preview("Text", as: .accessoryInline) {
    FuelyTextWidget()
} timeline: {
    WidgetSamples.entry(.onTrack)
    WidgetSamples.entry(.behindNoSleep)
    WidgetSamples.entry(.overGoal)
}
