import Combine
import FuelyCore
import SwiftUI

/// Fuely's water drop: a round bulb with a soft, blunt tip. Original shape, also used as the clip
/// and mask of the water inside.
nonisolated struct WaterDropShape: Shape {
    /// Width ÷ height of the drop's frame.
    static let aspectRatio: CGFloat = 0.78

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height * 0.42)
        let centerX = rect.midX
        let bulbCenterY = rect.maxY - radius
        let top = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: centerX, y: top))
        // A horizontal tangent at the tip keeps it soft instead of a sharp point.
        path.addCurve(to: CGPoint(x: centerX + radius, y: bulbCenterY),
                      control1: CGPoint(x: centerX + radius * 0.16, y: top),
                      control2: CGPoint(x: centerX + radius, y: bulbCenterY - radius * 0.78))
        path.addArc(center: CGPoint(x: centerX, y: bulbCenterY), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addCurve(to: CGPoint(x: centerX, y: top),
                      control1: CGPoint(x: centerX - radius, y: bulbCenterY - radius * 0.78),
                      control2: CGPoint(x: centerX - radius * 0.16, y: top))
        path.closeSubpath()
        return path
    }

    /// The bulb's centre, where the percentage sits.
    static func bulbCenter(in size: CGSize) -> CGPoint {
        let radius = min(size.width / 2, size.height * 0.42)
        return CGPoint(x: size.width / 2, y: size.height - radius)
    }
}

/// The animated water drop on the Today card (DECISIONS T4–T4d): layered waves, bubbles, a splash
/// when a drink is logged, an opening rise and a once-a-day goal sparkle.
///
/// Battery (T4b, T4f): the waves are drawn by one `Canvas` inside a `TimelineView` at ≤ 30 fps,
/// computed from the timeline date (no per-frame state). The timeline pauses while the app isn't
/// active, the drop isn't on screen, Low Power Mode is on or Reduce Motion is on; ~10 s after the
/// last level change it calms to a low drift at ≤ 15 fps. Paused, it shows a still wave. What plays
/// under Low Power Mode / Reduce Motion and per source (Fuely log vs Health refresh, T4e) comes from
/// `DropMotionPolicy` in FuelyCore.
struct WaterDropView: View {
    /// Today's total ÷ goal; may exceed 1 (the drop stays full, the % keeps counting).
    var fraction: Double
    /// Height of the drop; the width follows `WaterDropShape.aspectRatio`.
    var height: CGFloat
    /// The model's pending opening-rise request (`AppModel.openingRiseRequestedAt`).
    var riseRequestedAt: Date?
    /// `AppModel.fuelyLogCount`: a change marks the next level rise as a drink logged in Fuely (T4e).
    var fuelyLogCount: Int
    var onRiseConsumed: () -> Void = {}
    /// Asks the model whether today's goal celebration is still due (and records it).
    var claimCelebration: () -> Bool = { false }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @State private var shownLevel: Double
    @State private var isVisible = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Last time the level moved: the waves are livelier for a while after it.
    @State private var activeSince = Date()
    @State private var isIdle = false
    @State private var splashStart: Date?
    @State private var impactCount = 0
    @State private var successCount = 0
    @State private var sparkleCount = 0

    init(fraction: Double, height: CGFloat, riseRequestedAt: Date? = nil, fuelyLogCount: Int = 0,
         onRiseConsumed: @escaping () -> Void = {}, claimCelebration: @escaping () -> Bool = { false }) {
        self.fraction = fraction
        self.height = height
        self.riseRequestedAt = riseRequestedAt
        self.fuelyLogCount = fuelyLogCount
        self.onRiseConsumed = onRiseConsumed
        self.claimCelebration = claimCelebration
        // Start empty when a rise is about to play, so the first frame never flashes full.
        let rising = WaterDropMotion.shouldStartPendingRise(requestedAt: riseRequestedAt, now: Date())
        _shownLevel = State(initialValue: rising ? 0 : Self.fillLevel(fraction))
    }

    private static func fillLevel(_ fraction: Double) -> Double {
        fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }

    private var policy: DropMotionPolicy { DropMotionPolicy(reduceMotion: reduceMotion, lowPower: isLowPower) }
    /// Reduce Motion or Low Power Mode: the waves stand still.
    private var isStill: Bool { !policy.animatesWaves }
    private var isPaused: Bool { isStill || scenePhase != .active || !isVisible }
    private var width: CGFloat { height * WaterDropShape.aspectRatio }
    private var size: CGSize { CGSize(width: width, height: height) }

    var body: some View {
        ZStack {
            DropGlass(size: size)
            TimelineView(.animation(minimumInterval: isIdle ? 1.0 / 15 : 1.0 / 30, paused: isPaused)) { timeline in
                DropWater(level: shownLevel, size: size, percent: FuelyFormat.percent(fraction),
                          motion: motion(at: timeline.date), palette: WaterPalette(colorScheme))
            }
            DropHighlight(size: size)
            SparkleBurst(trigger: sparkleCount, size: size)
        }
        .frame(width: width, height: height)
        .sensoryFeedback(.impact(weight: .light), trigger: impactCount)
        .sensoryFeedback(.success, trigger: successCount)
        .onAppear {
            isVisible = true
            startPendingRise()
            celebrateIfDue(after: .zero)
        }
        .onDisappear { isVisible = false }
        .onChange(of: riseRequestedAt) { startPendingRise() }
        // Total and log counter as one value: the model changes both in the same update for a Fuely
        // log, so a single callback sees whether this level change came with a new log (T4e).
        .onChange(of: LevelKey(fraction: fraction, logCount: fuelyLogCount)) { old, new in
            guard new.fraction != old.fraction else { return }
            levelChanged(from: old.fraction, to: new.fraction, fromFuelyLog: new.logCount != old.logCount)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // One state change ~11 s after the last level change: drop to the slow drift frame rate.
        .task(id: activeSince) {
            isIdle = false
            try? await Task.sleep(for: .seconds(DropMotion.calmEnd))
            if !Task.isCancelled { isIdle = true }
        }
    }

    /// Everything time-based for one frame, derived from the timeline date.
    private func motion(at date: Date) -> DropMotion {
        if isStill { return DropMotion.still(bubbles: policy.showsBubbles) }
        let sinceActive = date.timeIntervalSince(activeSince)
        let splashAge = splashStart.map { date.timeIntervalSince($0) }
        return DropMotion(time: date.timeIntervalSinceReferenceDate, sinceActive: sinceActive, splashAge: splashAge,
                          bubbles: true)
    }

    // MARK: Events

    /// The opening rise (T4a, T4g): only when this drop is on screen while the request is fresh, i.e.
    /// Today was showing when the app became active. A request made while Week was on top expires
    /// unplayed (`WaterDropMotion.pendingRiseLifetime`), so coming back from Week never plays it.
    private func startPendingRise() {
        guard isVisible, WaterDropMotion.shouldStartPendingRise(requestedAt: riseRequestedAt, now: Date()) else { return }
        onRiseConsumed()
        let target = Self.fillLevel(fraction)
        guard policy.playsOpeningRise else {
            shownLevel = target
            return
        }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { shownLevel = 0 }
        activeSince = Date()
        // Next run loop turn, so the empty drop is committed before the rise starts.
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 1.6, bounce: 0.12).delay(0.1)) { shownLevel = target }
        }
        celebrateIfDue(after: .seconds(1.4))
    }

    /// `fromFuelyLog`: the change came with a new Fuely log; anything else (Health refresh, undo,
    /// midnight) moves quietly (T4e).
    private func levelChanged(from old: Double, to new: Double, fromFuelyLog: Bool) {
        let target = Self.fillLevel(new)
        let rose = new > old
        let change = policy.levelChange(rose: rose, fromFuelyLog: fromFuelyLog, wasFull: Self.fillLevel(old) >= 1)
        if change.impactHaptic { impactCount += 1 }
        if change.splash { splashStart = Date() }
        if policy.animatesWaves { activeSince = Date() }
        let settle: Duration
        switch change.animation {
        case .none:
            shownLevel = target
            settle = .zero
        case .quickEase:
            withAnimation(.easeOut(duration: 0.35)) { shownLevel = target }
            settle = .seconds(0.35)
        case .smooth:
            withAnimation(.smooth(duration: 1.2)) { shownLevel = target }
            settle = .seconds(1.0)
        case .spring:
            withAnimation(.spring(duration: 1.5, bounce: 0.22)) { shownLevel = target }
            settle = .seconds(1.1)
        }
        // The goal celebration plays whichever source reached 100% (T4c).
        if rose { celebrateIfDue(after: settle) }
    }

    /// Success haptic + sparkle the first time today's total reaches the goal (T4c).
    private func celebrateIfDue(after delay: Duration) {
        guard isVisible, fraction >= 1, claimCelebration() else { return }
        Task {
            try? await Task.sleep(for: delay)
            successCount += 1
            if policy.showsSparkle { sparkleCount += 1 }
        }
    }
}

// MARK: - Motion

private struct LevelKey: Equatable {
    var fraction: Double
    var logCount: Int
}

/// Time inputs for one frame.
private struct DropMotion {
    /// Seconds; drives the wave phase and the bubbles.
    var time: Double
    /// Seconds since the level last moved.
    var sinceActive: Double
    /// Seconds since the last splash started, if any.
    var splashAge: Double?
    /// Off in Low Power Mode (T4f).
    var bubbles: Bool

    static let calmStart: Double = 8
    static let calmEnd: Double = 11
    static let splashDuration: Double = 0.9

    /// A pleasant still frame (Reduce Motion, Low Power Mode).
    static func still(bubbles: Bool) -> DropMotion {
        DropMotion(time: 1.35, sinceActive: .infinity, splashAge: nil, bubbles: bubbles)
    }

    /// Wave height multiplier: lively after a change, a gentle drift once idle, a slosh after a splash.
    var amplitude: Double {
        let calm = min(max((sinceActive - Self.calmStart) / (Self.calmEnd - Self.calmStart), 0), 1)
        var value = 1 - 0.55 * calm
        if let splashAge, splashAge >= 0 { value += 1.4 * exp(-splashAge * 2.2) }
        return value
    }
}

/// Water colors. Fixed deep tones (not the `ocean` ink, which turns light in dark mode) so the white
/// percentage always reads on the water.
private struct WaterPalette {
    var surface: Color
    var deep: Color
    var back: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            surface = Color(red: 0.10, green: 0.62, blue: 0.72)
            deep = Color(red: 0.04, green: 0.24, blue: 0.46)
            back = Color(red: 0.25, green: 0.80, blue: 0.86)
        } else {
            surface = Color(red: 0.00, green: 0.62, blue: 0.70)
            deep = Color(red: 0.04, green: 0.26, blue: 0.46)
            back = Color(red: 0.40, green: 0.84, blue: 0.88)
        }
    }
}

// MARK: - Layers

/// The empty drop: Liquid Glass on iOS 26+, a thin material before (DECISIONS P2).
private struct DropGlass: View {
    var size: CGSize

    var body: some View {
        let shape = WaterDropShape()
        Group {
            if #available(iOS 26, *) {
                Color.clear
                    .glassEffect(.clear.tint(FuelyColor.water.opacity(0.10)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(FuelyColor.water.opacity(0.08)) }
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            shape.fill(FuelyColor.water.opacity(0.18))
                .blur(radius: 12)
                .offset(y: 8)
        }
    }
}

/// Rim light and a curved specular highlight, on top of the water like light on glass.
private struct DropHighlight: View {
    var size: CGSize

    var body: some View {
        let shape = WaterDropShape()
        ZStack {
            shape.stroke(
                LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.08), FuelyColor.water.opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.5)
            // Curved specular highlight hugging the upper left of the bulb, plus a small glint.
            BulbArc(from: .degrees(196), to: .degrees(250), inset: 0.82)
                .stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.7)],
                                       startPoint: .bottomLeading, endPoint: .top),
                        style: StrokeStyle(lineWidth: size.width * 0.045, lineCap: .round))
                .blur(radius: 0.5)
            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: size.width * 0.04)
                .position(x: size.width * 0.40, y: size.height * 0.27)
                .blur(radius: 0.3)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An arc of a circle concentric with the drop's bulb (`inset` × its radius).
nonisolated private struct BulbArc: Shape {
    var from: Angle
    var to: Angle
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = WaterDropShape.bulbCenter(in: rect.size)
        let radius = min(rect.width / 2, rect.height * 0.42) * inset
        var path = Path()
        path.addArc(center: CGPoint(x: rect.minX + center.x, y: rect.minY + center.y), radius: radius,
                    startAngle: from, endAngle: to, clockwise: false)
        return path
    }
}

/// The water, bubbles, splash and the white half of the percentage, for one frame. Animatable on
/// `level`, so a spring on the level redraws the water without per-frame state.
private struct DropWater: View, Animatable {
    var level: Double
    var size: CGSize
    var percent: String
    var motion: DropMotion
    var palette: WaterPalette

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        let geometry = WaveGeometry(size: size, level: level, motion: motion)
        ZStack {
            Canvas { context, _ in
                context.clip(to: WaterDropShape().path(in: CGRect(origin: .zero, size: size)))
                draw(in: &context, geometry: geometry)
            }
            // The percentage twice: ocean ink on the glass, white where the water covers it.
            percentLabel.foregroundStyle(FuelyColor.ocean)
            percentLabel
                .foregroundStyle(.white)
                .mask {
                    Canvas { context, _ in
                        context.fill(geometry.frontPath(), with: .color(.black))
                    }
                }
        }
        .frame(width: size.width, height: size.height)
    }

    private var percentLabel: some View {
        let center = WaterDropShape.bulbCenter(in: size)
        return Text(percent)
            .font(.system(size: size.height * 0.17, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size.width * 0.74)
            .position(x: center.x, y: center.y + size.height * 0.01)
            .contentTransition(.numericText())
            .animation(.snappy, value: percent)
    }

    private func draw(in context: inout GraphicsContext, geometry: WaveGeometry) {
        guard level > 0.001 else { return }
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(geometry.backPath(), with: .color(palette.back.opacity(0.55)))
        context.fill(geometry.frontPath(),
                     with: .linearGradient(Gradient(colors: [palette.surface, palette.deep]),
                                           startPoint: CGPoint(x: bounds.midX, y: geometry.surfaceY),
                                           endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))
        drawBubbles(in: &context, geometry: geometry)
        drawSplash(in: &context, geometry: geometry)
    }

    /// A handful of small bubbles rising from the bottom and fading out under the surface.
    private func drawBubbles(in context: inout GraphicsContext, geometry: WaveGeometry) {
        let depth = size.height - geometry.surfaceY
        guard motion.bubbles, depth > size.height * 0.12 else { return }
        let textCenterY = WaterDropShape.bulbCenter(in: size).y
        for bubble in Bubble.all {
            let progress = (motion.time / bubble.period + bubble.offset).truncatingRemainder(dividingBy: 1)
            let y = size.height * 0.97 - progress * (depth - size.height * 0.03)
            let x = size.width * bubble.x + sin(motion.time * 2.1 + bubble.offset * 9) * size.width * 0.018
            let radius = size.width * bubble.radius
            // Fade out under the surface and while passing behind the percentage.
            let textBand = abs(y - textCenterY) / (size.height * 0.13)
            let fade = min(progress / 0.12, 1) * min((1 - progress) / 0.25, 1) * min(max(textBand - 0.6, 0) * 2.5, 1)
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.16 * fade)))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.55 * fade)), lineWidth: 0.8)
        }
    }

    /// A few droplets thrown up from the surface, falling back under gravity.
    private func drawSplash(in context: inout GraphicsContext, geometry: WaveGeometry) {
        guard let age = motion.splashAge, age >= 0, age < DropMotion.splashDuration else { return }
        let fade = 1 - age / DropMotion.splashDuration
        for drop in SplashDroplet.all {
            let x = size.width * (0.5 + drop.x + drop.vx * age)
            let y = geometry.surfaceY - size.height * (drop.vy * age - 2.2 * age * age)
            let radius = size.width * drop.radius
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(palette.surface.opacity(0.9 * fade)))
        }
    }
}

/// The two layered waves for one frame (parallax: different speed, length, height and phase).
private struct WaveGeometry {
    var size: CGSize
    var level: Double
    var motion: DropMotion

    private var maxAmplitude: CGFloat { size.height * 0.03 }
    private var amplitude: CGFloat {
        // Calmer near empty and full, where big waves look odd in the narrow tip and bottom.
        let edge = min(level / 0.08, (1 - level) / 0.06, 1)
        return maxAmplitude * CGFloat(motion.amplitude * max(edge, 0.25))
    }

    /// The mean surface height: below the bottom when empty, above the tip when full.
    var surfaceY: CGFloat {
        let travel = size.height + maxAmplitude * 4
        return size.height + maxAmplitude * 2 - CGFloat(level) * travel
    }

    func frontPath() -> Path {
        wave(length: size.width * 0.95, speed: -1.25, height: amplitude, phase: 0, lift: 0)
    }

    func backPath() -> Path {
        wave(length: size.width * 1.35, speed: 0.8, height: amplitude * 0.85, phase: 2.1, lift: maxAmplitude * 0.6)
    }

    private func wave(length: CGFloat, speed: Double, height: CGFloat, phase: Double, lift: CGFloat) -> Path {
        var path = Path()
        let steps = 28
        let baseline = surfaceY - lift
        let shift = motion.time * speed + phase
        for step in 0...steps {
            let x = size.width * CGFloat(step) / CGFloat(steps)
            let y = baseline + height * CGFloat(sin(Double(x / length) * 2 * .pi + shift))
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

private struct Bubble {
    var x: Double, radius: Double, period: Double, offset: Double

    static let all = [
        Bubble(x: 0.34, radius: 0.022, period: 4.2, offset: 0.00),
        Bubble(x: 0.58, radius: 0.016, period: 3.4, offset: 0.37),
        Bubble(x: 0.45, radius: 0.012, period: 2.9, offset: 0.71),
        Bubble(x: 0.68, radius: 0.020, period: 4.8, offset: 0.55),
        Bubble(x: 0.27, radius: 0.013, period: 3.7, offset: 0.18),
    ]
}

/// Start offset from the centre (fraction of the width), sideways speed (widths/s), upward speed
/// (heights/s) and radius (fraction of the width).
private struct SplashDroplet {
    var x: Double, vx: Double, vy: Double, radius: Double

    static let all = [
        SplashDroplet(x: -0.05, vx: -0.30, vy: 0.78, radius: 0.040),
        SplashDroplet(x: 0.04, vx: 0.26, vy: 0.86, radius: 0.034),
        SplashDroplet(x: 0.00, vx: -0.04, vy: 1.00, radius: 0.028),
        SplashDroplet(x: 0.09, vx: 0.44, vy: 0.60, radius: 0.026),
        SplashDroplet(x: -0.10, vx: -0.46, vy: 0.56, radius: 0.024),
        SplashDroplet(x: 0.02, vx: 0.10, vy: 0.70, radius: 0.020),
    ]
}

// MARK: - Celebration

/// Four-point sparkles that pop around the drop once (T4c).
private struct SparkleBurst: View {
    var trigger: Int
    var size: CGSize

    private static let spots: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (-0.66, -0.16, 1.0), (0.58, -0.32, 0.8), (0.70, 0.18, 1.15), (-0.62, 0.30, 0.75),
        (0.20, -0.58, 0.9), (-0.26, -0.50, 0.65), (0.40, 0.46, 0.7),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.spots.indices, id: \.self) { index in
                let spot = Self.spots[index]
                SparkleShape()
                    .fill(index.isMultiple(of: 2) ? FuelyColor.water : FuelyColor.action)
                    .frame(width: 24 * spot.scale, height: 24 * spot.scale)
                    .keyframeAnimator(initialValue: SparkleFrame(), trigger: trigger) { content, frame in
                        content
                            .scaleEffect(frame.scale)
                            .rotationEffect(.degrees(frame.rotation))
                            .opacity(frame.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(0, duration: Double(index) * 0.07)
                            SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                            CubicKeyframe(0.2, duration: 0.6)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: Double(index) * 0.07)
                            LinearKeyframe(1, duration: 0.12)
                            LinearKeyframe(1, duration: 0.45)
                            LinearKeyframe(0, duration: 0.4)
                        }
                        KeyframeTrack(\.rotation) {
                            LinearKeyframe(0, duration: Double(index) * 0.07)
                            LinearKeyframe(90, duration: 0.97)
                        }
                    }
                    .offset(x: size.width * spot.x, y: size.height * spot.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SparkleFrame {
    var scale: CGFloat = 0
    var opacity: Double = 0
    var rotation: Double = 0
}

nonisolated private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.22
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
        path.closeSubpath()
        return path
    }
}

#Preview("Drops") {
    HStack(spacing: FuelySpacing.l) {
        WaterDropView(fraction: 0.02, height: 150)
        WaterDropView(fraction: 0.52, height: 150)
        WaterDropView(fraction: 1.3, height: 150)
    }
    .padding()
    .fuelyCard(tint: FuelyColor.water)
    .padding()
    .frame(maxHeight: .infinity)
    .fuelyScreenBackground()
}
