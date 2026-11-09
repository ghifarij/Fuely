import SwiftUI

/// A circular progress ring that can go past 100% like the Move ring (DECISIONS W3): the second
/// lap is drawn on top with a soft shadow at its leading end.
struct ProgressRing: View {
    /// 0…∞; values above 1 draw extra laps.
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 14

    private var clamped: Double { fraction.isFinite ? max(fraction, 0) : 0 }
    private var firstLap: Double { min(clamped, 1) }
    /// Progress of the current overflow lap (0 when ≤ 100%).
    private var overflow: Double {
        guard clamped > 1 else { return 0 }
        let rest = clamped.truncatingRemainder(dividingBy: 1)
        return rest == 0 ? 1 : rest
    }

    var body: some View {
        ZStack {
            Circle().stroke(FuelyColor.track, lineWidth: lineWidth)
            arc(to: firstLap)
            if overflow > 0 {
                arc(to: overflow)
                    .shadow(color: .black.opacity(0.25), radius: lineWidth / 4)
            }
        }
        .padding(lineWidth / 2)
        .animation(.spring(duration: 0.6), value: clamped)
        .accessibilityHidden(true)
    }

    private func arc(to end: Double) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

/// A row of segments, one per goal step (e.g. workout days this week); filled segments
/// beyond the goal are not drawn (the label carries "4/3").
struct SegmentedProgressBar: View {
    var filled: Int
    var total: Int
    var color: Color
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: FuelySpacing.xxs) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(FuelyColor.track))
                    .frame(height: height)
            }
        }
        .animation(.spring(duration: 0.5), value: filled)
        .accessibilityHidden(true)
    }
}

/// A linear bar that can show more than 100% by filling completely.
struct ProgressBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(FuelyColor.track)
                Capsule().fill(color.gradient)
                    .frame(width: proxy.size.width * min(max(fraction.isFinite ? fraction : 0, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: fraction)
        .accessibilityHidden(true)
    }
}

#Preview("Rings and bars") {
    VStack(spacing: FuelySpacing.l) {
        HStack(spacing: FuelySpacing.m) {
            ProgressRing(fraction: 0.35, color: FuelyColor.water).frame(width: 90, height: 90)
            ProgressRing(fraction: 1.0, color: FuelyColor.sleep).frame(width: 90, height: 90)
            ProgressRing(fraction: 1.4, color: FuelyColor.water).frame(width: 90, height: 90)
        }
        SegmentedProgressBar(filled: 2, total: 3, color: FuelyColor.workout)
        ProgressBar(fraction: 0.6, color: FuelyColor.water)
    }
    .padding()
    .fuelyCard()
    .padding()
    .frame(maxHeight: .infinity)
    .fuelyScreenBackground()
}
