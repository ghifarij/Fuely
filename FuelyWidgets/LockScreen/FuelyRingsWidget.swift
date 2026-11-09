import FuelyCore
import SwiftUI
import WidgetKit

/// Fuely Rings (DECISIONS G3): `accessoryRectangular`, three mini rings (water, sleep, workouts)
/// + (+). Tapping outside the button opens Today. (+) opens the amount picker (W6b).
struct FuelyRingsWidget: Widget {
    static let kind = "FuelyRings"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FuelyProvider()) { entry in
            FuelyRingsView(entry: entry)
        }
        .configurationDisplayName("Fuely Rings")
        .description("Water, sleep and workout rings, with (+) to log water.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct FuelyRingsView: View {
    let entry: FuelyEntry

    var body: some View {
        Group {
            if let draft = entry.draft {
                AccessoryDraftPicker(draft: draft)
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(FuelyDeepLink.today.url)
        .containerBackground(for: .widget) {}
    }

    /// The rings share whatever width (+) leaves (≈ 37 pt each in a 160 × 72 slot) instead of a
    /// fixed size, so the row never runs past the slot's right edge.
    private var idle: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(WidgetMetric.allCases, id: \.self) { metric in
                    MiniRing(metric: metric, summary: entry.summary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.accessibility(entry.summary))
            AddWaterButton {
                AccessoryAddGlyph(size: 24)
            }
        }
    }
}

/// A lock screen ring with the value inside and the metric's symbol below. The ring is as large
/// as the space allows (square, up to 44 pt).
private struct MiniRing: View {
    let metric: WidgetMetric
    let summary: TodaySummary

    var body: some View {
        VStack(spacing: 2) {
            WidgetRing(fraction: WidgetRings.fraction(metric, in: summary), tint: .primary, lineWidth: 4) {
                Text(WidgetCopy.value(metric, in: summary))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 44, maxHeight: 44)
            Image(systemName: metric.symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Rings · picking", as: .accessoryRectangular) {
    FuelyRingsWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, draftML: 250)
}

#Preview("Rings", as: .accessoryRectangular) {
    FuelyRingsWidget()
} timeline: {
    WidgetSamples.entry(.onTrack)
    WidgetSamples.entry(.behindNoSleep)
    WidgetSamples.entry(.overGoal)
}
