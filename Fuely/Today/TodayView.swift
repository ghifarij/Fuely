import FuelyCore
import SwiftUI

/// The Today screen (DECISIONS T1, T2): water, sleep and workouts, a motivational line,
/// a sync hint when Health access is off, and today's drinks with swipe to delete (W7).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        @Bindable var model = model
        let summary = model.summary
        List {
            Section {
                TodayHeader(date: summary.date, headline: TodayCopy.headline(for: summary))
                    .cardRow()
                if let hint = model.syncHint {
                    SyncHintBanner(hint: hint, issue: summary.syncIssue ?? model.refreshIssue) {
                        Task { await model.requestHealthAuthorization() }
                    }
                    .cardRow()
                }
                if let error = model.storeError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(FuelyFont.detail)
                        .foregroundStyle(FuelyColor.nudge)
                        .cardRow()
                }
                WaterCard(summary: summary, riseRequestedAt: model.openingRiseRequestedAt,
                          fuelyLogCount: model.fuelyLogCount, onRiseConsumed: model.consumeOpeningRise,
                          claimCelebration: model.claimGoalCelebration) {
                    model.isQuickLogPresented = true
                }
                .cardRow()
                goalCards(summary)
                    .cardRow()
            }
            TodayDrinksSection(entries: model.todayEntries, externalML: summary.externalWaterML) { entry in
                Task { await model.delete(entry) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .fuelyScreenBackground()
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.week) {
                    Label("Week", systemImage: "chart.bar.xaxis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .refreshable { await model.refresh() }
        // Pace moves with the clock (DECISIONS W8): re-derive each minute, no HealthKit reads.
        .task { await model.runMinuteTicks() }
    }

    /// Sleep and workouts side by side; stacked at accessibility text sizes.
    @ViewBuilder
    private func goalCards(_ summary: TodaySummary) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: FuelySpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: FuelySpacing.s))
        layout {
            SleepCard(score: summary.sleepScore, goal: summary.sleepGoal)
            WorkoutCard(week: summary.workoutWeek, now: summary.date)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    /// A list row that shows a card on the screen background (no row chrome).
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: FuelySpacing.xs, leading: FuelySpacing.gutter,
                                      bottom: FuelySpacing.xs, trailing: FuelySpacing.gutter))
    }
}

/// Date and the motivational line (DECISIONS T2).
struct TodayHeader: View {
    var date: Date
    var headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.xxs) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).locale(DisplayLocale.english()))
                .font(FuelyFont.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(FuelyColor.ocean)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Health access off" and other sync problems.
struct SyncHintBanner: View {
    var hint: TodayCopy.SyncHint
    var issue: HealthSyncIssue?
    var onAllowAccess: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the icon column would leave the message a narrow strip.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: FuelySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: FuelySpacing.s))
        layout {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(FuelyColor.nudge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FuelySpacing.xxs) {
                VStack(alignment: .leading, spacing: FuelySpacing.xxs) {
                    Text(hint.title).font(FuelyFont.cardTitle)
                    Text(hint.message).font(FuelyFont.detail).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                if issue == .notAuthorized {
                    allowAccessButton
                }
            }
            Spacer(minLength: 0)
        }
        .fuelyCard(tint: FuelyColor.nudge)
    }

    private var allowAccessButton: some View {
        Button(action: onAllowAccess) {
            Text("Allow Health access")
                .font(FuelyFont.detail.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.borderless)
        .padding(.top, FuelySpacing.xxs)
    }

    private var icon: String {
        switch issue {
        case .locked?: "lock.fill"
        case .notAuthorized?: "heart.slash.fill"
        default: "exclamationmark.icloud.fill"
        }
    }
}

#Preview("Today · on track") {
    NavigationStack { TodayView() }
        .environment(PreviewData.model(.onTrack))
        .fontDesign(.rounded)
}

#Preview("Today · on track · dark") {
    NavigationStack { TodayView() }
        .environment(PreviewData.model(.onTrack))
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}

#Preview("Today · behind, no sleep, access off") {
    NavigationStack { TodayView() }
        .environment(PreviewData.model(.behindNoSleep))
        .fontDesign(.rounded)
}

#Preview("Today · over goal · dark") {
    NavigationStack { TodayView() }
        .environment(PreviewData.model(.overGoal))
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}

#Preview("Today · empty · XXXL") {
    NavigationStack { TodayView() }
        .environment(PreviewData.model(.empty))
        .fontDesign(.rounded)
        .dynamicTypeSize(.accessibility2)
}
