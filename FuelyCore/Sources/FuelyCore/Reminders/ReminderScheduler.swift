import Foundation
import OSLog
import UserNotifications

/// Whether iOS will show Fuely's notifications.
public enum NotificationPermission: Sendable, Hashable {
    case allowed, denied, notDetermined
}

/// The slice of `UNUserNotificationCenter` Fuely uses, so the scheduling can be tested.
public protocol NotificationScheduling: Sendable {
    func permission() async -> NotificationPermission
    /// Every pending request id (Fuely's and, in theory, anyone else's in this app).
    func pendingRequestIDs() async -> [String]
    func removePendingRequests(ids: [String]) async
    /// Adds or replaces (same id) a request.
    func add(_ reminder: PlannedReminder) async throws
}

/// The real notification center. Works in the app and in the widget extension (local
/// notifications need no entitlement, so this fits a free Personal Team, P4/P5).
public struct LiveNotificationCenter: NotificationScheduling {
    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    public func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .notDetermined: .notDetermined
        case .denied: .denied
        @unknown default: .denied
        }
    }

    public func pendingRequestIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func removePendingRequests(ids: [String]) async {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func add(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.threadIdentifier = reminder.kind == .water ? "fuely.water" : "fuely.workout"
        content.sound = reminder.isQuiet ? nil : .default
        content.interruptionLevel = reminder.isQuiet ? .passive : .active
        // An absolute interval, so a time zone change can't move it and "fire date passed = sent"
        // (ReminderBookkeeping) stays exact.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(reminder.fireDate.timeIntervalSinceNow, 1),
                                                        repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }
}

/// Applies `ReminderPlanner` (DECISIONS R5): counts what already fired, plans from the App Group
/// store (water log + HealthKit snapshot; no HealthKit, so it also runs in the widget extension
/// and while the phone is locked) and replaces Fuely's pending requests with the plan.
///
/// Two processes (app and widget) may reschedule at the same moment. The bookkeeping update is
/// atomic (coordinated file write); the notification center calls are not, but every run computes
/// the same ids from the same stored state, so the last one wins with a consistent set.
public struct ReminderScheduler: Sendable {
    public let store: FuelyStore
    public let center: any NotificationScheduling
    public let calendar: Calendar

    private static let log = Logger(subsystem: "com.afgaghifari.fuely", category: "Reminders")

    public init(store: FuelyStore, center: any NotificationScheduling = LiveNotificationCenter(),
                calendar: Calendar = .current) {
        self.store = store
        self.center = center
        self.calendar = calendar
    }

    /// The scheduler on the App Group store and the real notification center.
    public static func appGroup() throws -> ReminderScheduler {
        ReminderScheduler(store: try FuelyStore.appGroup())
    }

    /// Recomputes and replaces Fuely's pending reminders. Returns what is now pending.
    /// - Parameter leadTime: `ReminderPlanner.leadAfterActivity` after a user action,
    ///   `ReminderPlanner.minimumLead` from the background.
    @discardableResult
    public func reschedule(now: Date = Date(), leadTime: TimeInterval = ReminderPlanner.leadAfterActivity)
        async throws -> [PlannedReminder] {
        let allowed = await center.permission() == .allowed
        let settings = try store.settings()
        let snapshot = try store.healthSnapshot()
        let summary = TodaySummary.make(settings: settings, waterLog: try store.waterLog(), snapshot: snapshot,
                                        now: now, calendar: calendar)
        let plan = try store.updateReminders { book -> [PlannedReminder] in
            book.markDelivered(asOf: now, calendar: calendar)
            let plan = allowed
                ? ReminderPlanner.plan(settings: settings, todayTotalML: summary.water.totalML,
                                       workouts: snapshot?.workouts ?? [], bookkeeping: book, now: now,
                                       leadTime: leadTime, calendar: calendar)
                : []
            book.setScheduled(plan.map(\.scheduled))
            return plan
        }

        let planned = Set(plan.map(\.id))
        let stale = await center.pendingRequestIDs().filter { ReminderPlanner.isFuelyID($0) && !planned.contains($0) }
        await center.removePendingRequests(ids: stale)

        var failed: Set<String> = []
        for reminder in plan {
            do {
                try await center.add(reminder)
            } catch {
                failed.insert(reminder.id)
                Self.log.error("Couldn't schedule \(reminder.id, privacy: .public): \(error.localizedDescription)")
            }
        }
        guard !failed.isEmpty else { return plan }
        // Never count a request iOS didn't take.
        try store.updateReminders { book in book.setScheduled(book.scheduled.filter { !failed.contains($0.id) }) }
        return plan.filter { !failed.contains($0.id) }
    }

    /// `reschedule` that only logs failures: for call sites where reminders are a side effect.
    public func rescheduleQuietly(now: Date = Date(), leadTime: TimeInterval = ReminderPlanner.leadAfterActivity) async {
        do {
            try await reschedule(now: now, leadTime: leadTime)
        } catch {
            Self.log.error("Reschedule failed: \(error.localizedDescription)")
        }
    }
}
