import BackgroundTasks
import FuelyCore
import Foundation
import OSLog
import UIKit
import UserNotifications
import WidgetKit

/// Best-effort background app refresh (DECISIONS R5). iOS decides if and when it runs, so nothing
/// depends on it: it only gives the reminders and widgets an extra, fresher recompute (e.g. water
/// logged in another app, a workout finished on the Watch). Needs only the Info.plist keys
/// `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes: fetch`, no entitlement, so it
/// works with a free Personal Team (P4).
enum BackgroundRefresh {
    static let identifier = "com.afgaghifari.fuely.refresh"
    /// How soon iOS may run the next one (it usually waits longer).
    static let interval: TimeInterval = 60 * 60

    private static let log = Logger(subsystem: "com.afgaghifari.fuely", category: "BackgroundRefresh")

    /// Asks iOS for the next run (replaces any earlier request with the same identifier).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator, Background App Refresh off, Low Power Mode: fine, the app still works.
            log.notice("Background refresh not scheduled: \(error.localizedDescription)")
        }
    }

    /// The task: resubmits itself, reads HealthKit when the phone is unlocked (else only the store),
    /// reschedules the reminders and reloads the widgets. Stops early when iOS expires the task
    /// (SwiftUI cancels it).
    static func run() async {
        schedule()
        let store: FuelyStore
        do {
            store = try FuelyStore.appGroup()
        } catch {
            log.error("Background refresh: no App Group store")
            return
        }
        let unlocked = await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
        if unlocked, WaterLogService.canUseHealthKit, !Task.isCancelled {
            do {
                try await HealthSync(store: store, healthKit: LiveHealthKitClient()).refresh(now: Date())
            } catch {
                log.notice("Background HealthKit refresh failed: \(error.localizedDescription)")
            }
        }
        guard !Task.isCancelled else { return }
        await ReminderScheduler(store: store).rescheduleQuietly(leadTime: ReminderPlanner.minimumLead)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Shows Fuely's reminders as banners even while Fuely is open, so a reminder that "fired" was
/// really seen (the bookkeeping counts it either way).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
