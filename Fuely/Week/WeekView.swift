import FuelyCore
import SwiftUI

/// The week view (DECISIONS T3, K2): a Monday–Sunday week of daily water %, the sleep score per
/// night and workout days. Earlier weeks are a tap away; each day opens its detail (today's drinks
/// swipe to delete, W7; earlier days are read-only, W7a). No monthly charts.
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 0 = this week, -1 = last week, …
    @State private var weekOffset = 0
    @State private var week: WeekHistory?
    @State private var issue: HealthSyncIssue?
    @State private var loadFailed = false

    /// How far back the week switcher goes.
    static let maxWeeksBack = 12

    private var calendar: Calendar { model.calendarForDisplay }
    private var now: Date { model.currentDate }

    var body: some View {
        ScrollView {
            VStack(spacing: FuelySpacing.s) {
                weekSwitcher
                if let week {
                    if let note = dataNote(week) {
                        Label(note, systemImage: "info.circle")
                            .font(FuelyFont.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, FuelySpacing.xxs)
                    }
                    WaterWeekCard(week: week, calendar: calendar, now: now)
                    summaryCards(week)
                    DayList(week: week, calendar: calendar, now: now)
                } else if loadFailed {
                    ContentUnavailableView("Couldn't load this week", systemImage: "exclamationmark.triangle",
                                           description: Text("Please try again."))
                } else {
                    ProgressView().padding(.top, FuelySpacing.xl)
                }
            }
            .padding(.horizontal, FuelySpacing.gutter)
            .padding(.bottom, FuelySpacing.l)
        }
        .fuelyScreenBackground()
        .navigationTitle("Week")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: HistoryDayRoute.self) { DayDetailView(date: $0.date) }
        .task(id: weekOffset) { await load() }
        .refreshable { await load() }
        // Past midnight "Today" moves on and the day before becomes a finished day (W7a).
        .onDayChange { Task { await load() } }
    }

    private var weekSwitcher: some View {
        HStack {
            Button {
                weekOffset -= 1
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(weekOffset <= -Self.maxWeeksBack)
            .accessibilityLabel("Previous week")

            VStack(spacing: 2) {
                Text(week.map { HistoryCopy.weekTitle($0, now: now, calendar: calendar) } ?? " ")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(FuelyColor.ocean)
                Text(week.map { HistoryCopy.weekRange($0, calendar: calendar) } ?? " ")
                    .font(FuelyFont.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Button {
                weekOffset += 1
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(weekOffset >= 0)
            .accessibilityLabel("Next week")
        }
        .font(.body.weight(.semibold))
        .tint(FuelyColor.ocean)
    }

    @ViewBuilder
    private func summaryCards(_ week: WeekHistory) -> some View {
        // Side by side, the card titles break mid-word at accessibility sizes: stack them instead.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: FuelySpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: FuelySpacing.s))
        layout {
            VStack(alignment: .leading, spacing: FuelySpacing.xs) {
                CardTitle("Sleep", systemImage: "moon.zzz.fill", color: FuelyColor.sleep)
                Text(FuelyFormat.sleepScore(week.averageSleepScore))
                    .font(FuelyFont.hero)
                    .monospacedDigit()
                    .foregroundStyle(week.averageSleepScore == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(FuelyColor.ocean))
                Text(HistoryCopy.sleepSummary(week))
                    .font(FuelyFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .fuelyCard(tint: FuelyColor.sleep)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: FuelySpacing.xs) {
                CardTitle("Workouts", systemImage: "figure.run", color: FuelyColor.workout)
                Text(FuelyFormat.workoutDays(week.workoutWeek))
                    .font(FuelyFont.hero)
                    .monospacedDigit()
                    .foregroundStyle(FuelyColor.ocean)
                SegmentedProgressBar(filled: week.workoutWeek.workoutDays, total: week.workoutWeek.goal.daysPerWeek,
                                     color: FuelyColor.workout, height: 8)
                Text(week.workoutWeek.isGoalReached ? "Weekly goal reached"
                     : "\(week.workoutWeek.goal.minMinutesPerDay)+ min counts as a day")
                    .font(FuelyFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .fuelyCard(tint: FuelyColor.workout)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Workouts, \(HistoryCopy.workoutSummary(week))")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dataNote(_ week: WeekHistory) -> String? {
        guard !week.usesHealthData else { return nil }
        if let hint = TodayCopy.syncHint(issue) {
            return "\(hint.title). Showing drinks saved in Fuely and today's cached sleep and workouts."
        }
        return "Showing drinks saved in Fuely. Connect Apple Health for sleep, workouts and other apps' water."
    }

    private func load() async {
        let date = calendar.date(byAdding: .day, value: 7 * weekOffset, to: now) ?? now
        guard let result = await model.week(containing: date) else {
            loadFailed = week == nil
            return
        }
        loadFailed = false
        week = result.week
        issue = result.issue
    }
}

/// Opens a day's detail from the week view.
struct HistoryDayRoute: Hashable {
    var date: Date
}

/// Daily water % as bars, with the 100% goal line. Bars past 100% fill to the top (W3); the
/// percentage carries the rest.
private struct WaterWeekCard: View {
    var week: WeekHistory
    var calendar: Calendar
    var now: Date
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 120
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.s) {
            let header = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: FuelySpacing.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            header {
                CardTitle("Water", systemImage: "drop.fill", color: FuelyColor.water)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text(HistoryCopy.waterSummary(week))
                    .font(FuelyFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: FuelySpacing.xs) {
                ForEach(week.days) { day in
                    NavigationLink(value: HistoryDayRoute(date: day.date)) {
                        WaterBar(day: day, label: HistoryCopy.weekdayInitial(day.date, calendar: calendar),
                                 height: chartHeight)
                    }
                    .buttonStyle(.plain)
                    .disabled(day.isFuture)
                    .accessibilityLabel(HistoryCopy.dayAccessibility(day, now: now, calendar: calendar))
                    .accessibilityHint(day.isFuture ? "" : "Shows the day's drinks")
                }
            }
        }
        .fuelyCard(tint: FuelyColor.water)
    }
}

private struct WaterBar: View {
    var day: HistoryDay
    var label: String
    var height: CGFloat
    @ScaledMetric(relativeTo: .body) private var barWidth: CGFloat = 20

    var body: some View {
        VStack(spacing: FuelySpacing.xxs) {
            Text(day.isFuture ? " " : "\(FuelyFormat.percentValue(day.waterFraction))")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(day.isWaterGoalMet ? AnyShapeStyle(FuelyColor.ocean) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ZStack(alignment: .bottom) {
                Capsule().fill(FuelyColor.track)
                Capsule()
                    .fill(FuelyColor.water.gradient)
                    .frame(height: day.isFuture ? 0 : max(height * min(day.waterFraction, 1), day.waterTotalML > 0 ? barWidth : 0))
            }
            .frame(width: barWidth, height: height)
            .overlay(alignment: .top) {
                if day.isWaterGoalMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.top, 6)
                }
            }
            Text(label)
                .font(FuelyFont.caption)
                .foregroundStyle(day.isToday ? AnyShapeStyle(FuelyColor.ocean) : AnyShapeStyle(.secondary))
                .fontWeight(day.isToday ? .bold : .medium)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .opacity(day.isFuture ? 0.45 : 1)
    }
}

/// One row per day: water, sleep score and workout minutes. Opens the day detail.
private struct DayList: View {
    var week: WeekHistory
    var calendar: Calendar
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Days")
                .font(FuelyFont.cardTitle)
                .padding(.bottom, FuelySpacing.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(week.elapsedDays.reversed().enumerated()), id: \.element.id) { index, day in
                if index > 0 { Divider() }
                NavigationLink(value: HistoryDayRoute(date: day.date)) {
                    DayRow(day: day, title: HistoryCopy.dayTitle(day, now: now, calendar: calendar),
                           subtitle: HistoryCopy.shortDate(day.date, calendar: calendar))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HistoryCopy.dayAccessibility(day, now: now, calendar: calendar))
                .accessibilityHint("Shows the day's drinks")
                .accessibilityAddTraits(.isButton)
            }
        }
        .fuelyCard()
    }
}

private struct DayRow: View {
    var day: HistoryDay
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: FuelySpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FuelyFont.body.weight(.semibold))
                Text(subtitle).font(FuelyFont.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: FuelySpacing.xs)
            metric(icon: "drop.fill", color: FuelyColor.water, text: FuelyFormat.percent(day.waterFraction))
            metric(icon: "moon.zzz.fill", color: FuelyColor.sleep, text: FuelyFormat.sleepScore(day.sleepScore))
            metric(icon: day.isWorkoutDay ? "checkmark.circle.fill" : "figure.run",
                   color: FuelyColor.workout, text: day.isWorkoutDay ? "Yes" : "—")
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, FuelySpacing.s)
        .contentShape(Rectangle())
    }

    private func metric(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(text).font(FuelyFont.detail).monospacedDigit()
        }
        .frame(minWidth: 52, alignment: .leading)
    }
}

#Preview("Week") {
    NavigationStack { WeekView() }
        .environment(PreviewData.model(.onTrack, history: true))
        .fontDesign(.rounded)
}

#Preview("Week · dark") {
    NavigationStack { WeekView() }
        .environment(PreviewData.model(.onTrack, history: true))
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}

#Preview("Week · no Health") {
    NavigationStack { WeekView() }
        .environment(PreviewData.model(.behindNoSleep))
        .fontDesign(.rounded)
}
