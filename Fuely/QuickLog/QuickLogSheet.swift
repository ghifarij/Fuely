import FuelyCore
import SwiftUI

/// Quick log (DECISIONS W5b, W7): 150 / 250 / 500 ml, a custom amount, and Undo for today's
/// newest entry. Writes go through `AppModel` → `WaterLogService` (store first, then HealthKit).
struct QuickLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var customText = ""
    @State private var isWorking = false
    /// The last amount added in this sheet, for the confirmation line.
    @State private var lastAdded: Int?
    @FocusState private var customFocused: Bool

    private var customAmount: Int? { WaterLogging.parseCustomAmount(customText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FuelySpacing.l) {
                    progressHeader
                    quickButtons
                    customRow
                    if let entry = model.undoCandidate {
                        undoRow(entry)
                    }
                }
                .padding(.horizontal, FuelySpacing.gutter)
                .padding(.vertical, FuelySpacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .fuelyScreenBackground()
            .navigationTitle("Log water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
        // Tall enough for the Undo row at the default text size (.medium cut it off).
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    /// Every row here is a single line with a fixed height, so a longer pace message or a bigger
    /// total never wraps and pushes the quick-add buttons below it up or down.
    private var progressHeader: some View {
        let water = model.summary.water
        return VStack(alignment: .leading, spacing: FuelySpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: FuelySpacing.xs) {
                Text(FuelyFormat.water(water.totalML))
                    .font(FuelyFont.value)
                    .monospacedDigit()
                    .foregroundStyle(FuelyColor.ocean)
                    .contentTransition(.numericText(value: Double(water.totalML)))
                Text("of \(FuelyFormat.water(water.goalML))")
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            ProgressBar(fraction: water.fraction, color: FuelyColor.water)
            HStack(spacing: FuelySpacing.s) {
                PaceBadge(water: water)
                Spacer(minLength: 0)
                // Always laid out (hidden until the first add) so it never changes the height.
                Label("Added \(FuelyFormat.water(lastAdded ?? 0))", systemImage: "checkmark.circle.fill")
                    .font(FuelyFont.caption.weight(.semibold))
                    .foregroundStyle(FuelyColor.ocean)
                    .opacity(lastAdded == nil ? 0 : 1)
                    .accessibilityHidden(lastAdded == nil)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var quickButtons: some View {
        HStack(spacing: FuelySpacing.s) {
            ForEach(WaterLogging.quickAddAmountsML, id: \.self) { amount in
                Button {
                    log(amount)
                } label: {
                    VStack(spacing: FuelySpacing.xs) {
                        Image(systemName: "drop.fill")
                            .font(dropFont(for: amount))
                            .foregroundStyle(FuelyColor.water)
                            .frame(height: 34)
                        Text(FuelyFormat.water(amount))
                            .font(FuelyFont.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FuelySpacing.xs)
                }
                .buttonStyle(QuickAddTileStyle())
                .accessibilityLabel("Add \(FuelyFormat.waterSpoken(amount))")
            }
        }
    }

    private var customRow: some View {
        VStack(alignment: .leading, spacing: FuelySpacing.xs) {
            Text("Custom amount").font(FuelyFont.cardTitle)
            HStack(spacing: FuelySpacing.s) {
                HStack {
                    TextField("e.g. 330", text: $customText)
                        .keyboardType(.numberPad)
                        .focused($customFocused)
                        .font(FuelyFont.body)
                        .monospacedDigit()
                        .submitLabel(.done)
                        .onSubmit(addCustom)
                        .accessibilityLabel("Custom amount in milliliters")
                    Text("ml").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .fuelyCard(cornerRadius: FuelySpacing.controlRadius, padding: FuelySpacing.s)

                Button("Add", action: addCustom)
                    .font(FuelyFont.body.weight(.semibold))
                    .fuelyProminentButton()
                    .controlSize(.large)
                    .tint(FuelyColor.action)
                    .disabled(customAmount == nil || isWorking)
            }
            if !customText.isEmpty && customAmount == nil {
                Text("Enter 1 to \(WaterLogging.customAmountRangeML.upperBound) ml.")
                    .font(FuelyFont.caption)
                    .foregroundStyle(FuelyColor.nudge)
            }
        }
    }

    private func undoRow(_ entry: WaterEntry) -> some View {
        HStack(spacing: FuelySpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last drink").font(FuelyFont.caption).foregroundStyle(.secondary)
                HStack(spacing: FuelySpacing.xxs) {
                    Text(FuelyFormat.water(entry.amountML)).font(FuelyFont.body.weight(.semibold))
                    Text("at \(entry.date.formatted(date: .omitted, time: .shortened))")
                        .font(FuelyFont.detail)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
            Spacer()
            Button("Undo", systemImage: "arrow.uturn.backward") {
                Task {
                    isWorking = true
                    await model.undoLatest()
                    lastAdded = nil
                    isWorking = false
                    AccessibilityNotification.Announcement("Removed \(FuelyFormat.waterSpoken(entry.amountML))").post()
                }
            }
            .fuelySecondaryButton()
            .disabled(isWorking)
            .accessibilityLabel("Undo last drink, \(FuelyFormat.waterSpoken(entry.amountML))")
        }
        .fuelyCard(cornerRadius: FuelySpacing.controlRadius, padding: FuelySpacing.s)
    }

    // MARK: Actions

    private func addCustom() {
        guard let amount = customAmount else { return }
        customFocused = false
        customText = ""
        log(amount)
    }

    private func log(_ amount: Int) {
        // Guard instead of `.disabled` on the quick buttons: toggling disabled re-styles the
        // glass buttons on every tap, which makes the drop and label flicker.
        guard !isWorking else { return }
        isWorking = true
        Task {
            if await model.logWater(amountML: amount) != nil {
                lastAdded = amount
                AccessibilityNotification.Announcement("Added \(FuelyFormat.waterSpoken(amount))").post()
            }
            isWorking = false
        }
    }

    /// Bigger drop for bigger amounts.
    private func dropFont(for amount: Int) -> Font {
        switch amount {
        case ..<200: .body
        case ..<400: .title3
        default: .title
        }
    }
}

/// A still glass tile for the quick-add amounts. The system `.glass` button style scales and
/// wobbles its label on press, which made the drop and amount jump on every tap; this tile only
/// dims while pressed.
private struct QuickAddTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, FuelySpacing.s)
            .padding(.horizontal, FuelySpacing.xs)
            .contentShape(RoundedRectangle(cornerRadius: FuelySpacing.controlRadius, style: .continuous))
            .fuelyCard(cornerRadius: FuelySpacing.controlRadius, padding: 0)
            .overlay {
                RoundedRectangle(cornerRadius: FuelySpacing.controlRadius, style: .continuous)
                    .fill(FuelyColor.water.opacity(configuration.isPressed ? 0.18 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("Quick log") {
    QuickLogSheet()
        .environment(PreviewData.model(.onTrack))
}

#Preview("Quick log · dark") {
    QuickLogSheet()
        .environment(PreviewData.model(.behindNoSleep))
        .preferredColorScheme(.dark)
}

#Preview("Quick log · as sheet") {
    Color.clear
        .sheet(isPresented: .constant(true)) { QuickLogSheet() }
        .environment(PreviewData.model(.onTrack))
}
