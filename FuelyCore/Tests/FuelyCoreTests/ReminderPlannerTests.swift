import Foundation
import Testing
@testable import FuelyCore

/// Water side of the reminder plan (DECISIONS R1, R1a, R5, R5b, W8). Nov 9 2026 is a Monday.
@Suite struct WaterReminderPlanTests {
    let cal = Calendar.test()
    let settings = FuelySettings(waterGoalML: 2400) // window 05:00–22:00 = 17 h

    func plan(_ hour: Int, _ minute: Int = 0, total: Int, book: ReminderBookkeeping = ReminderBookkeeping(),
              settings: FuelySettings? = nil, lead: TimeInterval = ReminderPlanner.minimumLead,
              calendar: Calendar? = nil, day: (Int, Int, Int) = (2026, 11, 9)) -> [PlannedReminder] {
        let cal = calendar ?? self.cal
        return ReminderPlanner.water(settings: settings ?? self.settings, todayTotalML: total, bookkeeping: book,
                                     now: cal.at(day.0, day.1, day.2, hour, minute), leadTime: lead, calendar: cal)
    }

    func shortfall(total: Int, at date: Date, goal: Int = 2400, window: DrinkingWindow = .default) -> Double {
        WaterPace.expectedIntakeML(goalML: goal, window: window, at: date, calendar: cal) - Double(total)
    }

    @Test func twoRemindersTwoHoursApartFromTheMomentTheShortfallReaches250() {
        // (600 + 250) / 2400 of 17 h = 6 h 01 min 15 s → 11:01:15.
        let reminders = plan(7, total: 600)
        #expect(reminders.map(\.fireDate) == [cal.at(2026, 11, 9, 11, 1, 15), cal.at(2026, 11, 9, 13, 1, 15)])
        #expect(reminders.map(\.id) == ["fuely.water.2026-11-09.1", "fuely.water.2026-11-09.2"])
        #expect(reminders.allSatisfy { $0.kind == .water && !$0.isQuiet })
    }

    @Test func everyPlannedWaterReminderFiresAtLeast250BehindInsideTheWindow() {
        for total in [0, 600, 1200, 2000] {
            for (hour, minute) in [(3, 0), (5, 0), (7, 0), (12, 30), (18, 0)] {
                for reminder in plan(hour, minute, total: total, lead: ReminderPlanner.leadAfterActivity) {
                    #expect(shortfall(total: total, at: reminder.fireDate) >= Double(ReminderPlanner.minimumShortfallML))
                    #expect(DrinkingWindow.default.contains(reminder.fireDate, calendar: cal))
                }
            }
        }
    }

    @Test func merelyBehindIsNotEnough() {
        // 600 ml: behind from 09:15 but only 250 ml behind at 11:01:15; nothing before that.
        #expect(shortfall(total: 600, at: cal.at(2026, 11, 9, 11)) < 250)
        let reminders = plan(9, 30, total: 600)
        #expect(reminders.first?.fireDate == cal.at(2026, 11, 9, 11, 1, 15))
    }

    @Test func alreadyFarEnoughBehindWaitsForTheLeadTime() {
        let reminders = plan(12, total: 600, lead: ReminderPlanner.leadAfterActivity)
        #expect(reminders.map(\.fireDate) == [cal.at(2026, 11, 9, 12, 30), cal.at(2026, 11, 9, 14, 30)])
    }

    @Test func leadTimeNeverPullsAReminderEarlier() {
        // 250 ml behind from 11:01:15 anyway; a 30 min lead from 07:00 changes nothing.
        let reminders = plan(7, total: 600, lead: ReminderPlanner.leadAfterActivity)
        #expect(reminders.first?.fireDate == cal.at(2026, 11, 9, 11, 1, 15))
    }

    @Test func leadTimeIsAtLeastOneMinute() {
        let reminders = plan(12, total: 600, lead: 0)
        #expect(reminders.first?.fireDate == cal.at(2026, 11, 9, 12, 1))
    }

    @Test func keepsTwoHoursAfterTheLastReminderSent() {
        var book = ReminderBookkeeping()
        book.recordWaterReminder(at: cal.at(2026, 11, 9, 11, 30), calendar: cal)
        let reminders = plan(12, total: 600, book: book)
        #expect(reminders.map(\.fireDate) == [cal.at(2026, 11, 9, 13, 30)])
        #expect(reminders.map(\.id) == ["fuely.water.2026-11-09.2"])
    }

    @Test func nothingOnceBothRemindersWentOut() {
        var book = ReminderBookkeeping()
        book.recordWaterReminder(at: cal.at(2026, 11, 9, 9), calendar: cal)
        book.recordWaterReminder(at: cal.at(2026, 11, 9, 11), calendar: cal)
        #expect(plan(14, total: 600, book: book).isEmpty)
    }

    @Test func yesterdaysRemindersDontCountToday() {
        var book = ReminderBookkeeping()
        book.recordWaterReminder(at: cal.at(2026, 11, 8, 15), calendar: cal)
        book.recordWaterReminder(at: cal.at(2026, 11, 8, 18), calendar: cal)
        #expect(plan(7, total: 600, book: book).count == 2)
    }

    @Test func nothingWhenTheGoalIsMet() {
        #expect(plan(7, total: 2400).isEmpty)
        #expect(plan(7, total: 3000).isEmpty)
        var zeroGoal = settings
        zeroGoal.waterGoalML = 0
        #expect(plan(7, total: 0, settings: zeroGoal).isEmpty)
    }

    @Test func nothingLoggedAtWindowOpenWaitsUntil250Behind() {
        // No 05:01 reminder (R5b): 250 / 2400 of 17 h = 1 h 46 min 15 s → 06:46:15.
        let reminders = plan(3, total: 0, lead: ReminderPlanner.leadAfterActivity)
        #expect(reminders.map(\.fireDate) == [cal.at(2026, 11, 9, 6, 46, 15), cal.at(2026, 11, 9, 8, 46, 15)])
        #expect(plan(5, total: 0).first?.fireDate == cal.at(2026, 11, 9, 6, 46, 15))
    }

    @Test func lessThan250LeftToDrinkPlansNothing() {
        // The pace never gets 250 ml ahead of the total before the window closes.
        #expect(plan(7, total: 2200).isEmpty)
        #expect(plan(7, total: 2151).isEmpty)
        // Exactly 250 left: only at the window end (exclusive), so nothing either.
        #expect(plan(7, total: 2150).isEmpty)
        #expect(plan(7, total: 2149).count == 1) // just before 22:00
    }

    @Test func aGoalBelow250NeverReminds() {
        var small = settings
        small.waterGoalML = 200
        #expect(plan(3, total: 0, settings: small).isEmpty)
        #expect(plan(21, total: 0, settings: small).isEmpty)
        small.waterGoalML = ReminderPlanner.minimumShortfallML
        #expect(plan(3, total: 0, settings: small).isEmpty)
    }

    @Test func nothingAtOrAfterTheWindowEnd() {
        // 20:30, nothing logged: the first fits, the second (22:31) would be outside the window.
        #expect(plan(20, 30, total: 0).map(\.fireDate) == [cal.at(2026, 11, 9, 20, 31)])
        #expect(plan(21, 59, total: 0).isEmpty) // 22:00 is the end (exclusive)
        #expect(plan(22, total: 0).isEmpty)
        #expect(plan(23, 30, total: 0).isEmpty)
    }

    @Test func respectsTheToggleAndAnInvalidWindow() {
        var off = settings
        off.remindersEnabled = false
        #expect(plan(10, total: 0, settings: off).isEmpty)
        var invalid = settings
        invalid.drinkingWindow = DrinkingWindow(start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 5))
        #expect(plan(10, total: 0, settings: invalid).isEmpty)
    }

    @Test func copyCarriesTheTotalAndTheGoal() {
        let reminders = plan(15, total: 1200, lead: ReminderPlanner.minimumLead)
        #expect(reminders.first?.body.contains("1.2 L of 2.4 L") == true)
    }

    @Test func springForwardKeepsRealTwoHourSpacing() {
        // New York jumps 02:00 → 03:00 on Mar 8 2026. Window 01:00–06:00 is 4 real hours.
        let ny = Calendar.test("America/New_York")
        var s = settings
        s.waterGoalML = 1000
        s.drinkingWindow = DrinkingWindow(start: TimeOfDay(hour: 1), end: TimeOfDay(hour: 6))
        let reminders = plan(0, 30, total: 0, settings: s, calendar: ny, day: (2026, 3, 8))
        #expect(reminders.count == 2)
        // 250 / 1000 of 4 real hours = 1 h after 01:00 EST → 03:00 EDT.
        #expect(reminders.first?.fireDate == ny.at(2026, 3, 8, 3, 0))
        #expect(reminders[1].fireDate.timeIntervalSince(reminders[0].fireDate) == .hours(2))
        #expect(ny.component(.hour, from: reminders[1].fireDate) == 5) // 03:00 EDT + 2 h = 05:00 EDT
        #expect(reminders.allSatisfy { $0.id.hasPrefix("fuely.water.2026-03-08.") })
    }

    @Test func fallBackKeepsRealTwoHourSpacing() {
        // New York repeats 01:00–02:00 on Nov 1 2026. Window 00:30–03:00 is 3.5 real hours.
        let ny = Calendar.test("America/New_York")
        var s = settings
        s.waterGoalML = 1000
        s.drinkingWindow = DrinkingWindow(start: TimeOfDay(hour: 0, minute: 30), end: TimeOfDay(hour: 3))
        let reminders = plan(0, 0, total: 0, settings: s, calendar: ny, day: (2026, 11, 1))
        #expect(reminders.count == 2)
        // 250 / 1000 of 3.5 real hours = 52.5 min after 00:30 → 01:22:30 (first pass, EDT).
        let start = s.drinkingWindow.interval(on: ny.at(2026, 11, 1, 12), calendar: ny)!.start
        #expect(reminders.first?.fireDate == start.addingTimeInterval(.minutes(52.5)))
        #expect(reminders[1].fireDate.timeIntervalSince(reminders[0].fireDate) == .hours(2))
        let end = s.drinkingWindow.interval(on: reminders[0].fireDate, calendar: ny)!.end
        #expect(reminders[1].fireDate < end)
    }
}

/// Workout side of the reminder plan (DECISIONS R2–R4, R3a, R5). Week of Mon Nov 9 – Sun Nov 15 2026.
@Suite struct WorkoutReminderPlanTests {
    let cal = Calendar.test()
    let settings = FuelySettings(workoutGoal: WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: 3),
                                 workoutReminderTime: TimeOfDay(hour: 8))

    func workout(day: Int, hour: Int = 6, minutes: Double = 60) -> WorkoutSample {
        let start = cal.at(2026, 11, day, hour)
        return WorkoutSample(start: start, end: start.addingTimeInterval(.minutes(minutes)), duration: .minutes(minutes))
    }

    func plan(day: Int, _ hour: Int, _ minute: Int = 0, samples: [WorkoutSample] = [],
              book: ReminderBookkeeping = ReminderBookkeeping(), settings: FuelySettings? = nil) -> PlannedReminder? {
        ReminderPlanner.workout(settings: settings ?? self.settings, workouts: samples, bookkeeping: book,
                                now: cal.at(2026, 11, day, hour, minute), calendar: cal)
    }

    @Test func slackOneNudgesAtTodaysReminderTime() throws {
        let note = try #require(plan(day: 12, 7)) // Thu: 4 days left, 3 to go
        #expect(note.fireDate == cal.at(2026, 11, 12, 8))
        #expect(note.id == "fuely.workout.2026-11-12")
        #expect(note.kind == .workout)
        #expect(note.body.hasPrefix("3 workouts to go, 4 days left this week."))
    }

    @Test func afterTodaysTimeItPlansTomorrowsNote() throws {
        let note = try #require(plan(day: 12, 9)) // → Fri: 3 days left, 3 to go, slack 0
        #expect(note.fireDate == cal.at(2026, 11, 13, 8))
        #expect(note.id == "fuely.workout.2026-11-13")
        #expect(note.title == "Today's a workout day")
    }

    @Test func plentyOfSlackPlansNothing() {
        #expect(plan(day: 9, 7) == nil)  // Mon: slack 4
        #expect(plan(day: 11, 7) == nil) // Wed: slack 2
    }

    @Test func negativeSlackIsOneQuietNote() throws {
        let note = try #require(plan(day: 15, 7, samples: [workout(day: 9)])) // Sun: 1 day left, 2 to go
        #expect(note.kind == .workoutBehind)
        #expect(note.isQuiet)
        var book = ReminderBookkeeping()
        book.recordWorkoutReminder(.behind(workoutsToGo: 2, daysLeft: 2), at: cal.at(2026, 11, 14, 8))
        #expect(plan(day: 15, 7, samples: [workout(day: 9)], book: book) == nil)
    }

    @Test func atMostOnePerDay() {
        var book = ReminderBookkeeping()
        book.recordWorkoutReminder(.nudge(workoutsToGo: 3, daysLeft: 4), at: cal.at(2026, 11, 12, 6))
        #expect(plan(day: 12, 7, book: book) == nil)
    }

    @Test func nothingOnceTodaysMinutesOrTheWeekAreDone() {
        // Sat: slack 0, but a 60 min workout at 06:00 today already counts.
        #expect(plan(day: 14, 7, samples: [workout(day: 9), workout(day: 14)]) == nil)
        #expect(plan(day: 14, 7, samples: [workout(day: 9), workout(day: 10), workout(day: 11)]) == nil)
    }

    @Test func respectsTheToggle() {
        var off = settings
        off.remindersEnabled = false
        #expect(plan(day: 12, 7, settings: off) == nil)
    }

    @Test func sundayNightPlansMondayInTheNewWeek() throws {
        #expect(plan(day: 15, 21, samples: [workout(day: 9)]) == nil) // Mon: slack 4 again
        var everyDay = settings
        everyDay.workoutGoal = WorkoutGoal(minMinutesPerDay: 30, daysPerWeek: 7)
        let note = try #require(plan(day: 15, 21, settings: everyDay))
        #expect(note.fireDate == cal.at(2026, 11, 16, 8))
        #expect(note.title == "Today's a workout day")
    }

    @Test func reminderTimeInsideADSTGapResolvesOnThatDay() throws {
        let ny = Calendar.test("America/New_York")
        var s = settings
        s.workoutGoal = WorkoutGoal(minMinutesPerDay: 30, daysPerWeek: 7) // Sun Mar 8: slack 1 − 7 < 0
        s.workoutReminderTime = TimeOfDay(hour: 2, minute: 30)               // skipped on Mar 8
        let note = try #require(ReminderPlanner.workout(settings: s, workouts: [], bookkeeping: ReminderBookkeeping(),
                                                        now: ny.at(2026, 3, 8, 0, 30), calendar: ny))
        #expect(ny.isDate(note.fireDate, inSameDayAs: ny.at(2026, 3, 8, 12)))
        #expect(note.fireDate > ny.at(2026, 3, 8, 0, 30))
        #expect(note.id == "fuely.workout.2026-03-08")
    }
}

@Suite struct ReminderPlanTests {
    let cal = Calendar.test()

    @Test func combinesWaterAndWorkoutSortedByFireDate() {
        let settings = FuelySettings(waterGoalML: 2400)
        let reminders = ReminderPlanner.plan(settings: settings, todayTotalML: 0, workouts: [],
                                             bookkeeping: ReminderBookkeeping(), now: cal.at(2026, 11, 12, 6),
                                             leadTime: ReminderPlanner.minimumLead, calendar: cal)
        #expect(reminders.map(\.kind) == [.water, .workout, .water])
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        #expect(reminders.allSatisfy { ReminderPlanner.isFuelyID($0.id) })
    }

    @Test func fuelyIDs() {
        #expect(ReminderPlanner.isFuelyID("fuely.water.2026-11-09.1"))
        #expect(!ReminderPlanner.isFuelyID("other.reminder"))
    }
}

/// Which planned reminders went out (fire date passed = delivered; see `ReminderBookkeeping`).
@Suite struct ReminderDeliveryTests {
    let cal = Calendar.test()

    func scheduled(_ kind: PlannedReminder.Kind, _ hour: Int, _ minute: Int = 0, id: String? = nil) -> ScheduledReminder {
        ScheduledReminder(id: id ?? "fuely.\(kind.rawValue).\(hour)", kind: kind, fireDate: cal.at(2026, 11, 9, hour, minute))
    }

    @Test func passedFireDatesCountAsSent() {
        var book = ReminderBookkeeping()
        book.setScheduled([scheduled(.water, 9, 16), scheduled(.water, 11, 16), scheduled(.workout, 8)])
        let delivered = book.markDelivered(asOf: cal.at(2026, 11, 9, 10), calendar: cal)
        #expect(delivered.map(\.kind) == [.workout, .water])
        #expect(book.waterRemindersSent(onDayOf: cal.at(2026, 11, 9, 10), calendar: cal) == 1)
        #expect(book.lastWaterReminderAt == cal.at(2026, 11, 9, 9, 16))
        #expect(book.workoutRemindedToday(now: cal.at(2026, 11, 9, 10), calendar: cal))
        #expect(book.scheduled.map(\.fireDate) == [cal.at(2026, 11, 9, 11, 16)])

        book.markDelivered(asOf: cal.at(2026, 11, 9, 12), calendar: cal)
        #expect(book.waterRemindersSent(onDayOf: cal.at(2026, 11, 9, 12), calendar: cal) == 2)
        #expect(book.scheduled.isEmpty)
    }

    @Test func aFireDateExactlyNowCounts() {
        var book = ReminderBookkeeping()
        book.setScheduled([scheduled(.water, 9)])
        #expect(book.markDelivered(asOf: cal.at(2026, 11, 9, 9), calendar: cal).count == 1)
    }

    @Test func aDeliveredBehindNoteSilencesTheWeek() {
        var book = ReminderBookkeeping()
        book.setScheduled([scheduled(.workoutBehind, 8)])
        book.markDelivered(asOf: cal.at(2026, 11, 9, 9), calendar: cal)
        #expect(book.behindNoteSentThisWeek(now: cal.at(2026, 11, 15, 20), calendar: cal))
    }

    @Test func scheduledSurvivesTheStoreAndOldFilesDecode() throws {
        let store = makeTempStore()
        try store.updateReminders { $0.setScheduled([scheduled(.water, 9)]) }
        #expect(try FuelyStore(directory: store.directory).reminders().scheduled.count == 1)

        let old = #"{"waterRemindersOnLastDay": 1}"#
        let book = try JSONDecoder().decode(ReminderBookkeeping.self, from: Data(old.utf8))
        #expect(book.scheduled.isEmpty)

        let unknownKind = #"{"scheduled": [{"id": "fuely.x", "kind": "stretch", "fireDate": 0}, {"id": "fuely.w", "kind": "water", "fireDate": 0}]}"#
        let lossy = try JSONDecoder().decode(ReminderBookkeeping.self, from: Data(unknownKind.utf8))
        #expect(lossy.scheduled.map(\.id) == ["fuely.w"])
    }
}
