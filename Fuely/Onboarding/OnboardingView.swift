import FuelyCore
import SwiftUI

/// First-launch onboarding (DECISIONS O1, height dropped per W1/W2):
/// Welcome → Health → Body (weight) → Water goal → Drinking window → Workout goal → Sleep goal →
/// Notifications → Widget tip. Every step saves through `AppModel.updateSettings`, so leaving
/// half-way keeps what was entered. Everything is editable later in Settings.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, health, body, waterGoal, drinkingWindow, workout, sleep, notifications, widgetTip
    }

    @Environment(AppModel.self) private var model
    @State private var step: Step
    @State private var draft = FuelySettings.default
    @State private var weightText = ""
    /// The user changed the water goal by hand: stop following the weight suggestion.
    @State private var waterGoalEdited = false
    @State private var isWorking = false
    @State private var movingForward = true
    @FocusState private var weightFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool

    init(initialStep: Step = .welcome) {
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        // A navigation container only so the keyboard toolbar (Done) shows; the bar stays hidden.
        NavigationStack {
            page
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: FuelySpacing.l) {
                    content
                }
                .padding(.horizontal, FuelySpacing.l)
                .padding(.top, FuelySpacing.m)
                .padding(.bottom, FuelySpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            bottomButtons
        }
        .fuelyScreenBackground()
        .onAppear { loadDraft() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: FuelySpacing.s) {
            Button {
                go(to: Step(rawValue: step.rawValue - 1))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome || isWorking)

            if step != .welcome {
                StepProgress(current: step.rawValue, total: Step.allCases.count - 1)
            } else {
                Spacer()
            }

            Button("Skip") { skip() }
                .font(FuelyFont.body)
                .frame(minWidth: 44, minHeight: 44)
                .opacity(isSkippable ? 1 : 0)
                .disabled(!isSkippable || isWorking)
                .accessibilityHidden(!isSkippable)
        }
        .tint(FuelyColor.ocean)
        .padding(.horizontal, FuelySpacing.xs)
        .padding(.top, FuelySpacing.xs)
    }

    private var bottomButtons: some View {
        VStack(spacing: FuelySpacing.xs) {
            Button { primaryAction() } label: {
                Group {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryTitle)
                    }
                }
                .font(FuelyFont.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            .fuelyProminentButton()
            .controlSize(.large)
            .tint(FuelyColor.action)
            .disabled(isWorking || !canContinue)
        }
        .padding(.horizontal, FuelySpacing.l)
        .padding(.bottom, FuelySpacing.m)
        .padding(.top, FuelySpacing.xs)
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .health: health
        case .body: bodyStep
        case .waterGoal: waterGoal
        case .drinkingWindow: drinkingWindow
        case .workout: workout
        case .sleep: sleep
        case .notifications: notifications
        case .widgetTip: widgetTip
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            Image(systemName: "drop.fill")
                .font(.system(size: 64))
                .foregroundStyle(FuelyColor.water.gradient)
                .frame(maxWidth: .infinity)
                .padding(.top, FuelySpacing.xl)
                .accessibilityHidden(true)
            StepHeader(title: "Welcome to Fuely",
                       message: "Fuel your day: water, sleep and workouts in one calm place.",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.m) {
                FeatureRow(icon: "drop.fill", color: FuelyColor.water, title: "Water",
                           detail: "Log a drink in a tap and stay on pace through the day.")
                FeatureRow(icon: "moon.zzz.fill", color: FuelyColor.sleep, title: "Sleep",
                           detail: "A nightly sleep score from your Apple Watch data.")
                FeatureRow(icon: "figure.run", color: FuelyColor.workout, title: "Workouts",
                           detail: "A weekly goal that counts every workout you record.")
            }
            .fuelyCard()
        }
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            StepIcon(systemImage: "heart.fill", color: .pink)
            StepHeader(title: "Connect Apple Health",
                       message: "Fuely reads your sleep and workouts, and saves the water you log so other apps see it too.",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.s) {
                PermissionRow(icon: "drop.fill", color: FuelyColor.water, text: "Water: read and write")
                PermissionRow(icon: "moon.zzz.fill", color: FuelyColor.sleep, text: "Sleep: read only")
                PermissionRow(icon: "figure.run", color: FuelyColor.workout, text: "Workouts: read only")
            }
            .fuelyCard()
            Text("Your data stays on your iPhone and in Apple Health. You can change access anytime in Settings.")
                .font(FuelyFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            StepIcon(systemImage: "scalemass.fill", color: FuelyColor.ocean)
            StepHeader(title: "Your weight",
                       message: "Fuely uses it to suggest a daily water goal (35 ml per kg). It isn't read from or saved to Apple Health.",
                       focus: $titleFocused)
            WeightField(text: $weightText, focus: $weightFocused)
                .font(FuelyFont.body)
                .fuelyCard()
            if let weight = SettingsLimits.parseWeight(weightText) {
                Label("Suggested goal: \(FuelyFormat.water(suggestion(for: weight)))", systemImage: "sparkles")
                    .font(FuelyFont.detail)
                    .foregroundStyle(FuelyColor.ocean)
            }
        }
    }

    private var waterGoal: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            StepIcon(systemImage: "drop.fill", color: FuelyColor.water)
            StepHeader(title: "Daily water goal",
                       message: "Workouts don't change it, and you can go past 100%.",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.s) {
                HStack(alignment: .center) {
                    Text(FuelyFormat.water(draft.waterGoalML))
                        .font(FuelyFont.hero)
                        .monospacedDigit()
                        .foregroundStyle(FuelyColor.ocean)
                        .contentTransition(.numericText(value: Double(draft.waterGoalML)))
                        .accessibilityHidden(true)
                    Spacer(minLength: FuelySpacing.s)
                    Stepper("Daily water goal", value: waterGoalBinding, in: SettingsLimits.waterGoalML,
                            step: SettingsLimits.waterGoalStepML)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityValue(FuelyFormat.waterSpoken(draft.waterGoalML))
                }
                .animation(.snappy, value: draft.waterGoalML)
                suggestionFooter
            }
            .fuelyCard(tint: FuelyColor.water)
        }
    }

    @ViewBuilder
    private var suggestionFooter: some View {
        if let suggested = draft.suggestedWaterGoalML, let weight = draft.weightKG {
            Divider()
            HStack {
                Text("Suggested for \(SettingsCopy.weight(weight)): \(FuelyFormat.water(suggested))")
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: FuelySpacing.xs)
                if suggested != draft.waterGoalML {
                    Button("Use") {
                        draft.waterGoalML = suggested
                        waterGoalEdited = false
                    }
                    .font(FuelyFont.detail.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Use suggested goal")
                }
            }
        } else {
            Text("Add your weight for a personal suggestion. \(FuelyFormat.water(FuelySettings.default.waterGoalML)) is a good start.")
                .font(FuelyFont.detail)
                .foregroundStyle(.secondary)
        }
    }

    private var drinkingWindow: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            StepIcon(systemImage: "clock.fill", color: FuelyColor.water)
            StepHeader(title: "When do you drink?",
                       message: "Your pace runs across this window, so hours asleep never count against you.",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.s) {
                DrinkingWindowPickers(window: $draft.drinkingWindow)
                Divider()
                Text("\(SettingsCopy.windowLength(draft.drinkingWindow)) drinking window")
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
            }
            .font(FuelyFont.body)
            .fuelyCard(tint: FuelyColor.water)
        }
    }

    private var workout: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            StepIcon(systemImage: "figure.run", color: FuelyColor.workout)
            StepHeader(title: "Weekly workout goal",
                       message: "Every workout type counts. Minutes on the same day add up, Monday to Sunday.",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.s) {
                ValueStepper(title: "Minimum per day", value: $draft.workoutGoal.minMinutesPerDay,
                             range: SettingsLimits.workoutMinutes, step: SettingsLimits.workoutMinutesStep,
                             format: { SettingsFormat.minutes($0) }, spokenFormat: { FuelyFormat.count($0, "minute") })
                Divider()
                ValueStepper(title: "Days per week", value: $draft.workoutGoal.daysPerWeek,
                             range: SettingsLimits.workoutDaysPerWeek, format: { SettingsFormat.days($0) })
            }
            .font(FuelyFont.body)
            .fuelyCard(tint: FuelyColor.workout)
        }
    }

    private var sleep: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            StepIcon(systemImage: "moon.zzz.fill", color: FuelyColor.sleep)
            StepHeader(title: "Sleep goal",
                       message: "Fuely scores each night from your Watch data: duration, bedtime consistency and interruptions.",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.s) {
                ValueStepper(title: "Score of at least", value: $draft.sleepGoalScore,
                             range: SettingsLimits.sleepGoal, step: SettingsLimits.sleepGoalStep,
                             format: { "\($0)" })
                Divider()
                Text("Wear your Watch to bed to get a score. Nights without data show “—” and don't count.")
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
            }
            .font(FuelyFont.body)
            .fuelyCard(tint: FuelyColor.sleep)
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            StepIcon(systemImage: "bell.badge.fill", color: FuelyColor.nudge)
            StepHeader(title: "Gentle reminders",
                       message: "Fuely only nudges you when you fall behind. Never more than needed.",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.m) {
                FeatureRow(icon: "drop.fill", color: FuelyColor.water, title: "Water",
                           detail: "At most 2 a day, only when you're behind pace.")
                FeatureRow(icon: "figure.run", color: FuelyColor.workout, title: "Workouts",
                           detail: "At most 1 a morning, only when your week needs it.")
            }
            .fuelyCard()
        }
    }

    private var widgetTip: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.l) {
            LockScreenMock()
                .frame(maxWidth: .infinity)
            StepHeader(title: "Add Fuely to your Lock Screen",
                       message: "See water, sleep and workouts at a glance, and log water with (+).",
                       focus: $titleFocused)
            VStack(alignment: .leading, spacing: FuelySpacing.s) {
                TipRow(number: 1, text: "Touch and hold your Lock Screen, then tap Customize.")
                TipRow(number: 2, text: "Choose Lock Screen and tap the widget area below the clock.")
                TipRow(number: 3, text: "Pick a Fuely widget, then tap Done.")
            }
            .fuelyCard()
        }
    }

    // MARK: Logic

    private var isSkippable: Bool {
        switch step {
        case .health, .body, .notifications: true
        default: false
        }
    }

    private var canContinue: Bool {
        step != .body || weightText.isEmpty || SettingsLimits.parseWeight(weightText) != nil
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .health: "Connect Apple Health"
        case .notifications: "Allow notifications"
        case .widgetTip: "Start fueling"
        default: "Continue"
        }
    }

    private var waterGoalBinding: Binding<Int> {
        Binding(get: { draft.waterGoalML }, set: { draft.waterGoalML = $0; waterGoalEdited = true })
    }

    private func suggestion(for weight: Double) -> Int {
        var settings = draft
        settings.weightKG = weight
        return settings.suggestedWaterGoalML ?? FuelySettings.default.waterGoalML
    }

    private func loadDraft() {
        draft = model.settings
        weightText = SettingsLimits.weightText(model.settings.weightKG)
    }

    private func primaryAction() {
        switch step {
        case .health:
            run { await model.requestHealthAuthorization() }
        case .notifications:
            run { await model.requestNotificationAuthorization() }
        case .body:
            draft.weightKG = SettingsLimits.parseWeight(weightText)
            if !waterGoalEdited, let suggested = draft.suggestedWaterGoalML { draft.waterGoalML = suggested }
            advance()
        case .widgetTip:
            save()
            model.completeOnboarding()
        default:
            advance()
        }
    }

    private func skip() {
        if step == .body {
            weightText = ""
            draft.weightKG = nil
        }
        advance()
    }

    /// Runs a permission request, then moves on whatever the answer (it's changeable in Settings).
    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
            advance()
        }
    }

    private func advance() {
        weightFocused = false
        save()
        go(to: Step(rawValue: step.rawValue + 1))
    }

    private func go(to next: Step?) {
        guard let next else { return }
        movingForward = next.rawValue > step.rawValue
        withAnimation(.smooth(duration: 0.35)) { step = next }
        titleFocused = true
    }

    /// Saves the values edited so far (never the onboarding flag; `completeOnboarding` sets it).
    private func save() {
        let draft = draft
        model.updateSettings { settings in
            settings.weightKG = draft.weightKG
            settings.waterGoalML = draft.waterGoalML
            settings.drinkingWindow = draft.drinkingWindow
            settings.workoutGoal = draft.workoutGoal
            settings.sleepGoalScore = draft.sleepGoalScore
        }
    }
}

// MARK: - Pieces

/// Capsule segments, one per step after Welcome.
private struct StepProgress: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: FuelySpacing.xxs) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? AnyShapeStyle(FuelyColor.water.gradient) : AnyShapeStyle(FuelyColor.track))
                    .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

private struct StepHeader: View {
    var title: String
    var message: String
    var focus: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.xs) {
            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(FuelyColor.ocean)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(focus)
            Text(message)
                .font(FuelyFont.body)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StepIcon: View {
    var systemImage: String
    var color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(color.gradient)
            .frame(width: 64, height: 64)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, FuelySpacing.l)
            .accessibilityHidden(true)
    }
}

private struct FeatureRow: View {
    var icon: String
    var color: Color
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: FuelySpacing.s) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FuelyFont.cardTitle)
                Text(detail).font(FuelyFont.detail).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    var icon: String
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: FuelySpacing.s) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 28).accessibilityHidden(true)
            Text(text).font(FuelyFont.body)
            Spacer(minLength: 0)
        }
    }
}

private struct TipRow: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FuelySpacing.s) {
            Text("\(number)")
                .font(FuelyFont.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(FuelyColor.action, in: Circle())
                .accessibilityHidden(true)
            Text(text).font(FuelyFont.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}

/// A small drawing of the Lock Screen with the Fuely Line widget (DECISIONS G2).
private struct LockScreenMock: View {
    var body: some View {
        VStack(spacing: FuelySpacing.xs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(DisplayLocale.english())))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Text("9:41")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: FuelySpacing.xs) {
                Text("💧 1.2/2.4L · 😴 82 · 🏃 2/3")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .padding(.horizontal, FuelySpacing.s)
            .padding(.vertical, FuelySpacing.xs)
            .background(.white.opacity(0.18), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.vertical, FuelySpacing.l)
        .frame(maxWidth: 300)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.2, blue: 0.4), Color(red: 0.1, green: 0.55, blue: 0.7)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.top, FuelySpacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example Lock Screen with the Fuely widget: water 1.2 of 2.4 liters, sleep 82, workouts 2 of 3, and a plus button.")
    }
}

// MARK: - Previews

#Preview("Onboarding · welcome") {
    OnboardingView()
        .environment(PreviewData.model(.empty, onboarded: false))
        .fontDesign(.rounded)
}

#Preview("Onboarding · welcome · dark") {
    OnboardingView()
        .environment(PreviewData.model(.empty, onboarded: false))
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding · water goal") {
    let model = PreviewData.model(.empty, onboarded: false)
    model.updateSettings { $0.weightKG = 70; $0.waterGoalML = 2000 }
    return OnboardingView(initialStep: .waterGoal)
        .environment(model)
        .fontDesign(.rounded)
}

#Preview("Onboarding · water goal · dark") {
    let model = PreviewData.model(.empty, onboarded: false)
    model.updateSettings { $0.weightKG = 70; $0.waterGoalML = 2000 }
    return OnboardingView(initialStep: .waterGoal)
        .environment(model)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding · drinking window") {
    OnboardingView(initialStep: .drinkingWindow)
        .environment(PreviewData.model(.empty, onboarded: false))
        .fontDesign(.rounded)
}

#Preview("Onboarding · widget tip · dark") {
    OnboardingView(initialStep: .widgetTip)
        .environment(PreviewData.model(.empty, onboarded: false))
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding · body") {
    OnboardingView(initialStep: .body)
        .environment(PreviewData.model(.empty, onboarded: false))
        .fontDesign(.rounded)
}
