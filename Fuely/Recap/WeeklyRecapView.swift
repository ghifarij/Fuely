import FuelyCore
import SwiftUI

/// The weekly recap (DECISIONS WR3): one full screen, no paging. "Last week" + dates → one big
/// animated emoji → headline → one stats card (three ring tiles + their detail lines) → one
/// suggestion → "Start this week", the only way to close. Nothing scrolls at normal text sizes down
/// to the 4.7" SE; when the content can't fit (accessibility sizes) it scrolls and the button stays
/// pinned.
struct WeeklyRecapView: View {
    /// The saved recap (WR8): every word comes from it, nothing is recomputed here.
    var recap: WeeklyRecap
    var onClose: () -> Void

    @Environment(\.calendar) private var calendar

    /// The week in the phone's region format (D3), e.g. "Nov 2 – 8" or "2–8 Nov".
    private var dateRange: String { WeeklyRecapCopy.dateRange(recap.week, calendar: calendar) }

    var body: some View {
        GeometryReader { proxy in
            let layout = RecapLayout(screenHeight: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            ViewThatFits(in: .vertical) {
                content(layout)
                ScrollView {
                    content(layout)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { closeButton }
        .fuelyScreenBackground()
        .fontDesign(.rounded)
    }

    /// Flexible gaps share the spare height on taller phones; in the scrolling fallback they
    /// collapse to their minimums.
    private func content(_ layout: RecapLayout) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.gap)
            header
            Spacer(minLength: layout.gap).frame(maxHeight: FuelySpacing.xl)
            AnimatedEmojiView(mood: recap.mood, size: layout.emojiSize, delay: 0.35)
            Spacer(minLength: layout.gap).frame(maxHeight: FuelySpacing.xl)
            summary
            Spacer(minLength: layout.gap * 2)
            RecapStatsCard(rows: recap.rows, compact: layout.compact)
            Spacer(minLength: layout.gap * 1.5).frame(maxHeight: FuelySpacing.xl)
            closingLine
            Spacer(minLength: layout.gap)
        }
        .padding(.horizontal, FuelySpacing.gutter)
        .frame(maxWidth: 560)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Last week")
                .font(FuelyFont.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.secondary)
            Text(dateRange)
                .font(FuelyFont.detail.weight(.semibold))
                .foregroundStyle(FuelyColor.ocean)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last week, \(dateRange)")
        .accessibilityAddTraits(.isHeader)
    }

    private var summary: some View {
        VStack(spacing: FuelySpacing.xxs) {
            Text(recap.headline)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(FuelyColor.ocean)
                .accessibilityAddTraits(.isHeader)
            Text(recap.supporting)
                .font(FuelyFont.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, FuelySpacing.xs)
    }

    @ViewBuilder
    private var closingLine: some View {
        Group {
            if recap.closingIsSuggestion {
                // The saved suggestion has no lead-in and starts lower-case (WR5).
                Text("\(Text("This week:").fontWeight(.semibold).foregroundStyle(FuelyColor.ocean)) \(recap.closing)")
            } else {
                Text(recap.closing)
            }
        }
        .font(FuelyFont.detail)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, FuelySpacing.m)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Text("Start this week")
                .font(FuelyFont.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .fuelyProminentButton()
        .controlSize(.large)
        .tint(FuelyColor.action)
        .frame(maxWidth: 560)
        .padding(.horizontal, FuelySpacing.l)
        .padding(.top, FuelySpacing.m)
        .padding(.bottom, FuelySpacing.m)
        .frame(maxWidth: .infinity)
        // Scrolling content (accessibility sizes) fades out under the pinned button instead of
        // showing through around it. Invisible when nothing scrolls.
        .background {
            let floor = Color(.fuelyBackgroundBottom)
            LinearGradient(stops: [.init(color: floor.opacity(0), location: 0),
                                   .init(color: floor, location: 0.28),
                                   .init(color: floor, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)
        }
    }
}

/// Sizes that depend on the phone: the 4.7" SE (667 pt, 693 pt with Display Zoom on larger phones)
/// gets a smaller emoji and tighter gaps, never smaller text, so everything fits without scrolling (WR3).
private struct RecapLayout {
    var compact: Bool
    var emojiSize: CGFloat
    /// Smallest gap between the blocks.
    var gap: CGFloat

    init(screenHeight: CGFloat) {
        compact = screenHeight <= 700
        emojiSize = compact ? 56 : 104
        gap = compact ? 5 : FuelySpacing.s
    }
}

// MARK: - Stats card

private struct RecapStatsCard: View {
    var rows: [WeeklyRecap.Row]
    var compact: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            // Three columns can't hold accessibility text sizes: there each ring gets a full-width row.
            if dynamicTypeSize.isAccessibilitySize {
                largeTextRows
            } else {
                tiles
            }
        }
        .fuelyCard(padding: compact ? FuelySpacing.s : FuelySpacing.m)
        .modifier(MaterialCardEdge())
    }

    // Accessibility text sizes: label → stat → detail, one row per ring.
    private var largeTextRows: some View {
        VStack(spacing: compact ? 9 : 14) {
            ForEach(rows) { row in
                if row.id != rows.first?.id {
                    Divider().padding(.leading, RecapLargeTextRow.ringSize + RecapLargeTextRow.spacing)
                }
                RecapLargeTextRow(row: row)
            }
        }
    }

    // Three ring tiles, then the detail lines.
    private var tiles: some View {
        VStack(spacing: compact ? FuelySpacing.s : FuelySpacing.m) {
            HStack(alignment: .top, spacing: FuelySpacing.xs) {
                ForEach(rows) { row in
                    RecapStatTile(row: row, ringSize: compact ? 70 : 78)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: FuelySpacing.xs) {
                        Image(systemName: row.ring.systemImage)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(row.ring.color)
                            .frame(width: 22)
                        Text(row.line)
                            .font(FuelyFont.detail)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FuelySpacing.xxs)
            // Each tile already reads its own line to VoiceOver.
            .accessibilityHidden(true)
        }
    }
}

/// iOS 18–25 only: the material card nearly disappears on the light gradient, so it gets a hairline.
/// Local to the recap; the shared `fuelyCard` helper is unchanged. Liquid Glass has its own edge.
private struct MaterialCardEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.overlay {
                RoundedRectangle(cornerRadius: FuelySpacing.cardRadius, style: .continuous)
                    .strokeBorder(FuelyColor.ocean.opacity(0.16), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The stat as text: the number carries the weight ("6 of 7 days", "84 avg sleep score").
private struct RecapStatText: View {
    var row: WeeklyRecap.Row

    var body: some View {
        Group {
            if let number = row.number {
                let emphasized = Text(number)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(FuelyColor.ocean)
                Text("\(emphasized) \(row.unit)")
            } else {
                Text(row.stat)
            }
        }
        .font(.system(.title3, design: .rounded, weight: .semibold))
        .foregroundStyle(.primary)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A ring with either the ring's glyph or its short number ("6/7", "84", "—") inside.
private struct RecapRing: View {
    var row: WeeklyRecap.Row
    var size: CGFloat
    var showsNumber: Bool

    var body: some View {
        ProgressRing(fraction: row.fraction, color: row.ring.color, lineWidth: size * 0.11)
            .frame(width: size, height: size)
            .overlay {
                if showsNumber {
                    // Sized to the ring, like the percentage in the water drop.
                    Text(row.shortNumber)
                        .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(!row.hasVerdict ? AnyShapeStyle(.secondary) : AnyShapeStyle(FuelyColor.ocean))
                } else {
                    Image(systemName: row.ring.systemImage)
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(row.ring.color)
                }
            }
            .accessibilityHidden(true)
    }
}

/// One ring as a full-width row: the stats card at accessibility text sizes.
private struct RecapLargeTextRow: View {
    var row: WeeklyRecap.Row

    static let ringSize: CGFloat = 52
    static let spacing: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: Self.spacing) {
            RecapRing(row: row, size: Self.ringSize, showsNumber: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.ring.title)
                    .font(FuelyFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                RecapStatText(row: row)
                Text(row.line)
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenSummary)
    }
}

/// One ring tile: big ring with the number inside, label and caption below.
private struct RecapStatTile: View {
    var row: WeeklyRecap.Row
    var ringSize: CGFloat

    var body: some View {
        VStack(spacing: FuelySpacing.xs) {
            RecapRing(row: row, size: ringSize, showsNumber: true)
            VStack(spacing: 1) {
                Text(row.ring.title)
                    .font(FuelyFont.cardTitle)
                    .foregroundStyle(.primary)
                Text(row.caption)
                    .font(FuelyFont.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenSummary)
    }
}

#if DEBUG
#Preview("All strong") { WeeklyRecapView(recap: WeeklyRecapSamples.allStrong) {} }
#Preview("Two strong") { WeeklyRecapView(recap: WeeklyRecapSamples.twoStrong) {} }
#Preview("One strong, no Watch") { WeeklyRecapView(recap: WeeklyRecapSamples.oneStrong) {} }
#Preview("Mixed, dark") {
    WeeklyRecapView(recap: WeeklyRecapSamples.mixed) {}
        .preferredColorScheme(.dark)
}
#Preview("Low") { WeeklyRecapView(recap: WeeklyRecapSamples.low) {} }
#Preview("Not enough data") { WeeklyRecapView(recap: WeeklyRecapSamples.notEnoughData) {} }
#Preview("Two strong, accessibility size") {
    WeeklyRecapView(recap: WeeklyRecapSamples.twoStrong) {}
        .dynamicTypeSize(.accessibility3)
}
#Preview("Mixed, accessibility size") {
    WeeklyRecapView(recap: WeeklyRecapSamples.mixed) {}
        .dynamicTypeSize(.accessibility3)
}
#endif
