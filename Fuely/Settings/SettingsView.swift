import FuelyCore
import SwiftUI
import UIKit

/// Everything from onboarding, editable (DECISIONS O1, W1, W2, W6, W8, R1, R2, S5, K2). No height
/// (W1). Every change writes through `AppModel.updateSettings`, which clamps to `SettingsLimits`
/// and reloads the widgets.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var weightText = ""
    @FocusState private var weightFocused: Bool

    private var settings: FuelySettings { model.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: FuelySpacing.l) {
                bodySection
                waterSection
                remindersSection
                workoutSection
                sleepSection
                healthSection
                aboutSection
            }
            .font(FuelyFont.body)
            .tint(FuelyColor.action)
            .padding(.horizontal, FuelySpacing.gutter)
            .padding(.top, FuelySpacing.xs)
            .padding(.bottom, FuelySpacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .fuelyScreenBackground()
        .navigationTitle("Settings")
        .onAppear { weightText = SettingsLimits.weightText(settings.weightKG) }
        .onChange(of: weightFocused) { _, focused in
            if !focused { commitWeight() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    // MARK: Sections

    private var bodySection: some View {
        SettingsCard("Body", systemImage: "figure.stand", color: FuelyColor.ocean,
                     footer: "Used only to suggest your water goal (35 ml per kg). Not shared with Apple Health.") {
            WeightField(text: $weightText, focus: $weightFocused)
                .onSubmit { commitWeight() }
                .settingsRow()
        }
    }

    private var waterSection: some View {
        SettingsCard("Water", systemImage: "drop.fill", color: FuelyColor.water,
                     footer: "Your pace runs across the \(SettingsCopy.windowLength(settings.drinkingWindow)) drinking window. "
                         + "The widget's (+) button logs the widget amount.") {
            ValueStepper(title: "Daily goal", value: binding(\.waterGoalML), range: SettingsLimits.waterGoalML,
                         step: SettingsLimits.waterGoalStepML, format: { FuelyFormat.water($0) },
                         spokenFormat: { FuelyFormat.waterSpoken($0) })
                .settingsRow()
            if let suggested = settings.suggestedWaterGoalML {
                SettingsDivider()
                if suggested == settings.waterGoalML {
                    SettingsValueRow(title: "Suggested for your weight", value: "In use")
                        .settingsRow()
                } else {
                    Button {
                        model.updateSettings { $0.waterGoalML = suggested }
                    } label: {
                        SettingsValueRow(title: "Use suggested", value: FuelyFormat.water(suggested),
                                         titleStyle: AnyShapeStyle(FuelyColor.action))
                            .settingsRow()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use suggested goal, \(FuelyFormat.waterSpoken(suggested))")
                }
            }
            SettingsDivider()
            VStack(alignment: .leading, spacing: FuelySpacing.s) {
                DrinkingWindowPickers(window: binding(\.drinkingWindow))
            }
            .settingsRow()
            SettingsDivider()
            ValueStepper(title: "Widget (+) amount", value: binding(\.widgetAmountML),
                         range: SettingsLimits.widgetAmountML, step: SettingsLimits.widgetAmountStepML,
                         format: { FuelyFormat.water($0) }, spokenFormat: { FuelyFormat.waterSpoken($0) })
                .settingsRow()
        }
    }

    private var remindersSection: some View {
        let on = settings.remindersEnabled
        let permissionNote = on ? SettingsCopy.notificationPermission(model.notificationPermission) : nil
        return SettingsCard("Reminders", systemImage: "bell.fill", color: FuelyColor.nudge,
                            footer: on
                                ? "Water: at most 2 a day, 2\u{00A0}h apart, only when you're behind pace. "
                                    + "Workouts: one morning note, only when your week needs it."
                                : "Fuely won't send water or workout reminders.") {
            Toggle("Water & workout reminders", isOn: binding(\.remindersEnabled))
                .settingsRow()
            if on {
                SettingsDivider()
                TimePickerRow(title: "Workout reminder", selection: workoutReminderBinding)
                    .settingsRow()
            }
            if let permissionNote {
                SettingsDivider()
                VStack(alignment: .leading, spacing: FuelySpacing.s) {
                    Label(permissionNote, systemImage: "bell.slash.fill")
                        .font(FuelyFont.detail)
                        .foregroundStyle(FuelyColor.nudge)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.notificationPermission == .notDetermined {
                        Button {
                            Task { await model.requestNotificationAuthorization() }
                        } label: {
                            Text("Allow Notifications").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .fuelyProminentButton()
                        .tint(FuelyColor.action)
                    } else {
                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .fuelySecondaryButton()
                        .tint(FuelyColor.ocean)
                    }
                }
                .padding(FuelySpacing.m)
            }
        }
        .animation(.default, value: on)
        .task { await model.refreshNotificationPermission() }
    }

    private var workoutSection: some View {
        SettingsCard("Workouts", systemImage: "figure.run", color: FuelyColor.workout,
                     footer: "Every workout type counts. Minutes on the same day add up. Weeks run Monday to Sunday.") {
            ValueStepper(title: "Minimum per day", value: binding(\.workoutGoal.minMinutesPerDay),
                         range: SettingsLimits.workoutMinutes, step: SettingsLimits.workoutMinutesStep,
                         format: { SettingsFormat.minutes($0) }, spokenFormat: { FuelyFormat.count($0, "minute") })
                .settingsRow()
            SettingsDivider()
            ValueStepper(title: "Days per week", value: binding(\.workoutGoal.daysPerWeek),
                         range: SettingsLimits.workoutDaysPerWeek, format: { SettingsFormat.days($0) })
                .settingsRow()
        }
    }

    private var sleepSection: some View {
        SettingsCard("Sleep", systemImage: "moon.zzz.fill", color: FuelyColor.sleep,
                     footer: "Fuely computes its own score from your sleep in Apple Health (all sources, naps included), following Apple's method.") {
            ValueStepper(title: "Sleep score goal", value: binding(\.sleepGoalScore), range: SettingsLimits.sleepGoal,
                         step: SettingsLimits.sleepGoalStep, format: { "\($0)" })
                .settingsRow()
        }
    }

    private var healthSection: some View {
        let status = SettingsCopy.healthAccess(model.healthAccess)
        return SettingsCard("Apple Health", systemImage: "heart.fill", color: FuelyColor.nudge,
                            footer: status.detail + " Read access for sleep and workouts is private, so only the Settings app shows it.") {
            SettingsValueRow(title: "Status") {
                Label(status.title, systemImage: healthIcon)
                    .foregroundStyle(model.healthAccess == .allowed ? FuelyColor.ocean : FuelyColor.nudge)
            }
            .settingsRow()
            .accessibilityElement(children: .combine)
            VStack(spacing: FuelySpacing.xs) {
                if model.healthAccess == .notDetermined {
                    Button {
                        Task { await model.requestHealthAuthorization() }
                    } label: {
                        Text("Connect Apple Health").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .fuelyProminentButton()
                    .tint(FuelyColor.action)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .fuelySecondaryButton()
                .tint(FuelyColor.ocean)
            }
            .padding([.horizontal, .bottom], FuelySpacing.m)
            .padding(.top, FuelySpacing.xxs)
        }
    }

    private var aboutSection: some View {
        SettingsCard("About", systemImage: "info.circle.fill", color: FuelyColor.ocean) {
            SettingsValueRow(title: "Version", value: Self.version)
                .settingsRow()
            SettingsDivider()
            SettingsValueRow(title: "Data", value: "On this iPhone and Apple Health")
                .settingsRow()
        }
    }

    // MARK: Helpers

    private var healthIcon: String {
        switch model.healthAccess {
        case .allowed: "checkmark.circle.fill"
        case .denied: "exclamationmark.circle.fill"
        case .notDetermined: "circle.dashed"
        case .unavailable: "xmark.circle"
        }
    }

    /// A binding that writes straight through `updateSettings` (store + widget reload).
    private func binding<Value>(_ keyPath: WritableKeyPath<FuelySettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] },
                set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private var workoutReminderBinding: Binding<Date> {
        Binding(get: { settings.workoutReminderTime.pickerDate() },
                set: { date in model.updateSettings { $0.workoutReminderTime = TimeOfDay(pickerDate: date) } })
    }

    /// Saves a valid weight; an empty field clears it; an invalid one is left for the user to fix.
    private func commitWeight() {
        if weightText.trimmingCharacters(in: .whitespaces).isEmpty {
            if settings.weightKG != nil { model.updateSettings { $0.weightKG = nil } }
        } else if let weight = SettingsLimits.parseWeight(weightText), weight != settings.weightKG {
            model.updateSettings { $0.weightKG = weight }
            weightText = SettingsLimits.weightText(weight)
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// A Settings section on a Fuely glass card (DECISIONS D4): a colored title above, the rows on the
/// card, and an optional note below.
private struct SettingsCard<Content: View>: View {
    var title: String
    var systemImage: String
    var color: Color
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String, systemImage: String, color: Color, footer: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.xs) {
            CardTitle(title, systemImage: systemImage, color: color)
                .padding(.horizontal, FuelySpacing.xxs)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fuelyCard(padding: nil)
            if let footer {
                Text(footer)
                    .font(FuelyFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, FuelySpacing.xxs)
            }
        }
    }
}

/// A read-only row: title on the left, value on the right; stacked at accessibility sizes.
private struct SettingsValueRow<Value: View>: View {
    var title: String
    var titleStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    @ViewBuilder var value: Value
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: FuelySpacing.xxs))
            : AnyLayout(HStackLayout(spacing: FuelySpacing.s))
        layout {
            Text(title).foregroundStyle(titleStyle)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: FuelySpacing.xs) }
            value
                .foregroundStyle(.secondary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension SettingsValueRow where Value == Text {
    init(title: String, value: String, titleStyle: AnyShapeStyle = AnyShapeStyle(.primary)) {
        self.init(title: title, titleStyle: titleStyle) { Text(value) }
    }
}

/// A hairline between rows, inset like system lists.
private struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, FuelySpacing.m) }
}

private extension View {
    /// Row padding inside a Settings card, at least 44 pt tall (HIG).
    func settingsRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, FuelySpacing.m)
            .padding(.vertical, FuelySpacing.xs)
    }
}

#Preview("Settings") {
    NavigationStack { SettingsView() }
        .environment(PreviewData.model(.onTrack))
        .fontDesign(.rounded)
}

#Preview("Settings · dark") {
    NavigationStack { SettingsView() }
        .environment(PreviewData.model(.onTrack, history: true))
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
}
