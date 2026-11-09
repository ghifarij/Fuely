import FuelyCore
import Foundation
import WidgetKit

/// One moment of every Fuely widget: the Today summary recomputed for `date` from the App Group
/// store (never HealthKit, DECISIONS W4), plus the settings the (+) button needs (W6a).
struct FuelyEntry: TimelineEntry {
    let date: Date
    let summary: TodaySummary
    let settings: FuelySettings
    /// What Fuely Circle shows (G4); the other widgets ignore it.
    var metric: WidgetMetric = .water
    /// The open amount picker (W6b), only while it is active at `date`; nil = Idle.
    var draft: WaterDraft? = nil
}

/// Builds timelines from the App Group store. Each entry recomputes pace and day rollover for its
/// own date (see `WidgetTimelinePlan`), so the widget stays current without HealthKit.
enum FuelyTimelineLoader {
    /// Retry soon when the store can't be read (e.g. first unlock not yet happened).
    static let retryInterval: TimeInterval = 15 * 60

    static func timeline(now: Date = .now, calendar: Calendar = .current,
                         metric: WidgetMetric = .water) -> Timeline<FuelyEntry> {
        guard let state = State.load() else {
            let entry = FuelyEntry(date: now, summary: State.empty.summary(at: now, calendar: calendar),
                                   settings: .default, metric: metric)
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(retryInterval)))
        }
        // An open picker gets an extra entry at its expiry, which draws Idle again (W6b).
        let draft = WaterDraft.active(state.draft, at: now)
        let dates = WidgetTimelinePlan.entryDates(from: now, window: state.settings.drinkingWindow, calendar: calendar,
                                                  draftExpiry: draft?.expiresAt)
        let entries = dates.map {
            FuelyEntry(date: $0, summary: state.summary(at: $0, calendar: calendar), settings: state.settings, metric: metric,
                       draft: WaterDraft.active(draft, at: $0))
        }
        // Reload after the last entry (next midnight); the app and the (+) intent also reload on writes.
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// The current entry (widget gallery / transient snapshot).
    static func entry(now: Date = .now, calendar: Calendar = .current, metric: WidgetMetric = .water) -> FuelyEntry {
        let state = State.load() ?? .empty
        return FuelyEntry(date: now, summary: state.summary(at: now, calendar: calendar), settings: state.settings, metric: metric,
                          draft: WaterDraft.active(state.draft, at: now))
    }

    private struct State {
        let settings: FuelySettings
        let waterLog: WaterLog
        let snapshot: HealthSnapshot?
        let draft: WaterDraft?

        static let empty = State(settings: .default, waterLog: WaterLog(), snapshot: nil, draft: nil)

        static func load() -> State? {
            do {
                let store = try FuelyStore.appGroup()
                // An unreadable draft just means Idle; it must never hide the water total.
                return State(settings: try store.settings(), waterLog: try store.waterLog(), snapshot: try store.healthSnapshot(),
                             draft: try? store.waterDraft())
            } catch {
                return nil
            }
        }

        func summary(at date: Date, calendar: Calendar) -> TodaySummary {
            TodaySummary.make(settings: settings, waterLog: waterLog, snapshot: snapshot, now: date, calendar: calendar)
        }
    }
}

/// Timelines for the widgets without configuration (Text, Line, Rings, Home Screen).
struct FuelyProvider: TimelineProvider {
    func placeholder(in context: Context) -> FuelyEntry {
        WidgetSamples.entry(.onTrack)
    }

    func getSnapshot(in context: Context, completion: @escaping (FuelyEntry) -> Void) {
        completion(context.isPreview ? WidgetSamples.entry(.onTrack) : FuelyTimelineLoader.entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FuelyEntry>) -> Void) {
        completion(FuelyTimelineLoader.timeline())
    }
}

/// Timelines for Fuely Circle, whose metric is picked by the user (G4).
struct FuelyCircleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FuelyEntry {
        WidgetSamples.entry(.onTrack)
    }

    func snapshot(for configuration: FuelyCircleConfiguration, in context: Context) async -> FuelyEntry {
        if context.isPreview { return WidgetSamples.entry(.onTrack, metric: configuration.metric.metric) }
        return FuelyTimelineLoader.entry(metric: configuration.metric.metric)
    }

    func timeline(for configuration: FuelyCircleConfiguration, in context: Context) async -> Timeline<FuelyEntry> {
        FuelyTimelineLoader.timeline(metric: configuration.metric.metric)
    }
}
