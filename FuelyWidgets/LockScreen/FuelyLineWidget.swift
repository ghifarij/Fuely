import FuelyCore
import SwiftUI
import WidgetKit

/// Fuely Line (DECISIONS G2): `accessoryRectangular`, three rows "💧 1.2/2.4L" / "😴 82" / "🏃 2/3"
/// with (+) on the right, vertically centered. (+) opens the in-widget amount picker (W6b);
/// tapping the text opens the quick-log sheet (`fuely://quick-log`). The emoji are drawn at a
/// smaller size than the values so they sit at the text's cap height instead of towering over it.
struct FuelyLineWidget: Widget {
    static let kind = "FuelyLine"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FuelyProvider()) { entry in
            FuelyLineView(entry: entry)
        }
        .configurationDisplayName("Fuely Line")
        .description("Water, sleep and workouts at a glance, with (+) to log water.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct FuelyLineView: View {
    let entry: FuelyEntry

    var body: some View {
        Group {
            if let draft = entry.draft {
                AccessoryDraftPicker(draft: draft)
                    .widgetSnaps()
            } else {
                idle
                    .widgetSnaps()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetSnaps(entry: entry)
        .widgetURL(FuelyDeepLink.quickLog.url)
        .containerBackground(for: .widget) {}
    }

    private var idle: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(WidgetMetric.allCases, id: \.self) { metric in
                    row(metric)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.accessibility(entry.summary))
            .accessibilityHint("Opens quick log")

            AddWaterButton {
                AccessoryAddGlyph(size: 24)
            }
        }
        // Three rows fill the 72 pt slot at the default text size; larger sizes would clip.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    /// "💧 1.2/2.4L": the emoji at footnote size (≈ the headline's cap height), the value in headline.
    private func row(_ metric: WidgetMetric) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(WidgetCopy.lineEmoji(metric))
                .font(.footnote)
            Text(WidgetCopy.lineValue(metric, in: entry.summary))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

#Preview("Line · picking", as: .accessoryRectangular) {
    FuelyLineWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, draftML: 250)
}

#Preview("Line", as: .accessoryRectangular) {
    FuelyLineWidget()
} timeline: {
    WidgetSamples.entry(.onTrack)
    WidgetSamples.entry(.behindNoSleep)
    WidgetSamples.entry(.overGoal)
}
