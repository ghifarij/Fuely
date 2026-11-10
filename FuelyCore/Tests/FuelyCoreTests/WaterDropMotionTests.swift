import Foundation
import Testing
@testable import FuelyCore

/// DECISIONS T4a: the opening rise plays on a cold launch or after ≥ 30 min in the background.
@Suite struct OpeningRiseTests {
    let cal = Calendar.test()
    var now: Date { cal.at(2026, 11, 9, 15) }

    @Test func coldLaunchAlwaysRises() {
        #expect(WaterDropMotion.shouldPlayOpeningRise(isColdLaunch: true, backgroundedAt: nil, now: now))
        #expect(WaterDropMotion.shouldPlayOpeningRise(isColdLaunch: true, backgroundedAt: now.addingTimeInterval(-5), now: now))
    }

    @Test func neverBackgroundedNeverRises() {
        // Becoming active without a background stint: Control Center, a sheet, back from Week.
        #expect(!WaterDropMotion.shouldPlayOpeningRise(isColdLaunch: false, backgroundedAt: nil, now: now))
    }

    @Test func shortBackgroundDoesNotRise() {
        #expect(!WaterDropMotion.shouldPlayOpeningRise(isColdLaunch: false, backgroundedAt: now.addingTimeInterval(-60), now: now))
        #expect(!WaterDropMotion.shouldPlayOpeningRise(
            isColdLaunch: false, backgroundedAt: now.addingTimeInterval(-.minutes(30) + 1), now: now))
    }

    @Test func exactlyThirtyMinutesRises() {
        #expect(WaterDropMotion.shouldPlayOpeningRise(
            isColdLaunch: false, backgroundedAt: now.addingTimeInterval(-.minutes(30)), now: now))
    }

    @Test func longBackgroundRises() {
        #expect(WaterDropMotion.shouldPlayOpeningRise(
            isColdLaunch: false, backgroundedAt: now.addingTimeInterval(-.hours(5)), now: now))
    }

    @Test func clockMovedBackDoesNotRise() {
        #expect(!WaterDropMotion.shouldPlayOpeningRise(
            isColdLaunch: false, backgroundedAt: now.addingTimeInterval(.hours(1)), now: now))
    }

    @Test func pendingRiseExpires() {
        #expect(!WaterDropMotion.shouldStartPendingRise(requestedAt: nil, now: now))
        #expect(WaterDropMotion.shouldStartPendingRise(requestedAt: now, now: now))
        #expect(WaterDropMotion.shouldStartPendingRise(requestedAt: now.addingTimeInterval(-1.9), now: now))
        #expect(!WaterDropMotion.shouldStartPendingRise(requestedAt: now.addingTimeInterval(-2), now: now))
        #expect(!WaterDropMotion.shouldStartPendingRise(requestedAt: now.addingTimeInterval(-60), now: now))
        #expect(!WaterDropMotion.shouldStartPendingRise(requestedAt: now.addingTimeInterval(5), now: now))
    }
}

/// DECISIONS T4c: the goal sparkle plays once per calendar day.
@Suite struct GoalCelebrationTests {
    let cal = Calendar.test()
    var now: Date { cal.at(2026, 11, 9, 15) }

    @Test func belowGoalNeverCelebrates() {
        #expect(!WaterDropMotion.shouldCelebrate(fraction: 0, lastCelebratedDay: nil, now: now, calendar: cal))
        #expect(!WaterDropMotion.shouldCelebrate(fraction: 0.999, lastCelebratedDay: nil, now: now, calendar: cal))
        #expect(!WaterDropMotion.shouldCelebrate(fraction: .nan, lastCelebratedDay: nil, now: now, calendar: cal))
        #expect(!WaterDropMotion.shouldCelebrate(fraction: .infinity, lastCelebratedDay: nil, now: now, calendar: cal))
    }

    @Test func reachingTheGoalCelebratesOnce() {
        #expect(WaterDropMotion.shouldCelebrate(fraction: 1, lastCelebratedDay: nil, now: now, calendar: cal))
        #expect(WaterDropMotion.shouldCelebrate(fraction: 1.4, lastCelebratedDay: nil, now: now, calendar: cal))
        let earlierToday = cal.at(2026, 11, 9, 8)
        #expect(!WaterDropMotion.shouldCelebrate(fraction: 1.2, lastCelebratedDay: earlierToday, now: now, calendar: cal))
    }

    @Test func yesterdaysCelebrationDoesNotCount() {
        let yesterday = cal.at(2026, 11, 8, 23, 59)
        #expect(WaterDropMotion.shouldCelebrate(fraction: 1, lastCelebratedDay: yesterday, now: now, calendar: cal))
    }

    @Test func dayBoundaryIsLocalMidnight() {
        let lateCelebration = cal.at(2026, 11, 8, 23, 59, 59)
        #expect(!WaterDropMotion.shouldCelebrate(fraction: 1, lastCelebratedDay: lateCelebration,
                                                 now: cal.at(2026, 11, 8, 23, 59, 59), calendar: cal))
        #expect(WaterDropMotion.shouldCelebrate(fraction: 1, lastCelebratedDay: lateCelebration,
                                                now: cal.at(2026, 11, 9, 0, 0), calendar: cal))
    }

    @Test func usesTheCalendarsTimeZone() {
        // 16:00 UTC on the 8th is 23:00 in Bangkok; 18:00 UTC is already the 9th there.
        let utc = Calendar.test("UTC")
        let celebrated = utc.at(2026, 11, 8, 16)
        let later = utc.at(2026, 11, 8, 18)
        #expect(WaterDropMotion.shouldCelebrate(fraction: 1, lastCelebratedDay: celebrated, now: later,
                                                calendar: Calendar.test("Asia/Bangkok")))
        #expect(!WaterDropMotion.shouldCelebrate(fraction: 1, lastCelebratedDay: celebrated, now: later, calendar: utc))
    }
}

/// DECISIONS T4b, T4e, T4f: what the drop plays per source and system setting.
@Suite struct DropMotionPolicyTests {
    let normal = DropMotionPolicy(reduceMotion: false, lowPower: false)
    let lowPower = DropMotionPolicy(reduceMotion: false, lowPower: true)
    let reduceMotion = DropMotionPolicy(reduceMotion: true, lowPower: false)
    let both = DropMotionPolicy(reduceMotion: true, lowPower: true)

    @Test func fuelyLogSplashesWithSpringAndHaptic() {
        let change = normal.levelChange(rose: true, fromFuelyLog: true, wasFull: false)
        #expect(change.animation == .spring)
        #expect(change.splash)
        #expect(change.impactHaptic)
    }

    @Test func noSplashWhenAlreadyFull() {
        let change = normal.levelChange(rose: true, fromFuelyLog: true, wasFull: true)
        #expect(!change.splash)
        #expect(change.impactHaptic)
    }

    @Test func healthRefreshRisesQuietly() {
        let change = normal.levelChange(rose: true, fromFuelyLog: false, wasFull: false)
        #expect(change.animation == .smooth)
        #expect(!change.splash)
        #expect(!change.impactHaptic)
    }

    @Test func goingDownIsQuiet() {
        // Undo, delete, or midnight: even with a log counter change it is not a drink.
        let change = normal.levelChange(rose: false, fromFuelyLog: true, wasFull: false)
        #expect(change.animation == .smooth)
        #expect(!change.splash)
        #expect(!change.impactHaptic)
    }

    @Test func lowPowerKeepsAShortEaseAndHapticsForFuelyLogs() {
        let log = lowPower.levelChange(rose: true, fromFuelyLog: true, wasFull: false)
        #expect(log.animation == .quickEase)
        #expect(!log.splash)
        #expect(log.impactHaptic)
        let refresh = lowPower.levelChange(rose: true, fromFuelyLog: false, wasFull: false)
        #expect(refresh.animation == .none)
        #expect(!refresh.impactHaptic)
    }

    @Test func lowPowerStopsDecorativeMotion() {
        #expect(!lowPower.animatesWaves)
        #expect(!lowPower.showsBubbles)
        #expect(!lowPower.playsOpeningRise)
        #expect(!lowPower.showsSparkle)
    }

    @Test func reduceMotionHasNoMotionButKeepsHaptics() {
        let log = reduceMotion.levelChange(rose: true, fromFuelyLog: true, wasFull: false)
        #expect(log.animation == .none)
        #expect(!log.splash)
        #expect(log.impactHaptic)
        #expect(!reduceMotion.animatesWaves)
        #expect(!reduceMotion.playsOpeningRise)
        #expect(!reduceMotion.showsSparkle)
        #expect(reduceMotion.showsBubbles) // still bubbles in the still frame
    }

    @Test func bothOnTakesTheStricterRule() {
        let log = both.levelChange(rose: true, fromFuelyLog: true, wasFull: false)
        #expect(log.animation == .none)
        #expect(log.impactHaptic)
        #expect(!both.showsBubbles)
        #expect(!both.animatesWaves)
    }

    @Test func normalModeAnimatesEverything() {
        #expect(normal.animatesWaves)
        #expect(normal.showsBubbles)
        #expect(normal.playsOpeningRise)
        #expect(normal.showsSparkle)
    }
}
