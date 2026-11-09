import Foundation
import Testing
@testable import FuelyCore

@Suite struct WorkoutWeekTests {
    let cal = Calendar.test()
    let goal = WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: 3)

    func workout(_ start: Date, minutes: Double) -> WorkoutSample {
        WorkoutSample(start: start, end: start.addingTimeInterval(.minutes(minutes)), duration: .minutes(minutes))
    }

    @Test func emptyWeekStartsOnMondayEvenWhenLocaleStartsOnSunday() {
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 4, 9), samples: [], goal: goal, calendar: cal)
        #expect(week.start == cal.at(2026, 11, 2))
        #expect(week.days.count == 7)
        #expect(week.days.last?.date == cal.at(2026, 11, 8))
        #expect(week.workoutDays == 0)
        #expect(week.workoutsStillNeeded == 3)
        #expect(!week.isGoalReached)
    }

    @Test func minutesWithinADayAddUp() {
        let samples = [workout(cal.at(2026, 11, 3, 6), minutes: 30), workout(cal.at(2026, 11, 3, 20), minutes: 30)]
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 4), samples: samples, goal: goal, calendar: cal)
        let tuesday = week.day(containing: cal.at(2026, 11, 3, 12), calendar: cal)
        #expect(tuesday?.minutes == 60)
        #expect(tuesday?.isWorkoutDay == true)
        #expect(week.workoutDays == 1)
    }

    @Test func thresholdIsInclusive() {
        let samples = [workout(cal.at(2026, 11, 2, 7), minutes: 50), workout(cal.at(2026, 11, 3, 7), minutes: 49)]
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 4), samples: samples, goal: goal, calendar: cal)
        #expect(week.days[0].isWorkoutDay)
        #expect(!week.days[1].isWorkoutDay)
        #expect(week.workoutDays == 1)
    }

    @Test func aDayCountsAtMostOnce() {
        let samples = [workout(cal.at(2026, 11, 5, 7), minutes: 60), workout(cal.at(2026, 11, 5, 18), minutes: 60)]
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 5), samples: samples, goal: goal, calendar: cal)
        #expect(week.workoutDays == 1)
    }

    @Test func samplesOutsideTheWeekAreIgnored() {
        let samples = [
            workout(cal.at(2026, 11, 1, 23), minutes: 60), // previous Sunday
            workout(cal.at(2026, 11, 9, 0, 0), minutes: 60), // next Monday
        ]
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 8, 23, 59), samples: samples, goal: goal, calendar: cal)
        #expect(week.workoutDays == 0)
        #expect(week.days.allSatisfy { $0.minutes == 0 })
    }

    @Test func sundayBelongsToTheWeekThatStartedMonday() {
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 8, 23, 59), samples: [], goal: goal, calendar: cal)
        #expect(week.start == cal.at(2026, 11, 2))
        let nextWeek = WorkoutAggregation.week(containing: cal.at(2026, 11, 9, 0, 0), samples: [], goal: goal, calendar: cal)
        #expect(nextWeek.start == cal.at(2026, 11, 9))
    }

    @Test func dayAssignmentFollowsTheInjectedTimeZone() {
        let utc = Calendar.test("UTC")
        let instant = utc.at(2026, 11, 8, 18) // Sunday in UTC, Monday 01:00 in the test time zone (UTC+7)
        let samples = [workout(instant, minutes: 60)]
        let utcWeek = WorkoutAggregation.week(containing: utc.at(2026, 11, 8, 20), samples: samples, goal: goal, calendar: utc)
        #expect(utcWeek.workoutDays == 1)
        let localWeek = WorkoutAggregation.week(containing: cal.at(2026, 11, 8, 20), samples: samples, goal: goal, calendar: cal)
        #expect(localWeek.workoutDays == 0)
    }

    @Test func workoutCrossingMidnightCountsOnItsStartDay() {
        let samples = [workout(cal.at(2026, 11, 3, 23, 30), minutes: 60)]
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 4), samples: samples, goal: goal, calendar: cal)
        #expect(week.days[1].minutes == 60)
        #expect(week.days[2].minutes == 0)
    }

    @Test func durationExcludesPausesNotWallClock() {
        let start = cal.at(2026, 11, 3, 7)
        let paused = WorkoutSample(start: start, end: start.addingTimeInterval(.minutes(70)), duration: .minutes(45))
        let week = WorkoutAggregation.week(containing: start, samples: [paused], goal: goal, calendar: cal)
        #expect(week.days[1].minutes == 45)
        #expect(!week.days[1].isWorkoutDay)
    }

    @Test func goalReachedAndOverGoal() {
        let samples = (2...6).map { workout(cal.at(2026, 11, $0, 7), minutes: 55) }
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 7), samples: samples, goal: goal, calendar: cal)
        #expect(week.workoutDays == 5)
        #expect(week.isGoalReached)
        #expect(week.workoutsStillNeeded == 0)
    }

    @Test func daysLeftIncludesToday() {
        let week = WorkoutAggregation.week(containing: cal.at(2026, 11, 2), samples: [], goal: goal, calendar: cal)
        #expect(week.daysLeft(includingDayOf: cal.at(2026, 11, 2, 8), calendar: cal) == 7)
        #expect(week.daysLeft(includingDayOf: cal.at(2026, 11, 6, 8), calendar: cal) == 3)
        #expect(week.daysLeft(includingDayOf: cal.at(2026, 11, 8, 23), calendar: cal) == 1)
        #expect(week.daysLeft(includingDayOf: cal.at(2026, 11, 9, 1), calendar: cal) == 0)
    }

    @Test func fallBackWeekHasSevenDays() {
        // 2026-11-01 New York ends DST (Sunday). Week Mon Oct 26 – Sun Nov 1.
        let ny = Calendar.test("America/New_York")
        let samples = [workout(ny.at(2026, 11, 1, 23, 0), minutes: 50)]
        let week = WorkoutAggregation.week(containing: ny.at(2026, 11, 1, 12), samples: samples, goal: goal, calendar: ny)
        #expect(week.start == ny.at(2026, 10, 26))
        #expect(week.days.map(\.date) == (26...31).map { ny.at(2026, 10, $0) } + [ny.at(2026, 11, 1)])
        #expect(week.days[6].isWorkoutDay)
    }

    @Test func goalDaysAreClampedTo1Through7() {
        #expect(WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: 0).daysPerWeek == 1)
        #expect(WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: 9).daysPerWeek == 7)
        #expect(WorkoutGoal.default == WorkoutGoal(minMinutesPerDay: 50, daysPerWeek: 3))
    }
}
