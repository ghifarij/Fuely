import FuelyCore
import Foundation
import Observation
import OSLog
import UserNotifications
import WidgetKit

/// The app's single source of UI state. Loads the `TodaySummary` from the App Group store,
/// refreshes from HealthKit on launch and foreground, and routes every water write through
/// `WaterLogService` (store first, then HealthKit; DECISIONS W4). Reloads the widgets and
/// reschedules the reminders (R5) after every refresh and write.
@Observable
@MainActor
final class AppModel {
    let store: FuelyStore
    /// nil in previews, tests and when HealthKit is unavailable.
    private let healthKit: (any HealthKitClient)?
    private let calendar: Calendar
    private let now: () -> Date
    private let reloadsWidgets: Bool
    /// False in previews: no system permission prompts.
    private let asksSystemPermissions: Bool
    /// Schedules the reminder notifications; nil in previews and tests.
    private let notifications: (any NotificationScheduling)?

    private(set) var settings: FuelySettings = .default
    /// The settings were read from the store at least once (so a failed read never shows onboarding
    /// to someone who already finished it).
    private(set) var hasLoadedSettings = false
    private(set) var summary: TodaySummary
    /// Fuely's own entries today, newest first (swipe to delete, DECISIONS W7).
    private(set) var todayEntries: [WaterEntry] = []
    /// What Undo would remove: today's newest Fuely entry.
    private(set) var undoCandidate: WaterEntry?
    private(set) var isRefreshing = false
    /// Why the last HealthKit read failed (e.g. locked); nil after a good refresh.
    private(set) var refreshIssue: HealthSyncIssue?
    /// A store read/write failed; shown as a small error line.
    private(set) var storeError: String?
    /// Requests from outside the Today view (deep links) to show the quick-log sheet.
    var isQuickLogPresented = false
    /// Fuely's write access to Apple Health water (the only permission HealthKit reveals).
    private(set) var healthAccess: HealthAccessStatus = .unavailable
    /// Whether iOS shows Fuely's notifications (Settings → Reminders).
    private(set) var notificationPermission: NotificationPermission = .allowed
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.afgaghifari.fuely", category: "AppModel")

    init(store: FuelyStore, healthKit: (any HealthKitClient)?, calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init, reloadsWidgets: Bool = true, asksSystemPermissions: Bool = true,
         notifications: (any NotificationScheduling)? = nil) {
        self.store = store
        self.healthKit = healthKit
        self.calendar = calendar
        self.now = now
        self.reloadsWidgets = reloadsWidgets
        self.asksSystemPermissions = asksSystemPermissions
        self.notifications = notifications
        self.summary = TodaySummary.make(settings: .default, waterLog: WaterLog(), snapshot: nil,
                                         now: now(), calendar: calendar)
        reload()
        updateHealthAccess()
    }

    /// The live model: App Group store + live HealthKit client (app process only).
    static func live() -> AppModel {
        let store: FuelyStore
        do {
            store = try FuelyStore.appGroup()
        } catch {
            // Without the App Group the widget can't see the data, but the app still works.
            log.error("App Group unavailable, using a local store: \(error.localizedDescription)")
            let support = URL.applicationSupportDirectory.appending(path: "Fuely", directoryHint: .isDirectory)
            store = FuelyStore(directory: support)
        }
        let healthKit: (any HealthKitClient)? = WaterLogService.canUseHealthKit ? LiveHealthKitClient() : nil
        migrateOnboardingFlag(into: store)
        return AppModel(store: store, healthKit: healthKit, notifications: LiveNotificationCenter())
    }

    /// Phase 2A kept the onboarding flag in `UserDefaults`; it now lives in `FuelySettings`.
    private static func migrateOnboardingFlag(into store: FuelyStore) {
        let key = "hasCompletedOnboarding"
        guard UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try store.updateSettings { $0.hasCompletedOnboarding = true }
            UserDefaults.standard.removeObject(forKey: key)
        } catch {
            log.error("Onboarding flag migration failed: \(error.localizedDescription)")
        }
    }

    var currentDate: Date { now() }

    /// Show the first-launch onboarding (DECISIONS O1).
    var needsOnboarding: Bool { hasLoadedSettings && !settings.hasCompletedOnboarding }

    /// Marks onboarding as done (the flag lives in `FuelySettings`).
    func completeOnboarding() {
        updateSettings { $0.hasCompletedOnboarding = true }
    }

    /// Keeps the pace and the day current while the Today screen stays open: re-derives the summary
    /// from the store at the start of every minute. Never touches HealthKit. Runs until cancelled.
    func runMinuteTicks() async {
        while !Task.isCancelled {
            let seconds = 60 - Double(calendar.component(.second, from: Date()))
            do {
                try await Task.sleep(for: .seconds(max(seconds, 1)))
            } catch {
                return
            }
            reload()
        }
    }

    /// The sync problem to show (a failed push wins over a failed read).
    var syncHint: TodayCopy.SyncHint? { TodayCopy.syncHint(summary.syncIssue ?? refreshIssue) }

    // MARK: Loading

    /// Re-reads the stored state (no HealthKit). Cheap; call after any change.
    func reload() {
        let date = now()
        do {
            let settings = try store.settings()
            let waterLog = try store.waterLog()
            self.settings = settings
            hasLoadedSettings = true
            summary = TodaySummary.make(settings: settings, waterLog: waterLog, snapshot: try store.healthSnapshot(),
                                        now: date, calendar: calendar)
            todayEntries = waterLog.entries(onDayOf: date, calendar: calendar).sorted { $0.date > $1.date }
            undoCandidate = waterLog.undoCandidate(now: date, calendar: calendar)
            storeError = nil
        } catch {
            Self.log.error("Store read failed: \(error.localizedDescription)")
            storeError = "Couldn't read your Fuely data."
        }
    }

    /// Pushes queued water to HealthKit and reads sleep, workouts and other apps' water
    /// (HealthSync.refresh). Call on launch and whenever the scene becomes active.
    func refresh() async {
        guard !isRefreshing else { return }
        guard let healthKit else {
            reload()
            reloadWidgets()
            await rescheduleReminders()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await HealthSync(store: store, healthKit: healthKit, calendar: calendar).refresh(now: now())
            refreshIssue = nil
        } catch {
            refreshIssue = HealthSyncIssue(error)
            Self.log.notice("HealthKit refresh failed: \(error.localizedDescription)")
        }
        reload()
        updateHealthAccess()
        reloadWidgets()
        await rescheduleReminders()
    }

    /// Asks for Health access (onboarding and the "Health access off" hint), then refreshes.
    func requestHealthAuthorization() async {
        guard let healthKit else { return }
        do {
            try await healthKit.requestAuthorization()
        } catch {
            Self.log.notice("Health authorization failed: \(error.localizedDescription)")
        }
        updateHealthAccess()
        await refresh()
    }

    private func updateHealthAccess() {
        healthAccess = healthKit?.waterWriteAccess() ?? .unavailable
    }

    /// Asks for permission to send reminders (onboarding O1, Settings), then schedules them.
    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        guard asksSystemPermissions else { return false }
        var granted = false
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.notice("Notification authorization failed: \(error.localizedDescription)")
        }
        await rescheduleReminders()
        return granted
    }

    // MARK: Reminders (DECISIONS R1, R1b, R2–R5)

    /// Re-reads the notification permission and replaces Fuely's pending reminders with a fresh plan
    /// from the store. Called after every refresh, water change and settings change.
    /// Re-reads whether iOS shows Fuely's notifications (Settings opens, returns from iOS Settings).
    func refreshNotificationPermission() async {
        guard let notifications else { return }
        notificationPermission = await notifications.permission()
    }

    /// Runs one at a time, in call order, so a quick off→on never ends with the older plan applied last.
    func rescheduleReminders() async {
        guard let notifications else { return }
        let previous = rescheduleTask
        let task = Task { @MainActor in
            await previous?.value
            notificationPermission = await notifications.permission()
            await ReminderScheduler(store: store, center: notifications, calendar: calendar)
                .rescheduleQuietly(now: now(), leadTime: ReminderPlanner.leadAfterActivity)
        }
        rescheduleTask = task
        await task.value
    }

    // MARK: Water

    private var waterService: WaterLogService {
        WaterLogService(store: store, healthKit: healthKit, calendar: calendar)
    }

    /// Logs a drink (quick-log buttons or custom amount). Returns the entry, nil on failure.
    @discardableResult
    func logWater(amountML: Int) async -> WaterEntry? {
        do {
            let (entry, _) = try await waterService.log(amountML: amountML, at: now())
            reload()
            reloadWidgets()
            await rescheduleReminders()
            return entry
        } catch {
            Self.log.error("Log water failed: \(error.localizedDescription)")
            storeError = "Couldn't save that drink. Please try again."
            return nil
        }
    }

    /// Undo: removes today's newest Fuely entry (DECISIONS W7).
    func undoLatest() async {
        guard let entry = undoCandidate else { return }
        await delete(entry)
    }

    /// Deletes a Fuely entry and its HealthKit sample, from Today or today's day detail (the entry
    /// may exist only in HealthKit). Other apps' entries and finished days are read-only (W7, W7a).
    func delete(_ entry: WaterEntry) async {
        guard entry.isDeletable, isEditable(day: entry.date) else { return }
        do {
            try await waterService.delete(entry, at: now())
        } catch {
            Self.log.error("Delete failed: \(error.localizedDescription)")
            storeError = "Couldn't delete that drink. Please try again."
        }
        reload()
        reloadWidgets()
        await rescheduleReminders()
    }

    // MARK: History

    /// The Monday–Sunday week containing `date` (DECISIONS T3, K2): HealthKit when it can be read,
    /// otherwise the stored data. nil only when the store can't be read.
    func week(containing date: Date) async -> (week: WeekHistory, issue: HealthSyncIssue?)? {
        let loader = WeekHistoryLoader(store: store, healthKit: healthKit, calendar: calendar)
        do {
            return try await loader.load(weekContaining: date, now: now())
        } catch {
            Self.log.error("Week load failed: \(error.localizedDescription)")
            return nil
        }
    }

    var calendarForDisplay: Calendar { calendar }

    /// Whether drinks on `day` can still be deleted: today only, checked against the current time on
    /// every call (W7a).
    func isEditable(day: Date) -> Bool {
        DayEditability.isEditable(day: day, now: now(), calendar: calendar)
    }

    // MARK: Settings (Settings and Onboarding write through here)

    /// Writes the settings (clamped to `SettingsLimits`), then reloads the Today state and the widgets.
    func updateSettings(_ body: (inout FuelySettings) -> Void) {
        do {
            try store.updateSettings { settings in
                body(&settings)
                settings = settings.sanitized()
            }
        } catch {
            Self.log.error("Settings write failed: \(error.localizedDescription)")
            storeError = "Couldn't save your settings."
        }
        reload()
        reloadWidgets()
        Task { await rescheduleReminders() }
    }

    // MARK: Deep links

    func handle(_ url: URL) {
        switch FuelyDeepLink(url: url) {
        case .quickLog?: isQuickLogPresented = true
        case .today?, nil: break
        }
    }

    private func reloadWidgets() {
        guard reloadsWidgets else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
