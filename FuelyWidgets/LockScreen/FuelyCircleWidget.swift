import FuelyCore
import SwiftUI
import WidgetKit

/// Fuely Circle (DECISIONS G4): `accessoryCircular`, configurable. Water = ring with (+) (the whole
/// circle is the button, too small for a separate tap target), sleep score, or workouts x/y
/// (tap opens Today). Water's (+) opens the amount picker (W6b, `CircleDraftPicker`): tap the
/// amount to cycle presets, ✓ logs, ✕ cancels.
struct FuelyCircleWidget: Widget {
    static let kind = "FuelyCircle"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: FuelyCircleConfiguration.self, provider: FuelyCircleProvider()) { entry in
            FuelyCircleView(entry: entry)
        }
        .configurationDisplayName("Fuely Circle")
        .description("Water with (+), your sleep score, or workouts this week.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct FuelyCircleView: View {
    let entry: FuelyEntry

    var body: some View {
        Group {
            if entry.metric == .water, let draft = entry.draft {
                CircleDraftPicker(draft: draft)
                    .widgetSnaps()
            } else if entry.metric == .water {
                AddWaterButton { ring }
                    .widgetSnaps()
            } else {
                ring
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WidgetCopy.accessibility(entry.metric, in: entry.summary))
                    .widgetSnaps()
            }
        }
        .widgetSnaps(entry: entry)
        .widgetURL(FuelyDeepLink.today.url)
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    private var ring: some View {
        WidgetRing(fraction: WidgetRings.fraction(entry.metric, in: entry.summary), tint: .primary, lineWidth: 5) {
            VStack(spacing: 0) {
                if entry.metric != .water {
                    Image(systemName: entry.metric.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .widgetSnaps()
                }
                Text(WidgetCopy.value(entry.metric, in: entry.summary))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if entry.metric == .water {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                        .widgetAccentable()
                        .widgetSnaps()
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(2)
        .contentShape(Circle())
    }
}

#Preview("Circle · Water", as: .accessoryCircular) {
    FuelyCircleWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, metric: .water)
    WidgetSamples.entry(.overGoal, metric: .water)
}

#Preview("Circle · Water picking", as: .accessoryCircular) {
    FuelyCircleWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, metric: .water, draftML: 250)
}

#Preview("Circle · Sleep", as: .accessoryCircular) {
    FuelyCircleWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, metric: .sleep)
    WidgetSamples.entry(.behindNoSleep, metric: .sleep)
}

#Preview("Circle · Workouts", as: .accessoryCircular) {
    FuelyCircleWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, metric: .workouts)
    WidgetSamples.entry(.overGoal, metric: .workouts)
}
