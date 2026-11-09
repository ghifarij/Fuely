import Foundation

/// When the Today water drop plays its one-off animations (DECISIONS T4a, T4c). Pure rules, so the
/// view only asks and never decides on its own.
public enum WaterDropMotion {
    /// Coming back to the foreground after at least this long away replays the opening rise (T4a).
    public static let riseAfterBackground: TimeInterval = 30 * 60

    /// How long an opening-rise request stays valid for the drop to pick it up (T4g): the rise plays
    /// only if Today is on screen when the app becomes active. The short window covers the launch
    /// race (the scene can become active just before or after the drop first appears); a request
    /// made while Week was showing expires, so coming back from Week later never plays it.
    public static let pendingRiseLifetime: TimeInterval = 2

    /// Whether becoming active should play the rise from empty: always on a cold launch, otherwise
    /// only after ≥ 30 min in the background. An app that never went to the background (e.g. a
    /// Control Center pull, a sheet, coming back from Week) never replays it.
    public static func shouldPlayOpeningRise(isColdLaunch: Bool, backgroundedAt: Date?, now: Date) -> Bool {
        if isColdLaunch { return true }
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= riseAfterBackground
    }

    /// Whether a rise requested at `requestedAt` should still start now (see `pendingRiseLifetime`).
    public static func shouldStartPendingRise(requestedAt: Date?, now: Date) -> Bool {
        guard let requestedAt else { return false }
        let age = now.timeIntervalSince(requestedAt)
        return age >= 0 && age < pendingRiseLifetime
    }

    /// Whether to play the once-a-day "goal reached" sparkle and success haptic (T4c): today's total
    /// is at least the goal and no celebration happened yet on today's calendar day. Opening the app
    /// above goal on a day that was never celebrated celebrates once.
    public static func shouldCelebrate(fraction: Double, lastCelebratedDay: Date?, now: Date,
                                       calendar: Calendar) -> Bool {
        guard fraction.isFinite, fraction >= 1 else { return false }
        guard let lastCelebratedDay else { return true }
        return !calendar.isDate(lastCelebratedDay, inSameDayAs: now)
    }
}

/// What the drop may play under the current system settings (DECISIONS T4b, T4e, T4f).
/// Reduce Motion: no motion at all, haptics kept. Low Power Mode: no continuous or decorative motion
/// (idle waves, bubbles, splash, sparkle, opening rise), but a drink logged in Fuely still gets a
/// short level change and the haptics. With both on, the stricter rule wins.
public struct DropMotionPolicy: Sendable, Hashable {
    public var reduceMotion: Bool
    public var lowPower: Bool

    public init(reduceMotion: Bool, lowPower: Bool) {
        self.reduceMotion = reduceMotion
        self.lowPower = lowPower
    }

    /// How the level moves to a new value.
    public enum LevelAnimation: Sendable, Hashable {
        /// Jump, no animation.
        case none
        /// Short ease (≤ 0.4 s, no spring): a Fuely log in Low Power Mode.
        case quickEase
        /// Calm ease without bounce: water from other apps, or the level going down.
        case smooth
        /// The ~1.5 s spring of a drink logged in Fuely.
        case spring
    }

    /// What a level change plays.
    public struct LevelChange: Sendable, Hashable {
        public var animation: LevelAnimation
        /// Droplets thrown up from the surface.
        public var splash: Bool
        /// Light impact haptic.
        public var impactHaptic: Bool
    }

    /// The idle waves and bubbles move (the timeline runs while visible and active).
    public var animatesWaves: Bool { !reduceMotion && !lowPower }
    /// Bubbles are drawn (still ones with Reduce Motion, none in Low Power Mode).
    public var showsBubbles: Bool { !lowPower }
    /// The opening rise from empty (T4a).
    public var playsOpeningRise: Bool { animatesWaves }
    /// The goal sparkle (T4c); its success haptic always plays.
    public var showsSparkle: Bool { animatesWaves }

    /// - Parameters:
    ///   - rose: the total went up.
    ///   - fromFuelyLog: the change came from a drink logged in Fuely (not a Health refresh, T4e).
    ///   - wasFull: the drop was already full, so a splash would be hidden.
    public func levelChange(rose: Bool, fromFuelyLog: Bool, wasFull: Bool) -> LevelChange {
        let logged = rose && fromFuelyLog
        let animation: LevelAnimation
        if reduceMotion {
            animation = .none
        } else if lowPower {
            animation = logged ? .quickEase : .none
        } else {
            animation = logged ? .spring : .smooth
        }
        return LevelChange(animation: animation, splash: logged && animatesWaves && !wasFull, impactHaptic: logged)
    }
}
