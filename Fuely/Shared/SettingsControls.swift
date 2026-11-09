import FuelyCore
import SwiftUI

/// Controls shared by onboarding and Settings, so both edit values the same way and inside
/// `SettingsLimits`.

extension TimeOfDay {
    /// This time today, for a `DatePicker`.
    func pickerDate(calendar: Calendar = .current) -> Date {
        date(on: Date(), calendar: calendar)
    }

    init(pickerDate: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: pickerDate)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

/// Start and end pickers for the drinking window. The ranges keep the window same-day and at least
/// an hour long (DECISIONS W8a), so an invalid window can't be entered.
struct DrinkingWindowPickers: View {
    @Binding var window: DrinkingWindow
    private let calendar = Calendar.current

    var body: some View {
        TimePickerRow(title: "Starts", selection: startBinding, range: startRange)
        TimePickerRow(title: "Ends", selection: endBinding, range: endRange)
    }

    private var startBinding: Binding<Date> {
        Binding(get: { window.start.pickerDate(calendar: calendar) },
                set: { window.start = TimeOfDay(pickerDate: $0, calendar: calendar) })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { window.end.pickerDate(calendar: calendar) },
                set: { window.end = TimeOfDay(pickerDate: $0, calendar: calendar) })
    }

    private var startRange: ClosedRange<Date> {
        TimeOfDay(hour: 0).pickerDate(calendar: calendar)
            ... SettingsLimits.latestStart(forEnd: window.end).pickerDate(calendar: calendar)
    }

    private var endRange: ClosedRange<Date> {
        SettingsLimits.earliestEnd(forStart: window.start).pickerDate(calendar: calendar)
            ... SettingsLimits.latestWindowEnd.pickerDate(calendar: calendar)
    }
}

/// A time picker row: title on the left, the compact time button on the right. At accessibility
/// sizes the button moves under the title so neither gets squeezed.
struct TimePickerRow: View {
    var title: String
    @Binding var selection: Date
    var range: ClosedRange<Date>?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: FuelySpacing.xs) {
                Text(title).accessibilityHidden(true)
                picker.labelsHidden()
            }
        } else {
            picker
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let range {
            DatePicker(title, selection: $selection, in: range, displayedComponents: .hourAndMinute)
        } else {
            DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
        }
    }
}

/// A stepper row: title on the left, the formatted value, then − / +.
struct ValueStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var format: (Int) -> String
    /// What VoiceOver reads for the value ("2.4 liters").
    var spokenFormat: ((Int) -> String)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // One row would squeeze the title until it breaks mid-word ("Mini-mum").
                VStack(alignment: .leading, spacing: FuelySpacing.xs) {
                    titleText
                    HStack(spacing: FuelySpacing.s) {
                        valueText
                        Spacer(minLength: FuelySpacing.xs)
                        stepper
                    }
                }
            } else {
                HStack(spacing: FuelySpacing.s) {
                    titleText
                    Spacer(minLength: FuelySpacing.xs)
                    valueText
                    stepper
                }
            }
        }
        .animation(.snappy, value: value)
    }

    private var titleText: some View {
        Text(title)
            .accessibilityHidden(true)
    }

    private var valueText: some View {
        Text(format(value))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .contentTransition(.numericText(value: Double(value)))
            .accessibilityHidden(true)
    }

    private var stepper: some View {
        Stepper(title, value: $value, in: range, step: step)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(spokenFormat?(value) ?? format(value))
    }
}

/// The weight text field: digits with one decimal, kg. Reports the parsed weight (nil = empty or
/// out of range) and shows a hint for an out-of-range value.
struct WeightField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    private var isInvalid: Bool { !text.isEmpty && SettingsLimits.parseWeight(text) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.xxs) {
            HStack {
                Text("Weight")
                Spacer()
                TextField("70", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused(focus)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("Weight in kilograms")
                Text("kg").foregroundStyle(.secondary)
            }
            if isInvalid {
                Text(WeightField.rangeHint)
                    .font(FuelyFont.caption)
                    .foregroundStyle(FuelyColor.nudge)
            }
        }
    }

    static var rangeHint: String {
        "Enter a weight from \(Int(SettingsLimits.weightKG.lowerBound)) to \(Int(SettingsLimits.weightKG.upperBound)) kg."
    }
}

enum SettingsFormat {
    nonisolated static func minutes(_ value: Int) -> String { "\(value) min" }
    nonisolated static func days(_ value: Int) -> String { FuelyFormat.count(value, "day") }
}
