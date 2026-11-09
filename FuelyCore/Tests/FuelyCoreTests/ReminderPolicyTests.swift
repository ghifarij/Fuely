import Foundation
import Testing
@testable import FuelyCore

@Suite struct WaterReminderPolicyTests {
    let cal = Calendar.test()
    let window = DrinkingWindow.default // 05:00–22:00

    func should(at hour: Int, _ minute: Int = 0, total: Int, sent: Int = 0, enabled: Bool = true) -> Bool {
        WaterReminderPolicy.shouldRemind(
            now: cal.at(2026, 11, 8, hour, minute), todayTotalML: total, goalML: 2400,
            window: window, enabled: enabled, remindersSentToday: sent, calendar: cal)
    }

    @Test func remindsOnlyWhenBehindInsideTheWindow() {
        #expect(should(at: 13, 30, total: 1000))
        #expect(!should(at: 13, 30, total: 1200)) // exactly on pace
        #expect(!should(at: 13, 30, total: 2400)) // goal met
    }

    @Test func neverOutsideTheWindow() {
        #expect(!should(at: 4, 59, total: 0))
        #expect(!should(at: 22, 0, total: 0))
        #expect(!should(at: 23, 30, total: 0))
    }

    @Test func atMostTwoPerDay() {
        #expect(should(at: 15, total: 0, sent: 1))
        #expect(!should(at: 15, total: 0, sent: 2))
        #expect(!should(at: 15, total: 0, sent: 3))
        #expect(WaterReminderPolicy.maxPerDay == 2)
    }

    @Test func respectsTheToggle() {
        #expect(!should(at: 15, total: 0, enabled: false))
    }

    func next(from hour: Int, _ minute: Int = 0, total: Int, sent: Int = 0) -> Date? {
        WaterReminderPolicy.nextReminderDate(
            after: cal.at(2026, 11, 8, hour, minute), todayTotalML: total, goalML: 2400,
            window: window, enabled: true, remindersSentToday: sent, calendar: cal)
    }

    @Test func nextReminderIsWhenPaceOvertakesTheTotal() {
        // 600 / 2400 = 25 % of the 17 h window -> 05:00 + 4h15 = 09:15.
        #expect(next(from: 7, total: 600) == cal.at(2026, 11, 8, 9, 15))
        // Already behind: now.
        #expect(next(from: 10, total: 600) == cal.at(2026, 11, 8, 10))
        // Before the window with nothing logged: the window start.
        #expect(next(from: 3, total: 0) == cal.at(2026, 11, 8, 5))
    }

    @Test func noNextReminderWhenNothingCanBeSent() {
        #expect(next(from: 7, total: 2400) == nil) // goal met
        #expect(next(from: 7, total: 0, sent: 2) == nil) // cap reached
        #expect(next(from: 22, total: 0) == nil) // window over
        #expect(WaterReminderPolicy.nextReminderDate(
            after: cal.at(2026, 11, 8, 7), todayTotalML: 0, goalML: 2400, window: window,
            enabled: false, remindersSentToday: 0, calendar: cal) == nil)
    }

    @Test func nextReminderDateAgreesWithShouldRemind() throws {
        let date = try #require(next(from: 7, total: 600))
        let later = date.addingTimeInterval(60)
        #expect(WaterReminderPolicy.shouldRemind(
            now: later, todayTotalML: 600, goalML: 2400, window: window,
            enabled: true, remindersSentToday: 0, calendar: cal))
        #expect(!WaterReminderPolicy.shouldRemind(
            now: date.addingTimeInterval(-60), todayTotalML: 600, goalML: 2400, window: window,
            enabled: true, remindersSentToday: 0, calendar: cal))
    }
}

@Suite struct WorkoutReminderPolicyTests {
    let cal = Calendar.test()
    let goal = WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: 3)
    let morning = TimeOfDay(hour: 8)

    func workout(day: Int, minutes: Double = 60) -> WorkoutSample {
        let start = cal.at(2026, 11, day, 6)
        return WorkoutSample(start: start, end: start.addingTimeInterval(.minutes(minutes)), duration: .minutes(minutes))
    }

    /// Nov 2 2026 is a Monday, Nov 8 a Sunday.
    func reminder(day: Int, hour: Int = 8, minute: Int = 0, samples: [WorkoutSample] = [], goal: WorkoutGoal? = nil,
                  remindedToday: Bool = false, behindNoteSent: Bool = false) -> WorkoutReminder? {
        WorkoutReminderPolicy.reminder(
            now: cal.at(2026, 11, day, hour, minute), samples: samples, goal: goal ?? self.goal,
            reminderTime: morning, alreadyRemindedToday: remindedToday,
            behindNoteSentThisWeek: behindNoteSent, calendar: cal)
    }

    @Test func slackFormula() {
        #expect(WorkoutReminderPolicy.slack(daysLeftInWeek: 7, workoutsStillNeeded: 3) == 4)
        #expect(WorkoutReminderPolicy.slack(daysLeftInWeek: 1, workoutsStillNeeded: 2) == -1)
    }

    @Test func plentyOfSlackMeansNothing() {
        #expect(reminder(day: 2) == nil) // Mon: 7 days left, need 3 -> slack 4
        #expect(reminder(day: 3) == nil) // Tue: 6 days left, need 3 -> slack 3
    }

    @Test func slackTwoIsSilent() {
        #expect(reminder(day: 4) == nil) // Wed: 5 days left, need 3 -> slack 2
    }

    @Test func slackOneIsAGentleNudge() {
        #expect(reminder(day: 5) == .nudge(workoutsToGo: 3, daysLeft: 4)) // Thu
        #expect(reminder(day: 6, samples: [workout(day: 2)]) == .nudge(workoutsToGo: 2, daysLeft: 3)) // Fri
    }

    @Test func slackZeroIsAWorkoutDay() {
        #expect(reminder(day: 7, samples: [workout(day: 2)]) == .workoutDay(workoutsToGo: 2, daysLeft: 2)) // Sat
    }

    @Test func negativeSlackIsOneQuietNoteThenSilence() {
        #expect(reminder(day: 8, samples: [workout(day: 2)]) == .behind(workoutsToGo: 2, daysLeft: 1)) // Sun
        #expect(reminder(day: 8, samples: [workout(day: 2)], behindNoteSent: true) == nil)
    }

    @Test func atMostOnePerDay() {
        #expect(reminder(day: 5, remindedToday: true) == nil)
    }

    @Test func onlyFromTheMorningTimeOn() {
        #expect(reminder(day: 5, hour: 7, minute: 59) == nil)
        #expect(reminder(day: 5, hour: 12) == .nudge(workoutsToGo: 3, daysLeft: 4))
    }

    @Test func nothingOnceTodaysMinutesAreMet() {
        #expect(reminder(day: 7, samples: [workout(day: 2), workout(day: 7)]) == nil)
    }

    @Test func partialMinutesTodayStillRemind() {
        let samples = [workout(day: 2), workout(day: 7, minutes: 20)]
        #expect(reminder(day: 7, samples: samples) == .workoutDay(workoutsToGo: 2, daysLeft: 2))
    }

    @Test func nothingOnceTheWeeklyGoalIsReached() {
        let samples = [workout(day: 2), workout(day: 3), workout(day: 4)]
        #expect(reminder(day: 8, samples: samples) == nil)
    }

    @Test(arguments: 1...7)
    func worksForAnyGoal(days: Int) {
        let g = WorkoutGoal(minMinutesPerDay: 30, daysPerWeek: days)
        // On Sunday with nothing done: 1 day left.
        let sunday = reminder(day: 8, goal: g)
        if days == 1 {
            #expect(sunday == .workoutDay(workoutsToGo: 1, daysLeft: 1))
        } else {
            #expect(sunday == .behind(workoutsToGo: days, daysLeft: 1))
        }
        // On Monday with nothing done: 7 days left.
        let monday = reminder(day: 2, goal: g)
        switch 7 - days {
        case 0: #expect(monday == .workoutDay(workoutsToGo: 7, daysLeft: 7))
        case 1: #expect(monday == .nudge(workoutsToGo: 6, daysLeft: 7))
        default: #expect(monday == nil)
        }
    }

    @Test func nextMorningDate() {
        let next = WorkoutReminderPolicy.nextReminderDate(after: cal.at(2026, 11, 8, 9), reminderTime: morning, calendar: cal)
        #expect(next == cal.at(2026, 11, 9, 8))
        let sameDay = WorkoutReminderPolicy.nextReminderDate(after: cal.at(2026, 11, 8, 7), reminderTime: morning, calendar: cal)
        #expect(sameDay == cal.at(2026, 11, 8, 8))
    }
}
