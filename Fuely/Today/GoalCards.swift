import FuelyCore
import SwiftUI

/// Water (DECISIONS T4, W3, W4): the animated drop with today's %, the total (every source) vs the
/// goal, and the Log Water button. The pace badge lives in the quick-log sheet.
struct WaterCard: View {
    var summary: TodaySummary
    /// `AppModel.openingRiseRequestedAt` (T4a).
    var riseRequestedAt: Date? = nil
    /// `AppModel.fuelyLogCount` (T4e).
    var fuelyLogCount = 0
    var onRiseConsumed: () -> Void = {}
    /// `AppModel.claimGoalCelebration` (T4c).
    var claimCelebration: () -> Bool = { false }
    var onLog: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with Dynamic Type, capped so the drop never crowds the text at accessibility sizes (T4d).
    @ScaledMetric(relativeTo: .largeTitle) private var scaledDropHeight: CGFloat = 176

    private var water: WaterProgress { summary.water }
    private var dropHeight: CGFloat { min(scaledDropHeight, 220) }

    var body: some View {
        VStack(spacing: FuelySpacing.m) {
            VStack(spacing: FuelySpacing.s) {
                WaterDropView(fraction: water.fraction, height: dropHeight, riseRequestedAt: riseRequestedAt,
                              fuelyLogCount: fuelyLogCount, onRiseConsumed: onRiseConsumed, claimCelebration: claimCelebration)
                    .padding(.top, FuelySpacing.xs)
                totalLine
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TodayCopy.waterAccessibility(water))

            Button(action: onLog) {
                Label("Log water", systemImage: "plus")
                    .font(FuelyFont.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .fuelyProminentButton()
            .controlSize(.large)
            .tint(FuelyColor.action)
            .accessibilityHint("Opens quick amounts and undo")
        }
        .fuelyCard(tint: FuelyColor.water)
    }

    /// "1.5 L of 2.4 L" on one line; stacked at accessibility sizes so nothing truncates.
    private var totalLine: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: FuelySpacing.xs))
        return layout {
            Text(FuelyFormat.water(water.totalML))
                .font(FuelyFont.hero)
                .monospacedDigit()
                .foregroundStyle(FuelyColor.ocean)
                .contentTransition(.numericText(value: Double(water.totalML)))
            Text("of \(FuelyFormat.water(water.goalML))")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        // Animates the layout too, so "of 2.4 L" slides with the rolling total instead of jumping.
        .animation(.snappy, value: water.totalML)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "On track" / "Goal reached" / "350 ml behind pace".
struct PaceBadge: View {
    var water: WaterProgress

    var body: some View {
        HStack(spacing: FuelySpacing.xxs) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(TodayCopy.paceText(water))
        }
            .font(FuelyFont.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, FuelySpacing.xs)
            .padding(.vertical, FuelySpacing.xxs)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var icon: String {
        switch water.status {
        case .goalMet: "checkmark.circle.fill"
        case .onTrack: "water.waves"
        case .behind: "clock.fill"
        }
    }

    private var color: Color { water.status == .behind ? FuelyColor.nudge : FuelyColor.ocean }
}

/// Fuely's sleep score for last night, or "—" with the Watch hint (S2, S5, S7).
struct SleepCard: View {
    var score: Int?
    var goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.xs) {
            CardTitle("Sleep", systemImage: "moon.zzz.fill", color: FuelyColor.sleep)
            HStack(alignment: .firstTextBaseline, spacing: FuelySpacing.xxs) {
                Text(FuelyFormat.sleepScore(score))
                    .font(FuelyFont.hero)
                    .monospacedDigit()
                    .foregroundStyle(score == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(FuelyColor.ocean))
                if score != nil {
                    Text("/ 100").font(FuelyFont.detail).foregroundStyle(.secondary)
                }
            }
            ProgressBar(fraction: Double(score ?? 0) / 100, color: FuelyColor.sleep, height: 8)
            Text(TodayCopy.sleepDetail(score: score, goal: goal))
                .font(FuelyFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fuelyCard(tint: FuelyColor.sleep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TodayCopy.sleepAccessibility(score: score, goal: goal))
    }
}

/// Workout days this Monday–Sunday week vs the goal (K2, K3).
struct WorkoutCard: View {
    var week: WorkoutWeek
    var now: Date
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.xs) {
            CardTitle("Workouts", systemImage: "figure.run", color: FuelyColor.workout)
            HStack(alignment: .firstTextBaseline, spacing: FuelySpacing.xxs) {
                Text(FuelyFormat.workoutDays(week))
                    .font(FuelyFont.hero)
                    .monospacedDigit()
                    .foregroundStyle(FuelyColor.ocean)
                Text("days").font(FuelyFont.detail).foregroundStyle(.secondary)
            }
            SegmentedProgressBar(filled: week.workoutDays, total: week.goal.daysPerWeek,
                                 color: FuelyColor.workout, height: 8)
            Text(TodayCopy.workoutDetail(week, now: now, calendar: calendar))
                .font(FuelyFont.caption)
                .foregroundStyle(.secondary)
            Text(TodayCopy.workoutToday(week, now: now, calendar: calendar))
                .font(FuelyFont.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fuelyCard(tint: FuelyColor.workout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TodayCopy.workoutAccessibility(week, now: now, calendar: calendar))
    }
}

/// Small colored card title with an SF Symbol.
struct CardTitle: View {
    var title: String
    var systemImage: String
    var color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: FuelySpacing.xs) {
            Image(systemName: systemImage).foregroundStyle(color).accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
        }
        .font(FuelyFont.cardTitle)
    }
}

#Preview("Goal cards") {
    let summary = PreviewData.summary(.onTrack)
    ScrollView {
        VStack(spacing: FuelySpacing.s) {
            WaterCard(summary: summary) {}
            HStack(alignment: .top, spacing: FuelySpacing.s) {
                SleepCard(score: summary.sleepScore, goal: summary.sleepGoal)
                WorkoutCard(week: summary.workoutWeek, now: summary.date)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: FuelySpacing.s) {
                SleepCard(score: nil, goal: 80)
                WorkoutCard(week: PreviewData.summary(.overGoal).workoutWeek, now: summary.date)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }
    .fuelyScreenBackground()
    .fontDesign(.rounded)
}

#Preview("Goal cards · dark") {
    let summary = PreviewData.summary(.behindNoSleep)
    ScrollView {
        VStack(spacing: FuelySpacing.s) {
            WaterCard(summary: summary) {}
            HStack(alignment: .top, spacing: FuelySpacing.s) {
                SleepCard(score: summary.sleepScore, goal: summary.sleepGoal)
                WorkoutCard(week: summary.workoutWeek, now: summary.date)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }
    .fuelyScreenBackground()
    .fontDesign(.rounded)
    .preferredColorScheme(.dark)
}
