import Foundation
import Testing
@testable import FuelyCore

// MARK: - Scoring functions (DECISIONS S8)

/// Synthetic nights: whole-minute inputs (the precision Apple displays) and the component points the
/// formula gives for them. Every component and the total must match exactly.
@Suite struct SleepScoreFormulaTests {
    struct Night: CustomTestStringConvertible, Sendable {
        let name: String
        let asleep: Int
        /// Onset minus average onset, minutes (+ later); nil = no average yet.
        let deviation: Int?
        let wakeUps: Int
        let wakeUpMinutes: Int
        let duration: Int, bedtime: Int, interruptions: Int, total: Int
        var testDescription: String { name }
    }

    static let nights: [Night] = [
        // 44.92 + 0.078 × 20 = 46.48; 30 − 0.2 × 5 = 29; 2 wake-ups within 10 free minutes.
        Night(name: "slightly long, a bit late", asleep: 440, deviation: 20, wakeUps: 2, wakeUpMinutes: 8,
              duration: 46, bedtime: 29, interruptions: 20, total: 95),
        // 44.92 − 0.14 × 20 = 42.12; 30 − 0.1 × 15 = 28.5 → 29 (half up); 20 − 4 − 2 = 14.
        Night(name: "short, early", asleep: 400, deviation: -75, wakeUps: 6, wakeUpMinutes: 40,
              duration: 42, bedtime: 29, interruptions: 14, total: 85),
        // 44.92 − 0.14 × 70 = 35.12; 30 − 0.2 × 75 = 15; 20 − 9 − 5 = 6.
        Night(name: "short, late, restless", asleep: 350, deviation: 90, wakeUps: 9, wakeUpMinutes: 70,
              duration: 35, bedtime: 15, interruptions: 6, total: 56),
        // 44.92 + 0.078 × 60 = 49.6; no average yet = full bedtime points.
        Night(name: "long, first night", asleep: 480, deviation: nil, wakeUps: 0, wakeUpMinutes: 0,
              duration: 50, bedtime: 30, interruptions: 20, total: 100),
        // 44.92 − 0.14 × 150 = 23.92; 30 − 0.1 × 90 = 21; 20 − 14 − 7 = −1 → 0.
        Night(name: "very short, very early", asleep: 270, deviation: -150, wakeUps: 12, wakeUpMinutes: 95,
              duration: 24, bedtime: 21, interruptions: 0, total: 45),
        // 51.94 → capped at 50; 30 − 37 → 0; interruptions far below 0 → 0.
        Night(name: "everything clamped", asleep: 510, deviation: 200, wakeUps: 20, wakeUpMinutes: 150,
              duration: 50, bedtime: 0, interruptions: 0, total: 50),
        // 44.92 − 0.14 × 40 = 39.32; early within the 60 min grace; 20 − 2.33 − 1.2 = 16.47.
        Night(name: "early within grace", asleep: 380, deviation: -30, wakeUps: 5, wakeUpMinutes: 31,
              duration: 39, bedtime: 30, interruptions: 16, total: 85),
    ]

    @Test(arguments: nights) func matchesTheFormula(_ night: Night) {
        let duration = SleepScoring.durationPoints(asleepMinutes: night.asleep)
        let bedtime = SleepScoring.bedtimePoints(deviationMinutes: night.deviation)
        let interruptions = SleepScoring.interruptionPoints(wakeUps: night.wakeUps, minutes: night.wakeUpMinutes)
        #expect(duration == night.duration)
        #expect(bedtime == night.bedtime)
        #expect(interruptions == night.interruptions)
        #expect(duration + bedtime + interruptions == night.total)
    }

    @Test func durationCurveShape() {
        #expect(SleepScoring.durationPoints(asleepMinutes: 0) == 0)
        #expect(SleepScoring.durationPoints(asleepMinutes: -10) == 0)
        #expect(SleepScoring.durationPoints(asleepMinutes: 99) == 0) // −0.02
        #expect(SleepScoring.durationPoints(asleepMinutes: 240) == 20) // 19.72, steep below the kink
        #expect(SleepScoring.durationPoints(asleepMinutes: 419) == 45) // 44.78
        #expect(SleepScoring.durationPoints(asleepMinutes: 420) == 45) // 44.92 at the 7 h kink
        #expect(SleepScoring.durationPoints(asleepMinutes: 421) == 45) // 44.998, gentle above it
        #expect(SleepScoring.durationPoints(asleepMinutes: 485) == 50) // 49.99
        #expect(SleepScoring.durationPoints(asleepMinutes: 486) == 50) // 50.068, capped
        #expect(SleepScoring.durationPoints(asleepMinutes: 900) == 50) // no long-sleep penalty
    }

    @Test func bedtimeLateCostsMoreThanEarly() {
        #expect(SleepScoring.bedtimePoints(deviationMinutes: nil) == 30)
        #expect(SleepScoring.bedtimePoints(deviationMinutes: 0) == 30)
        // Late: 15 min grace, then 0.2 pt per minute.
        #expect(SleepScoring.bedtimePoints(deviationMinutes: 15) == 30)
        #expect(SleepScoring.bedtimePoints(deviationMinutes: 17) == 30) // 29.6
        #expect(SleepScoring.bedtimePoints(deviationMinutes: 18) == 29) // 29.4
        #expect(SleepScoring.bedtimePoints(deviationMinutes: 164) == 0) // 0.2
        #expect(SleepScoring.bedtimePoints(deviationMinutes: 165) == 0)
        #expect(SleepScoring.bedtimePoints(deviationMinutes: 400) == 0)
        // Early: 60 min grace, then 0.1 pt per minute.
        #expect(SleepScoring.bedtimePoints(deviationMinutes: -60) == 30)
        #expect(SleepScoring.bedtimePoints(deviationMinutes: -65) == 30) // 29.5, half up
        #expect(SleepScoring.bedtimePoints(deviationMinutes: -66) == 29) // 29.4
        #expect(SleepScoring.bedtimePoints(deviationMinutes: -120) == 24)
        #expect(SleepScoring.bedtimePoints(deviationMinutes: -360) == 0)
        #expect(SleepScoring.bedtimePoints(deviationMinutes: -900) == 0)
    }

    @Test func interruptionThresholds() {
        #expect(SleepScoring.interruptionPoints(wakeUps: 0, minutes: 0) == 20)
        // Up to 3.6 wake-ups and 5 min each are free.
        #expect(SleepScoring.interruptionPoints(wakeUps: 3, minutes: 15) == 20)
        #expect(SleepScoring.interruptionPoints(wakeUps: 3, minutes: 17) == 20) // 19.6
        #expect(SleepScoring.interruptionPoints(wakeUps: 3, minutes: 18) == 19) // 19.4
        // A 4th wake-up costs 5/3 × 0.4 even when it is short.
        #expect(SleepScoring.interruptionPoints(wakeUps: 4, minutes: 0) == 19) // 19.33
        #expect(SleepScoring.interruptionPoints(wakeUps: 4, minutes: 20) == 19)
        #expect(SleepScoring.interruptionPoints(wakeUps: 5, minutes: 25) == 18) // 17.67
        #expect(SleepScoring.interruptionPoints(wakeUps: 15, minutes: 140) == 0)
        #expect(SleepScoring.interruptionPoints(wakeUps: 30, minutes: 300) == 0)
    }

    @Test func roundsHalfUp() {
        #expect(SleepScoring.roundHalfUp(47.5) == 48)
        #expect(SleepScoring.roundHalfUp(47.494) == 47)
        #expect(SleepScoring.roundHalfUp(2.5) == 3) // banker's rounding would give 2
        #expect(SleepScoring.roundHalfUp(-0.4) == 0)
    }
}

// MARK: - Measurement from HealthKit samples

/// Dates are made up: March 2030 in the test time zone (UTC+7, no DST).
@Suite struct SleepMeasurementTests {
    let cal = Calendar.test()

    let watch = SleepSampleSource(bundleIdentifier: "com.apple.health.watch", isAppleWatch: true, name: "Apple Watch")
    let phone = SleepSampleSource(bundleIdentifier: "com.apple.health.phone", isAppleWatch: false, name: "iPhone")
    let app = SleepSampleSource(bundleIdentifier: "com.example.sleeptracker", isAppleWatch: false, name: "SleepTracker")

    func s(_ start: Date, _ end: Date, _ stage: SleepStage = .asleepCore, _ source: SleepSampleSource? = nil) -> SleepSample {
        SleepSample(start: start, end: end, stage: stage, source: source ?? watch)
    }

    func score(_ samples: [SleepSample], day: Date) -> SleepScore? {
        SleepScoring.score(forNightEndingOn: day, samples: samples, calendar: cal)
    }

    /// `d(day, hour, minute, second)` in March 2030.
    func d(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        cal.at(2030, 3, day, hour, minute, second)
    }

    /// One 7 h night per sleep day in `days` (days of March 2030 unless `month`), falling asleep
    /// at `hour:minute` the evening before (or after midnight when `hour` < 12).
    func history(days: ClosedRange<Int>, month: Int = 3, hour: Int, minute: Int = 0) -> [SleepSample] {
        days.map { day in
            let onset = hour < 12 ? cal.at(2030, month, day, hour, minute) : cal.at(2030, month, day - 1, hour, minute)
            return s(onset, onset.addingTimeInterval(.hours(7)))
        }
    }

    // MARK: A full day, end to end

    /// 13 history nights falling asleep at 22:40, then the scored night of 16 March: Watch stages
    /// with four wake-ups (7 + 4 + 2 + 3 min), an overlapping iPhone "asleep" sample, pre-sleep and
    /// post-wake awake time, and a 14:00–14:45 afternoon nap logged as unstaged "asleep" by an app.
    func fullDay() -> [SleepSample] {
        let history = history(days: 3...15, hour: 22, minute: 40)
        let night = [
            s(d(15, 23, 0), d(15, 23, 10), .awake), // before sleep: excluded
            s(d(15, 23, 10), d(16, 1, 30), .asleepCore),
            s(d(16, 1, 30), d(16, 1, 37), .awake), // 7
            s(d(16, 1, 37), d(16, 3, 0), .asleepDeep),
            s(d(16, 3, 0), d(16, 3, 4), .awake), // 4
            s(d(16, 3, 4), d(16, 4, 50), .asleepREM),
            s(d(16, 4, 50), d(16, 4, 52), .awake), // 2
            s(d(16, 4, 52), d(16, 5, 30), .asleepCore),
            s(d(16, 5, 30), d(16, 5, 33), .awake), // 3
            s(d(16, 5, 33), d(16, 6, 20), .asleepCore),
            s(d(16, 6, 20), d(16, 6, 40), .awake), // after waking: excluded
            s(d(15, 23, 30), d(16, 0, 30), .asleepUnspecified, phone), // overlaps core
            s(d(16, 14, 0), d(16, 14, 45), .asleepUnspecified, app), // nap
        ]
        return history + night
    }

    @Test func scoresAFullDay() throws {
        let score = try #require(score(fullDay(), day: d(16, 20)))
        let night = score.night
        #expect(night.asleepMinutes == 459) // 414 night (430 − 16 awake) + 45 nap
        #expect(night.wakeUps == 4)
        #expect(night.wakeUpMinutes == 16)
        #expect(night.onset == d(15, 23, 10))
        #expect(night.averageOnsetMinutesAfterNoon == 640) // 22:40
        #expect(night.historyNights == 13)
        #expect(night.bedtimeDeviationMinutes == 30)
        #expect(night.includesNap)
        #expect(Set(night.sources.map(\.displayName)) == ["Apple Watch", "iPhone", "SleepTracker"])
        #expect(score.durationPoints == 48) // 47.962
        #expect(score.bedtimePoints == 27) // 30 − 0.2 × 15
        #expect(score.interruptionPoints == 19) // 19.33
        #expect(score.total == 94)
    }

    @Test func afternoonNapBelongsToThatDayNotTheNext() throws {
        let samples = fullDay()
        // Before the nap (07:00 on the 16th): only the night.
        let morning = samples.filter { $0.end <= d(16, 7) }
        #expect(try #require(score(morning, day: d(16, 7))).night.asleepMinutes == 414)
        // The 17th has no sleep of its own.
        #expect(score(samples, day: d(17, 9)) == nil)
    }

    // MARK: No data (S7)

    @Test func noSamplesMeansNoScore() {
        #expect(score([], day: d(10, 9)) == nil)
    }

    @Test func inBedAndAwakeAloneMeanNoScore() {
        let samples = [
            s(d(9, 22), d(10, 6), .inBed),
            s(d(9, 22), d(9, 23), .awake),
        ]
        #expect(score(samples, day: d(10, 9)) == nil)
    }

    @Test func invertedSamplesAreIgnored() {
        #expect(score([s(d(10, 6), d(9, 22))], day: d(10)) == nil)
    }

    @Test func aNightWithoutTheWatchStillScores() throws {
        // All sources count (S8): an iPhone-only "asleep" night gets a score.
        let night = s(d(9, 23), d(10, 6), .asleepUnspecified, phone)
        let result = try #require(score([night], day: d(10, 9)))
        #expect(result.night.asleepMinutes == 420)
        #expect(result.durationPoints == 45)
        #expect(result.total == 95)
    }

    // MARK: Asleep time

    @Test func overlappingSourcesAreUnitedNotPreferred() throws {
        let samples = [
            s(d(9, 23), d(10, 2), .asleepCore),
            s(d(10, 2), d(10, 6), .asleepDeep),
            s(d(9, 23), d(10, 6), .asleepCore), // duplicate
            // A phone app thinks the night was longer: its extra time counts too (union).
            s(d(9, 22, 30), d(10, 6, 30), .asleepUnspecified, app),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.asleepMinutes == 480)
        #expect(night.onset == d(9, 22, 30))
        #expect(night.wakeUps == 0)
    }

    @Test func fallBackNightMeasuresRealHours() throws {
        // 2030-11-03 New York: clocks go 02:00 -> 01:00, so 23:00 -> 07:00 is 9 real hours.
        let ny = Calendar.test("America/New_York")
        let sample = SleepSample(start: ny.at(2030, 11, 2, 23), end: ny.at(2030, 11, 3, 7), stage: .asleepCore)
        let result = try #require(SleepScoring.score(forNightEndingOn: ny.at(2030, 11, 3, 9), samples: [sample], calendar: ny))
        #expect(result.night.asleepMinutes == 540)
        #expect(result.durationPoints == 50)
    }

    // MARK: Minute grid (Apple scores whole clock minutes)

    @Test func everyClockMinuteTheSleepTouchesCounts() throws {
        // 23:00:00 → 06:00:20 touches 421 clock minutes; the partial last minute counts whole.
        let start = d(9, 23)
        let longer = s(start, d(10, 6, 0, 20))
        #expect(try #require(score([longer], day: d(10, 9))).night.asleepMinutes == 421)
        // 23:00:40 → 06:00:00: the partial first minute counts whole too.
        let later = s(start.addingTimeInterval(40), d(10, 6))
        #expect(try #require(score([later], day: d(10, 9))).night.asleepMinutes == 420)
        // 23:00:10 → 06:00:50: both partial ends count.
        let both = s(start.addingTimeInterval(10), d(10, 6, 0, 50))
        #expect(try #require(score([both], day: d(10, 9))).night.asleepMinutes == 421)
    }

    @Test func eachMinuteGoesToWhateverCoversMoreOfIt() throws {
        // Awake 02:00:20 → 02:01:40: 40 s of the 02:00 minute and 40 s of the 02:01 minute, so
        // both minutes are awake: one 2 min wake-up, 418 min asleep.
        let samples = [
            s(d(9, 23), d(10, 2, 0, 20)),
            s(d(10, 2, 0, 20), d(10, 2, 1, 40), .awake),
            s(d(10, 2, 1, 40), d(10, 6)),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.wakeUps == 1)
        #expect(night.wakeUpMinutes == 2)
        #expect(night.asleepMinutes == 418)
    }

    @Test func anAwakeSampleThatWinsNoMinuteIsNoWakeUp() throws {
        // A 30 s awake sample split over two minutes (15 s each) loses both to sleep. A 25 s
        // sample inside one minute loses it too.
        let samples = [
            s(d(9, 23), d(10, 2, 30, 45)),
            s(d(10, 2, 30, 45), d(10, 2, 31, 15), .awake),
            s(d(10, 2, 31, 15), d(10, 4, 0, 10)),
            s(d(10, 4, 0, 10), d(10, 4, 0, 35), .awake),
            s(d(10, 4, 0, 35), d(10, 6)),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.wakeUps == 0)
        #expect(night.wakeUpMinutes == 0)
        #expect(night.asleepMinutes == 420)
    }

    @Test func aTiedMinuteIsAsleepUnlessTuned() throws {
        // Awake 02:00:30 → 02:01:00: exactly half of the 02:00 minute.
        let samples = [
            s(d(9, 23), d(10, 2, 0, 30)),
            s(d(10, 2, 0, 30), d(10, 2, 1), .awake),
            s(d(10, 2, 1), d(10, 6)),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.wakeUps == 0)
        #expect(night.asleepMinutes == 420)
        var config = SleepScoreConfig()
        config.tiedMinuteIsAsleep = false
        let tuned = try #require(SleepScoring.score(forNightEndingOn: d(10, 9), samples: samples,
                                                    calendar: cal, config: config)).night
        #expect(tuned.wakeUps == 1)
        #expect(tuned.wakeUpMinutes == 1)
        #expect(tuned.asleepMinutes == 419)
    }

    @Test func aShortAwakeSampleThatWinsItsMinuteIsAWakeUp() throws {
        // 31 s awake inside one minute beats 29 s asleep: one 1 min wake-up (no minimum length).
        let samples = [
            s(d(9, 23), d(10, 2, 0, 10)),
            s(d(10, 2, 0, 10), d(10, 2, 0, 41), .awake),
            s(d(10, 2, 0, 41), d(10, 6)),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.wakeUps == 1)
        #expect(night.wakeUpMinutes == 1)
        #expect(night.asleepMinutes == 419)
    }

    // MARK: Wake-ups

    @Test func wakeUpsAreAwakeMinutesInsideTheSleep() throws {
        let samples = [
            s(d(9, 22, 30), d(9, 23), .awake), // before: excluded
            s(d(9, 23), d(10, 2)),
            s(d(10, 2), d(10, 2, 10), .awake), // 10
            s(d(10, 2, 10), d(10, 4)),
            s(d(10, 4), d(10, 4, 5), .awake),
            s(d(10, 4, 5), d(10, 4, 7), .awake), // back-to-back: one wake-up of 7
            s(d(10, 4, 7), d(10, 4, 8)),
            s(d(10, 4, 8), d(10, 4, 9), .awake), // 1 asleep minute between: a new one
            s(d(10, 4, 9), d(10, 6)),
            s(d(10, 6), d(10, 7), .awake), // after: excluded
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.wakeUps == 3)
        #expect(night.wakeUpMinutes == 18)
        #expect(night.asleepMinutes == 420 - 18)
        #expect(night.onset == d(9, 23))
    }

    @Test func gapsWithoutSamplesAreNeitherAsleepNorAwake() throws {
        // A source stops recording and resumes 33 min later: no wake-up and no asleep time in between.
        let samples = [
            s(d(9, 23), d(10, 2)),
            s(d(10, 2, 33), d(10, 6), .asleepUnspecified),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.asleepMinutes == 180 + 207)
        #expect(night.wakeUps == 0)
        #expect(night.wakeUpMinutes == 0)
        #expect(night.onset == d(9, 23))
        #expect(!night.includesNap) // one session
    }

    @Test func awakeCoveredByAnotherSourcesAsleepIsNotAWakeUp() throws {
        let samples = [
            s(d(9, 23), d(10, 2)),
            s(d(10, 2), d(10, 2, 10), .awake),
            s(d(10, 2, 10), d(10, 6)),
            s(d(10, 1), d(10, 3), .asleepUnspecified, phone),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.wakeUps == 0)
        #expect(night.asleepMinutes == 420)
    }

    @Test func onlyTheMainSleepsWakeUpsCount() throws {
        // Only the main sleep's wake-ups count; naps add asleep time.
        let samples = [
            s(d(9, 23), d(10, 2)),
            s(d(10, 2), d(10, 2, 3), .awake), // 3 min: counts
            s(d(10, 2, 3), d(10, 6)),
            s(d(10, 13), d(10, 13, 30)),
            s(d(10, 13, 30), d(10, 13, 35), .awake), // inside the nap: ignored
            s(d(10, 13, 35), d(10, 14)),
        ]
        let night = try #require(score(samples, day: d(10, 20))).night
        #expect(night.wakeUps == 1) // the gap between night and nap is not a wake-up either
        #expect(night.wakeUpMinutes == 3)
        #expect(night.asleepMinutes == 420 - 3 + 55) // naps still count for duration
        #expect(night.onset == d(9, 23))
        #expect(!night.isNapOnly)
    }

    @Test func napOnlyDayIsNotScored() {
        // S7b: a day without a real night shows "—" like a day without data; its nap isn't scored.
        let samples = [
            s(d(10, 13), d(10, 13, 30)),
            s(d(10, 13, 30), d(10, 13, 35), .awake),
            s(d(10, 13, 35), d(10, 14)),
        ]
        let day = d(10, 20)
        #expect(score(samples, day: day) == nil)
        #expect(SleepScoring.scores(forSleepDays: [day], samples: samples, calendar: cal).isEmpty)
    }

    // MARK: Sleep day

    @Test func sleepDayRunsFrom18YesterdayTo18Today() {
        // Ends 17:30 on the 10th: the 10th.
        let day = s(d(10, 10), d(10, 17, 30))
        #expect(score([day], day: d(10, 20)) != nil)
        #expect(score([day], day: d(11, 9)) == nil)
        // Ends 18:30 on the 10th: already the 11th's sleep.
        let evening = s(d(10, 14), d(10, 18, 30))
        #expect(score([evening], day: d(10, 20)) == nil)
        #expect(score([evening], day: d(11, 9)) != nil)
        // Last night is not tomorrow's.
        let lastNight = s(d(9, 22), d(10, 6))
        #expect(score([lastNight], day: d(11)) == nil)
    }

    @Test func longestSessionIsTheMainSleepForOnset() throws {
        let samples = [
            s(d(9, 19), d(9, 20)), // evening doze, > 2 h before the night
            s(d(9, 23), d(10, 6)),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.onset == d(9, 23))
        #expect(night.asleepMinutes == 480)
        #expect(night.wakeUps == 0)
        #expect(night.includesNap)
    }

    @Test func gapUpToTwoHoursStaysInOneSession() throws {
        let samples = [
            s(d(9, 22), d(9, 23)),
            s(d(10, 1), d(10, 6)), // exactly 2 h later: same session
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.onset == d(9, 22))
        #expect(night.asleepMinutes == 360)
        #expect(night.wakeUps == 0)
        #expect(!night.includesNap)
        let split = [samples[0], s(d(10, 1, 1), d(10, 6))]
        #expect(try #require(score(split, day: d(10, 9))).night.includesNap)
    }

    // MARK: Bedtime consistency

    @Test func noHistoryMeansFullBedtimeAndNoAverage() throws {
        let result = try #require(score([s(d(10, 2), d(10, 9))], day: d(10, 12)))
        #expect(result.night.averageOnsetMinutesAfterNoon == nil)
        #expect(result.night.bedtimeDeviationMinutes == nil)
        #expect(result.night.historyNights == 0)
        #expect(result.bedtimePoints == 30)
    }

    @Test func averageWrapsAroundMidnight() throws {
        // Onsets 23:30, 00:30, 00:00 → average 00:00 (720 min after noon).
        let samples = [
            s(d(6, 23, 30), d(7, 7)),
            s(d(8, 0, 30), d(8, 8)),
            s(d(9, 0, 0), d(9, 8)),
            s(d(10, 0, 45), d(10, 8)),
        ]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.averageOnsetMinutesAfterNoon == 720)
        #expect(night.onsetMinutesAfterNoon == 765)
        #expect(night.bedtimeDeviationMinutes == 45)
    }

    @Test func historyIsTheThirteenPreviousSleepDays() throws {
        // 14 days back (24 Feb) is outside the window; 13 days back (25 Feb) is inside.
        let samples = history(days: 24...24, month: 2, hour: 20)
            + history(days: 25...25, month: 2, hour: 23)
            + [s(d(9, 23, 30), d(10, 6, 30))]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.historyNights == 1)
        #expect(night.bedtimeDeviationMinutes == 30)
    }

    @Test func lateBedtimeCostsPoints() throws {
        let samples = history(days: 3...9, hour: 23) + [s(d(10, 1), d(10, 8))]
        let result = try #require(score(samples, day: d(10, 9)))
        #expect(result.night.bedtimeDeviationMinutes == 120)
        #expect(result.bedtimePoints == 9) // 30 - 0.2 * 105
    }

    @Test func earlyBedtimeCostsLess() throws {
        let samples = history(days: 3...9, hour: 23) + [s(d(9, 21), d(10, 4))]
        let result = try #require(score(samples, day: d(10, 9)))
        #expect(result.night.bedtimeDeviationMinutes == -120)
        #expect(result.bedtimePoints == 24) // 30 - 0.1 * 60
    }

    @Test func historyOnsetIsEachNightsMainSleep() throws {
        // A history day with an afternoon nap: its onset is still the night's.
        let samples = history(days: 8...9, hour: 23)
            + [s(d(9, 13), d(9, 14))]
            + [s(d(9, 23), d(10, 6))]
        let night = try #require(score(samples, day: d(10, 9))).night
        #expect(night.averageOnsetMinutesAfterNoon == 660)
        #expect(night.bedtimeDeviationMinutes == 0)
    }

    @Test func napOnlyDaysAreLeftOutOfTheAverage() throws {
        // Nights at 23:00 on the 7th and 8th, a 15:00 nap-only day on the 9th: the nap's onset is
        // not part of the 10th's average.
        let samples = history(days: 7...8, hour: 23)
            + [s(d(9, 15), d(9, 16, 30))]
            + [s(d(9, 23, 30), d(10, 6, 30))]
        let result = try #require(score(samples, day: d(10, 9)))
        #expect(result.night.historyNights == 2)
        #expect(result.night.averageOnsetMinutesAfterNoon == 660)
        #expect(result.night.bedtimeDeviationMinutes == 30)
        #expect(result.bedtimePoints == 27)

        // The nap-only day itself gets no score (S7b).
        #expect(score(samples, day: d(9, 20)) == nil)
    }

    @Test func napOnlyThresholdDecidesWhetherADayIsScored() throws {
        // Exactly 3 h is a real night (scored); 2 h 59 m is nap-only ("—") unless the threshold is lowered.
        #expect(score([s(d(10, 1), d(10, 4))], day: d(10, 9)) != nil)
        let short = [s(d(10, 1), d(10, 3, 59))]
        #expect(score(short, day: d(10, 9)) == nil)
        var config = SleepScoreConfig()
        config.minMainSleepForBedtimeHistory = 2 * 3600
        #expect(SleepScoring.score(forNightEndingOn: d(10, 9), samples: short, calendar: cal,
                                   config: config) != nil)
    }

    @Test func napOnlyThresholdIsTunable() throws {
        // Main sleep of exactly 3 h is a night; 2 h 59 m is nap-only.
        let threeHours = [s(d(9, 1), d(9, 4))]
            + [s(d(9, 23), d(10, 6))]
        #expect(try #require(score(threeHours, day: d(10, 9))).night.historyNights == 1)
        let shorter = [s(d(9, 1), d(9, 3, 59))]
            + [s(d(9, 23), d(10, 6))]
        #expect(try #require(score(shorter, day: d(10, 9))).night.historyNights == 0)
        var config = SleepScoreConfig()
        config.minMainSleepForBedtimeHistory = 2 * 3600
        let tuned = try #require(SleepScoring.score(forNightEndingOn: d(10, 9), samples: shorter,
                                                    calendar: cal, config: config))
        #expect(tuned.night.historyNights == 1)
    }

    // MARK: Batch

    @Test func batchScoresMatchSingleScores() {
        let samples = fullDay()
        let days = (0..<20).map { cal.date(byAdding: .day, value: -$0, to: d(17))! }
        let batch = SleepScoring.scores(forSleepDays: days, samples: samples, calendar: cal)
        for day in days {
            #expect(batch[cal.startOfDay(for: day)] == score(samples, day: day))
        }
        #expect(batch.count == 14) // 13 history nights + the 16th
    }

    @Test func meetsGoal() throws {
        let result = try #require(score([s(d(10, 0), d(10, 6))], day: d(10, 9)))
        #expect(result.meets(goal: result.total))
        #expect(!result.meets(goal: result.total + 1))
    }
}
