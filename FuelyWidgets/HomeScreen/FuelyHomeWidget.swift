import FuelyCore
import SwiftUI
import WidgetKit

/// Fuely on the Home Screen (DECISIONS G5): `systemSmall` and `systemMedium`, rings + (+).
/// Full color on the ocean gradient; in the tinted / clear Home Screen styles the system drops the
/// background and the rings and button move to the accent group (G7). Tap outside (+) opens Today.
/// (+) turns the widget into the amount picker (W6b) until ✓, ✕ or ~2 min pass.
struct FuelyHomeWidget: Widget {
    static let kind = "FuelyHome"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FuelyProvider()) { entry in
            FuelyHomeView(entry: entry)
        }
        .configurationDisplayName("Fuely")
        .description("Water, sleep and workout rings, with (+) to log water.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FuelyHomeView: View {
    let entry: FuelyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch (family, entry.draft) {
            case (.systemMedium, let draft?): MediumDraftView(summary: entry.summary, draft: draft)
            case (.systemMedium, nil): MediumHomeView(entry: entry)
            case (_, let draft?): SmallDraftView(draft: draft)
            case (_, nil): SmallHomeView(entry: entry)
            }
        }
        .fontDesign(.rounded)
        .widgetURL(FuelyDeepLink.today.url)
        .containerBackground(for: .widget) { WidgetColor.background }
    }
}

// MARK: - Small

struct SmallHomeView: View {
    let entry: FuelyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                WaterHeadline(summary: entry.summary, valueFont: .title2, compactPace: true)
                Spacer(minLength: 0)
                AddWaterButton { RoundAddGlyph() }
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(WidgetMetric.allCases, id: \.self) { metric in
                    if metric != .water { Spacer(minLength: 4) }
                    RingTile(metric: metric, summary: entry.summary, size: 38, lineWidth: 5, showsTitle: false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ringsAccessibility)
        }
    }

    private var ringsAccessibility: String {
        [WidgetMetric.sleep, .workouts].map { WidgetCopy.accessibility($0, in: entry.summary) }.joined(separator: ". ")
    }
}

// MARK: - Medium

struct MediumHomeView: View {
    let entry: FuelyEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Water, litres and a fixed 44 pt (+) as one compact group, centered horizontally and
            // vertically so it lines up with the rings (G5).
            VStack(alignment: .center, spacing: 8) {
                WaterHeadline(summary: entry.summary, valueFont: .title, compactPace: false)
                AddWaterButton { MediumAddGlyph() }
            }
            .fixedSize()
            .frame(maxHeight: .infinity, alignment: .center)
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 8) {
                ForEach(WidgetMetric.allCases, id: \.self) { metric in
                    RingTile(metric: metric, summary: entry.summary, size: 54, lineWidth: 7, showsTitle: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([WidgetMetric.sleep, .workouts]
                .map { WidgetCopy.accessibility($0, in: entry.summary) }.joined(separator: ". "))
        }
    }
}

// MARK: - Amount picker (W6b)

/// Small picker: "💧 Log water  ✕" / "−  250 ml  +" / a full-width ✓.
struct SmallDraftView: View {
    let draft: WaterDraft

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HomeDraftTitle()
                Spacer(minLength: 0)
                HomeDraftCircle(control: .cancel, draft: draft, diameter: 28)
                    .padding(.trailing, -8)
            }
            .padding(.top, -8)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                HomeDraftCircle(control: .decrease, draft: draft)
                    .padding(.leading, -5)
                HomeDraftAmount(draft: draft, font: .title)
                    .frame(maxWidth: .infinity)
                HomeDraftCircle(control: .increase, draft: draft)
                    .padding(.trailing, -5)
            }
            Spacer(minLength: 0)
            HomeCommitButton(draft: draft, fillsWidth: true)
                .padding(.bottom, -4)
        }
    }
}

/// Medium picker: heading and today's total, "−  250 ml  +", presets 150 / 250 / 500, ✕ and a round ✓.
struct MediumDraftView: View {
    let summary: TodaySummary
    let draft: WaterDraft

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    HomeDraftTitle()
                    Text("\(FuelyFormat.water(summary.water.totalML)) of \(FuelyFormat.water(summary.water.goalML))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    HomeDraftCircle(control: .decrease, draft: draft, diameter: 36)
                        .padding(.leading, -4)
                    HomeDraftAmount(draft: draft, font: .title, unitBelow: false)
                        .frame(minWidth: 92)
                    HomeDraftCircle(control: .increase, draft: draft, diameter: 36)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(WaterDraft.presetsML, id: \.self) { amount in
                        HomePresetChip(amountML: amount, draft: draft)
                    }
                }
                .padding(.bottom, -4)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                HomeDraftCircle(control: .cancel, draft: draft, diameter: 30)
                    .padding(.top, -7)
                    .padding(.trailing, -7)
                Spacer(minLength: 0)
                HomeCommitButton(draft: draft)
                    .padding(.bottom, -4)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Pieces

/// "Water / 1.25 L / of 2.4 L / On track".
private struct WaterHeadline: View {
    let summary: TodaySummary
    let valueFont: Font.TextStyle
    let compactPace: Bool
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        VStack(alignment: headlineAlignment, spacing: 1) {
            Label("Water", systemImage: "drop.fill")
                .font(.caption.weight(.semibold))
                .widgetTint(WidgetColor.water, mode)
                .widgetAccentable()
            Text(FuelyFormat.water(summary.water.totalML))
                .font(.system(valueFont))
                .fontWeight(.bold)
                .foregroundStyle(mode == .fullColor ? WidgetColor.ocean : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.accessibility(.water, in: summary))
    }

    /// Small: leading, beside its (+). Medium: centered above its (+).
    private var headlineAlignment: HorizontalAlignment { compactPace ? .leading : .center }
}

/// A ring with the metric's symbol (small) or value (medium) inside, and labels below.
private struct RingTile: View {
    let metric: WidgetMetric
    let summary: TodaySummary
    let size: CGFloat
    let lineWidth: CGFloat
    let showsTitle: Bool
    @Environment(\.widgetRenderingMode) private var mode

    /// Water as a percentage (the litres are already in the headline), the others as their value.
    private var value: String {
        metric == .water ? FuelyFormat.percent(summary.water.fraction) : WidgetCopy.value(metric, in: summary)
    }

    var body: some View {
        VStack(spacing: 3) {
            WidgetRing(fraction: WidgetRings.fraction(metric, in: summary), tint: WidgetColor.tint(metric), lineWidth: lineWidth) {
                if showsTitle {
                    Text(value)
                        .font(.system(size: 15, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, lineWidth / 2 + 3)
                } else {
                    Image(systemName: metric.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .widgetTint(WidgetColor.tint(metric), mode)
                }
            }
            .frame(width: size, height: size)
            if showsTitle {
                Text(WidgetCopy.title(metric))
                    .font(.caption2.weight(.semibold))
                    .widgetTint(WidgetColor.tint(metric), mode)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(value)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(minWidth: size)
    }
}

/// Small widget (+): a filled aqua circle. In tinted / clear modes a translucent primary disc.
private struct RoundAddGlyph: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(mode == .fullColor ? Color.white : Color.primary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(mode == .fullColor ? AnyShapeStyle(WidgetColor.action) : AnyShapeStyle(Color.primary.opacity(0.2))))
            .widgetAccentable()
            .frame(width: 44, height: 44, alignment: .topTrailing)
            .contentShape(Rectangle())
    }
}

/// Medium widget (+): the "+" glyph only (DECISIONS W6) in a fixed 44 pt filled aqua circle,
/// centered under the water column (G5). In tinted / clear modes a translucent primary disc in the
/// accent group (VoiceOver: "Log water, choose an amount", see AddWaterButton).
private struct MediumAddGlyph: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(mode == .fullColor ? Color.white : Color.primary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(mode == .fullColor ? AnyShapeStyle(WidgetColor.action) : AnyShapeStyle(Color.primary.opacity(0.2))))
            .widgetAccentable()
            .contentShape(Circle())
    }
}

#Preview("Small", as: .systemSmall) {
    FuelyHomeWidget()
} timeline: {
    WidgetSamples.entry(.onTrack)
    WidgetSamples.entry(.behindNoSleep)
    WidgetSamples.entry(.overGoal)
}

#Preview("Small · picking", as: .systemSmall) {
    FuelyHomeWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, draftML: 250)
    WidgetSamples.entry(.onTrack, draftML: 50)
}

#Preview("Medium · picking", as: .systemMedium) {
    FuelyHomeWidget()
} timeline: {
    WidgetSamples.entry(.onTrack, draftML: 250)
    WidgetSamples.entry(.onTrack, draftML: 2000)
}

#Preview("Medium", as: .systemMedium) {
    FuelyHomeWidget()
} timeline: {
    WidgetSamples.entry(.onTrack)
    WidgetSamples.entry(.behindNoSleep)
    WidgetSamples.entry(.overGoal)
}
