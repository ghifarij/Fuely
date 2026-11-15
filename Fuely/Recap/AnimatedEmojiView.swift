import Combine
import FuelyCore
import SwiftUI

/// The recap's one big emoji (DECISIONS WR6): the system emoji as text, moved with native keyframe
/// animations. One entrance (~1 s) with a soft haptic, then a slow, gentle loop.
///
/// Still (no motion at all) under Reduce Motion and Low Power Mode, like the water drop (T4b, T4f);
/// the loop also stops while the app isn't active.
struct AnimatedEmojiView: View {
    var mood: WeeklyRecap.Mood
    /// Font size of the emoji in points. The view's frame is a little larger, so the motion has room.
    var size: CGFloat = 104
    /// Seconds to wait (hidden) before the entrance, so it isn't lost in the screen's own transition.
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var hasStarted = false
    @State private var hasEntered = false
    @State private var hapticCount = 0

    private var isStill: Bool { reduceMotion || isLowPower }

    var body: some View {
        Group {
            if isStill {
                emoji
            } else if !hasStarted {
                emoji.hidden()
            } else if !hasEntered {
                emoji.keyframeAnimator(initialValue: EmojiMotion.entranceStart(mood)) { content, pose in
                    content.emojiPose(pose, size: size)
                } keyframes: { _ in
                    EmojiMotion.entrance(mood).keyframes
                }
            } else if scenePhase == .active {
                emoji.keyframeAnimator(initialValue: EmojiPose(), repeating: true) { content, pose in
                    content.emojiPose(pose, size: size)
                } keyframes: { _ in
                    EmojiMotion.loop(mood).keyframes
                }
            } else {
                emoji
            }
        }
        .frame(width: size * 1.7, height: size * 1.3)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: hapticCount)
        .task {
            guard !hasEntered else { return }
            if delay > 0, !isStill { try? await Task.sleep(for: .seconds(delay)) }
            hasStarted = true
            hapticCount += 1
            // The entrance keyframes end with a short hold at rest; switch to the loop inside it.
            try? await Task.sleep(for: .seconds(EmojiMotion.entranceDuration))
            hasEntered = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
    }

    private var emoji: some View {
        Text(mood.emoji)
            .font(.system(size: size))
            .fixedSize()
    }
}

// MARK: - Pose

/// Everything the animations move. The default is the emoji at rest.
private struct EmojiPose {
    var scale: CGFloat = 1
    /// Vertical squash/stretch (1 = none), anchored at the bottom.
    var stretch: CGFloat = 1
    /// Degrees, around the bottom centre.
    var rotation: CGFloat = 0
    /// Offsets as a fraction of the emoji size.
    var x: CGFloat = 0
    var y: CGFloat = 0
    var opacity: CGFloat = 1
}

private extension View {
    nonisolated func emojiPose(_ pose: EmojiPose, size: CGFloat) -> some View {
        self
            .scaleEffect(x: 1, y: pose.stretch, anchor: .bottom)
            .scaleEffect(pose.scale)
            .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
            .offset(x: pose.x * size, y: pose.y * size)
            .opacity(pose.opacity)
    }
}

// MARK: - Motion

/// One keyframe: ease to `value` over `duration` seconds, or spring to it (`bounce` > 0).
private struct Step {
    var value: CGFloat
    var duration: Double
    var bounce: Double = 0

    init(_ value: CGFloat, _ duration: Double) {
        self.value = value
        self.duration = duration
    }

    /// A spring that keeps wobbling around `value` for `duration` seconds.
    static func spring(_ value: CGFloat, _ duration: Double, bounce: Double) -> Step {
        var step = Step(value, duration)
        step.bounce = bounce
        return step
    }
}

/// The keyframe tracks of one animation. A track left empty stays at rest.
private struct EmojiMotion {
    var scale: [Step] = []
    var stretch: [Step] = []
    var rotation: [Step] = []
    var x: [Step] = []
    var y: [Step] = []
    var opacity: [Step] = []

    /// Seconds until the loop takes over.
    static let entranceDuration: Double = 1.3
    /// Extra time the entrance holds its last (rest) pose, so the hand-over can't show a jump.
    private static let entranceHold: Double = 0.4

    @KeyframesBuilder<EmojiPose> var keyframes: some Keyframes<EmojiPose> {
        KeyframeTrack(\EmojiPose.scale) { Self.track(scale, rest: 1) }
        KeyframeTrack(\EmojiPose.stretch) { Self.track(stretch, rest: 1) }
        KeyframeTrack(\EmojiPose.rotation) { Self.track(rotation, rest: 0) }
        KeyframeTrack(\EmojiPose.x) { Self.track(x, rest: 0) }
        KeyframeTrack(\EmojiPose.y) { Self.track(y, rest: 0) }
        KeyframeTrack(\EmojiPose.opacity) { Self.track(opacity, rest: 1) }
    }

    @KeyframeTrackContentBuilder<CGFloat>
    private static func track(_ steps: [Step], rest: CGFloat) -> some KeyframeTrackContent<CGFloat> {
        for step in steps.isEmpty ? [Step(rest, 0.1)] : steps {
            if step.bounce > 0 {
                SpringKeyframe(step.value, duration: step.duration, spring: Spring(duration: 0.3, bounce: step.bounce))
            } else {
                CubicKeyframe(step.value, duration: step.duration)
            }
        }
    }

    // MARK: Entrances (~1 s, all end at rest)

    /// Where the entrance starts from.
    static func entranceStart(_ mood: WeeklyRecap.Mood) -> EmojiPose {
        switch mood {
        case .allStrong: EmojiPose(scale: 0.2, rotation: -24, opacity: 0)
        case .twoStrong: EmojiPose(y: -0.8, opacity: 0)
        case .oneStrong: EmojiPose(scale: 0.7, y: 0.14, opacity: 0)
        case .mixed: EmojiPose(scale: 0.5, rotation: -16, opacity: 0)
        case .low: EmojiPose(scale: 0.8, rotation: -16, y: -0.4, opacity: 0)
        case .notEnoughData: EmojiPose(x: -0.45, opacity: 0)
        }
    }

    static func entrance(_ mood: WeeklyRecap.Mood) -> EmojiMotion {
        var motion: EmojiMotion
        switch mood {
        case .allStrong:
            // Pop in with an overshoot and a small settle.
            motion = EmojiMotion(scale: [Step(1.28, 0.36), Step(0.93, 0.22), Step(1.05, 0.2), Step(1, 0.22)],
                                 rotation: [Step(8, 0.36), Step(-4, 0.22), Step(0, 0.42)],
                                 opacity: [Step(1, 0.18)])
        case .twoStrong:
            // Drop in from above, land with a springy squash, one small rebound.
            motion = EmojiMotion(stretch: [Step(1.08, 0.24), Step(0.7, 0.07), .spring(1, 0.36, bounce: 0.62), Step(0.84, 0.06),
                                           .spring(1, 0.5, bounce: 0.6)],
                                 y: [Step(0, 0.28), Step(0, 0.07), Step(-0.2, 0.17), Step(0, 0.17)],
                                 opacity: [Step(1, 0.12)])
        case .oneStrong:
            // Rise in softly, then one clear nod.
            motion = EmojiMotion(scale: [Step(1, 0.5)],
                                 stretch: [Step(1, 0.55), Step(0.86, 0.2), Step(1, 0.3)],
                                 rotation: [Step(0, 0.55), Step(7, 0.2), Step(0, 0.3)],
                                 y: [Step(0, 0.5), Step(0, 0.05), Step(0.14, 0.2), Step(0, 0.3)],
                                 opacity: [Step(1, 0.35)])
        case .mixed:
            // Scale in with a wobble that dies down.
            motion = EmojiMotion(scale: [Step(1, 0.35)],
                                 rotation: [Step(13, 0.24), Step(-10, 0.2), Step(7, 0.18), Step(-4, 0.18), Step(0, 0.2)],
                                 opacity: [Step(1, 0.2)])
        case .low:
            // Drifts down like a head nodding off, sways once and settles.
            motion = EmojiMotion(scale: [Step(1, 0.7)],
                                 rotation: [Step(9, 0.55), Step(-5, 0.4), Step(0, 0.35)],
                                 y: [Step(0.05, 0.55), Step(0, 0.4)],
                                 opacity: [Step(1, 0.4)])
        case .notEnoughData:
            // Slide in from the side, glance past the centre and settle.
            motion = EmojiMotion(rotation: [Step(5, 0.4), Step(-3, 0.28), Step(0, 0.32)],
                                 x: [Step(0.12, 0.4), Step(-0.07, 0.28), Step(0, 0.32)],
                                 opacity: [Step(1, 0.25)])
        }
        // Stay at rest a little longer than the hand-over to the loop needs.
        let length = motion.opacity.reduce(0) { $0 + $1.duration }
        motion.opacity.append(Step(1, entranceDuration + entranceHold - length))
        return motion
    }

    // MARK: Loops (slow and small, start and end at rest)

    static func loop(_ mood: WeeklyRecap.Mood) -> EmojiMotion {
        switch mood {
        case .allStrong:
            // A double pulse, then a rest. 3.0 s.
            EmojiMotion(scale: [Step(1, 1.1), Step(1.1, 0.32), Step(1, 0.32), Step(1.06, 0.28), Step(1, 0.38), Step(1, 0.6)])
        case .twoStrong:
            // Crouch, hop, land with a springy squash, then a rest. 2.9 s.
            EmojiMotion(stretch: [Step(1, 0.9), Step(0.88, 0.14), Step(1.08, 0.2), Step(1.04, 0.3), Step(0.76, 0.07),
                                  .spring(1, 0.6, bounce: 0.62), Step(1, 0.69)],
                        y: [Step(0, 1.04), Step(-0.26, 0.26), Step(0, 0.24), Step(0, 1.36)])
        case .oneStrong:
            // Two clear nods, then a longer rest. 3.4 s.
            EmojiMotion(stretch: [Step(1, 1.3), Step(0.86, 0.22), Step(1, 0.28), Step(0.9, 0.2), Step(1, 0.28), Step(1, 1.12)],
                        rotation: [Step(0, 1.3), Step(7, 0.22), Step(0, 0.28), Step(5, 0.2), Step(0, 0.28), Step(0, 1.12)],
                        y: [Step(0, 1.3), Step(0.15, 0.22), Step(0, 0.28), Step(0.1, 0.2), Step(0, 0.28), Step(0, 1.12)])
        case .mixed:
            // A sheepish wobble that dies down. 3.2 s.
            EmojiMotion(rotation: [Step(0, 0.9), Step(-9, 0.3), Step(8, 0.4), Step(-5, 0.34), Step(3, 0.3), Step(0, 0.3),
                                   Step(0, 0.66)])
        case .low:
            // Deep, slow breathing: swells and tips back, then sinks. 4.6 s.
            EmojiMotion(scale: [Step(1.16, 2.0), Step(1, 2.6)],
                        rotation: [Step(-7, 2.0), Step(0, 2.6)],
                        y: [Step(-0.06, 2.0), Step(0.02, 1.6), Step(0, 1.0)])
        case .notEnoughData:
            // Look left, hold, look right, hold, back. 4.2 s.
            EmojiMotion(rotation: [Step(0, 0.7), Step(-5, 0.36), Step(-5, 0.7), Step(5, 0.52), Step(5, 0.7), Step(0, 0.42),
                                   Step(0, 0.8)],
                        x: [Step(0, 0.7), Step(-0.12, 0.36), Step(-0.12, 0.7), Step(0.12, 0.52), Step(0.12, 0.7),
                            Step(0, 0.42), Step(0, 0.8)])
        }
    }
}

#if DEBUG
#Preview("Six moods") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FuelySpacing.l) {
        ForEach(WeeklyRecap.Mood.allCases, id: \.self) { mood in
            AnimatedEmojiView(mood: mood, size: 80)
        }
    }
    .padding()
    .frame(maxHeight: .infinity)
    .fuelyScreenBackground()
}
#endif
