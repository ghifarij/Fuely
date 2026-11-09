import Foundation
import Testing
@testable import FuelyCore

/// An in-memory notification center.
actor FakeNotificationCenter: NotificationScheduling {
    var permissionValue: NotificationPermission = .allowed
    var pending: [String: PlannedReminder] = [:]
    var otherPending: Set<String> = []
    var failingIDs: Set<String> = []

    func setPermission(_ value: NotificationPermission) { permissionValue = value }
    func setOther(_ ids: Set<String>) { otherPending = ids }
    func setFailing(_ ids: Set<String>) { failingIDs = ids }

    func permission() async -> NotificationPermission { permissionValue }
    func pendingRequestIDs() async -> [String] { Array(pending.keys) + Array(otherPending) }
    func removePendingRequests(ids: [String]) async {
        for id in ids {
            pending[id] = nil
            otherPending.remove(id)
        }
    }

    func add(_ reminder: PlannedReminder) async throws {
        if failingIDs.contains(reminder.id) { throw CocoaError(.featureUnsupported) }
        pending[reminder.id] = reminder
    }
}

@Suite struct ReminderSchedulerTests {
    let cal = Calendar.test()
    let store = makeTempStore()
    let center = FakeNotificationCenter()

    var scheduler: ReminderScheduler { ReminderScheduler(store: store, center: center, calendar: cal) }

    init() throws {
        try store.saveSettings(FuelySettings(waterGoalML: 2400, hasCompletedOnboarding: true))
    }

    @Test func schedulesThePlanAndRemembersIt() async throws {
        try store.logWater(amountML: 600, at: cal.at(2026, 11, 12, 6, 30))
        let plan = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        #expect(plan.map(\.kind) == [.workout, .water, .water])
        #expect(Set(await center.pending.keys) == Set(plan.map(\.id)))
        #expect(try store.reminders().scheduled.map(\.id) == plan.map(\.id))
    }

    @Test func replacesOnlyFuelysOwnRequests() async throws {
        await center.setOther(["someone.else"])
        _ = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        // Goal met: water reminders go away, the workout note stays, others are untouched.
        try store.logWater(amountML: 2400, at: cal.at(2026, 11, 12, 7, 5))
        _ = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7, 6), leadTime: ReminderPlanner.minimumLead)
        let ids = Set(await center.pendingRequestIDs())
        #expect(ids == ["someone.else", "fuely.workout.2026-11-12"])
    }

    @Test func remindersThatFiredCountTowardTheDailyLimit() async throws {
        // 07:00 with nothing logged: water at 07:01 and 09:01.
        _ = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        // 09:30, still nothing logged: both fired, so no more water today.
        let plan = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 9, 30), leadTime: ReminderPlanner.minimumLead)
        #expect(!plan.contains { $0.kind == .water })
        #expect(try store.reminders().waterRemindersSent(onDayOf: cal.at(2026, 11, 12, 9, 30), calendar: cal) == 2)
    }

    @Test func aRemovedReminderNeverCounts() async throws {
        _ = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 6), leadTime: ReminderPlanner.minimumLead)
        // A drink moves the water reminders later before any fired.
        try store.logWater(amountML: 1000, at: cal.at(2026, 11, 12, 6, 0))
        _ = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 6, 0), leadTime: ReminderPlanner.minimumLead)
        #expect(try store.reminders().waterRemindersSent(onDayOf: cal.at(2026, 11, 12, 6), calendar: cal) == 0)
    }

    @Test func turningRemindersOffRemovesEverything() async throws {
        _ = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        try store.updateSettings { $0.remindersEnabled = false }
        let plan = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7, 1), leadTime: ReminderPlanner.minimumLead)
        #expect(plan.isEmpty)
        #expect(await center.pending.isEmpty)
        #expect(try store.reminders().scheduled.isEmpty)
    }

    @Test func withoutPermissionNothingIsScheduled() async throws {
        await center.setPermission(.denied)
        let plan = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        #expect(plan.isEmpty)
        #expect(await center.pending.isEmpty)
        #expect(try store.reminders().scheduled.isEmpty)
    }

    @Test func aFailedAddIsNotRemembered() async throws {
        await center.setFailing(["fuely.water.2026-11-12.1"])
        _ = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        let ids = try store.reminders().scheduled.map(\.id)
        #expect(!ids.contains("fuely.water.2026-11-12.1"))
        #expect(ids.contains("fuely.water.2026-11-12.2"))
    }

    @Test func otherAppsWaterFromTheSnapshotCounts() async throws {
        try store.saveHealthSnapshot(HealthSnapshot(refreshedAt: cal.at(2026, 11, 12, 6), externalWaterML: 2400,
                                                    sleepScore: nil, workouts: []))
        let plan = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        #expect(!plan.contains { $0.kind == .water })
    }

    @Test func workoutsFromTheSnapshotCount() async throws {
        // Thu: three workouts already → weekly goal reached, no workout note.
        let workouts = [9, 10, 11].map { day -> WorkoutSample in
            let start = cal.at(2026, 11, day, 6)
            return WorkoutSample(start: start, end: start.addingTimeInterval(.hours(1)), duration: .hours(1))
        }
        try store.saveHealthSnapshot(HealthSnapshot(refreshedAt: cal.at(2026, 11, 12, 6), externalWaterML: 0,
                                                    sleepScore: nil, workouts: workouts))
        let plan = try await scheduler.reschedule(now: cal.at(2026, 11, 12, 7), leadTime: ReminderPlanner.minimumLead)
        #expect(!plan.contains { $0.kind != .water })
    }
}
