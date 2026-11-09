import FuelyCore
import SwiftUI

/// One day from the week view: water vs goal, the night's sleep score, workout minutes, and every
/// drink. On today, Fuely's drinks swipe to delete (also from Apple Health); other apps' are
/// read-only (W7). Finished days are final (W7a): no swipe, no ⓘ, no hint.
struct DayDetailView: View {
    var date: Date
    @Environment(AppModel.self) private var model
    @State private var day: HistoryDay?
    @State private var usesHealthData = true
    @State private var loadFailed = false
    /// The time the screen was last checked against (load, midnight, foreground); nil before the
    /// first load. Kept as state so passing midnight re-renders the day as read-only.
    @State private var checkedAt: Date?

    private var calendar: Calendar { model.calendarForDisplay }
    private var now: Date { checkedAt ?? model.currentDate }

    /// Today's drinks can be deleted; any earlier day is read-only (W7a).
    private func isEditable(_ day: HistoryDay) -> Bool {
        DayEditability.isEditable(day: day.date, now: now, calendar: calendar)
    }

    var body: some View {
        List {
            if let day {
                Section {
                    DaySummaryCard(day: day)
                        .detailCardRow()
                }
                drinks(day)
            } else if loadFailed {
                ContentUnavailableView("Couldn't load this day", systemImage: "exclamationmark.triangle")
                    .listRowBackground(Color.clear)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .fuelyScreenBackground()
        .navigationTitle(day.map { HistoryCopy.dayTitle($0, now: now, calendar: calendar) } ?? "")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .onDayChange { Task { await load() } }
    }

    @ViewBuilder
    private func drinks(_ day: HistoryDay) -> some View {
        let isEditable = isEditable(day)
        Section {
            if day.fuelyEntries.isEmpty && day.externalWaterML == 0 {
                Text("No drinks logged this day.")
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            // Newest first, Fuely's and other apps' drinks interleaved by time.
            ForEach((day.fuelyEntries + day.externalEntries).sorted { $0.date > $1.date }) { entry in
                // Past days get no swipe action at all, not a disabled one (W7a).
                if entry.isDeletable && isEditable {
                    DrinkRow(amountML: entry.amountML, title: FuelyFormat.water(entry.amountML), subtitle: nil, date: entry.date)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                        }
                        .accessibilityAction(named: "Delete") { delete(entry) }
                        .listRowBackground(Color.clear)
                } else {
                    DrinkRow(amountML: entry.amountML, title: FuelyFormat.water(entry.amountML),
                             subtitle: entry.isDeletable ? nil : HistoryCopy.externalSubtitle(entry), date: entry.date)
                        .listRowBackground(Color.clear)
                }
            }
            if day.externalEntries.isEmpty && day.externalWaterML > 0 {
                DrinkRow(amountML: day.externalWaterML, title: FuelyFormat.water(day.externalWaterML),
                         subtitle: "Other apps · read-only", date: nil)
                    .listRowBackground(Color.clear)
            }
        } header: {
            HStack(spacing: FuelySpacing.xs) {
                Text("Drinks")
                    .font(FuelyFont.cardTitle)
                    .foregroundStyle(.primary)
                if isEditable && !day.fuelyEntries.isEmpty {
                    DrinksInfoButton()
                }
            }
            .textCase(nil)
            .padding(.top, FuelySpacing.s)
        }
        if !usesHealthData {
            // Stays visible: it explains why other apps' drinks are missing.
            Text("Apple Health couldn't be read, so only drinks saved in Fuely are shown.")
                .font(FuelyFont.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func delete(_ entry: WaterEntry) {
        // The swipe may have started before midnight; the model and service check again.
        guard model.isEditable(day: entry.date) else {
            checkedAt = model.currentDate
            return
        }
        Task {
            await model.delete(entry)
            await load()
        }
    }

    private func load() async {
        checkedAt = model.currentDate
        guard let result = await model.week(containing: date) else {
            loadFailed = day == nil
            return
        }
        loadFailed = false
        day = result.week.day(containing: date, calendar: calendar)
        usesHealthData = result.week.usesHealthData
    }
}

/// Water ring + total, the night's sleep score and workout minutes.
private struct DaySummaryCard: View {
    var day: HistoryDay
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 96
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.m) {
            Text(HistoryCopy.longDate(day.date, calendar: model.calendarForDisplay))
                .font(FuelyFont.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(spacing: FuelySpacing.l) {
                ZStack {
                    ProgressRing(fraction: day.waterFraction, color: FuelyColor.water, lineWidth: 12)
                    Text(FuelyFormat.percent(day.waterFraction))
                        .font(FuelyFont.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(FuelyColor.ocean)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(FuelySpacing.s)
                }
                .frame(width: ringSize, height: ringSize)
                VStack(alignment: .leading, spacing: FuelySpacing.xxs) {
                    CardTitle("Water", systemImage: "drop.fill", color: FuelyColor.water)
                    Text(FuelyFormat.water(day.waterTotalML))
                        .font(FuelyFont.value)
                        .monospacedDigit()
                        .foregroundStyle(FuelyColor.ocean)
                    Text("of \(FuelyFormat.water(day.waterGoalML))" + (day.isWaterGoalMet ? " · Goal reached" : ""))
                        .font(FuelyFont.detail)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water, \(FuelyFormat.waterSpoken(day.waterTotalML)) of \(FuelyFormat.waterSpoken(day.waterGoalML)), \(FuelyFormat.percentValue(day.waterFraction)) percent")
            Divider()
            let goals = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: FuelySpacing.m))
                : AnyLayout(HStackLayout(alignment: .top, spacing: FuelySpacing.m))
            goals {
                VStack(alignment: .leading, spacing: FuelySpacing.xxs) {
                    CardTitle("Sleep", systemImage: "moon.zzz.fill", color: FuelyColor.sleep)
                    Text(FuelyFormat.sleepScore(day.sleepScore))
                        .font(FuelyFont.value)
                        .monospacedDigit()
                        .foregroundStyle(day.sleepScore == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(FuelyColor.ocean))
                    Text(TodayCopy.sleepDetail(score: day.sleepScore, goal: day.sleepGoal))
                        .font(FuelyFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TodayCopy.sleepAccessibility(score: day.sleepScore, goal: day.sleepGoal))
                VStack(alignment: .leading, spacing: FuelySpacing.xxs) {
                    CardTitle("Workouts", systemImage: "figure.run", color: FuelyColor.workout)
                    Text(HistoryCopy.workoutMinutes(day))
                        .font(FuelyFont.value)
                        .monospacedDigit()
                        .foregroundStyle(FuelyColor.ocean)
                    Text(day.isWorkoutDay ? "Workout day ✓" : "Not a workout day")
                        .font(FuelyFont.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .fuelyCard(tint: FuelyColor.water)
    }
}

private extension View {
    func detailCardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: FuelySpacing.xs, leading: FuelySpacing.gutter,
                                      bottom: FuelySpacing.xs, trailing: FuelySpacing.gutter))
    }
}

#Preview("Day detail · yesterday") {
    NavigationStack {
        DayDetailView(date: PreviewData.calendar.date(byAdding: .day, value: -1, to: PreviewData.now) ?? PreviewData.now)
    }
    .environment(PreviewData.model(.onTrack, history: true))
    .fontDesign(.rounded)
}

#Preview("Day detail · today · dark") {
    NavigationStack { DayDetailView(date: PreviewData.now) }
        .environment(PreviewData.model(.onTrack, history: true))
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}
