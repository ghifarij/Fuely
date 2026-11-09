import FuelyCore
import SwiftUI

/// Today's drinks: Fuely's entries (swipe to delete) and other apps' water as one read-only row
/// (DECISIONS W7: other apps' samples can't be deleted by Fuely).
struct TodayDrinksSection: View {
    var entries: [WaterEntry]
    var externalML: Int
    var onDelete: (WaterEntry) -> Void

    var body: some View {
        Section {
            if entries.isEmpty && externalML == 0 {
                Text("No drinks logged yet today.")
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
                    .listRowBackground(rowBackground)
            }
            ForEach(entries) { entry in
                DrinkRow(amountML: entry.amountML, title: FuelyFormat.water(entry.amountML),
                         subtitle: nil, date: entry.date)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
                    }
                    .accessibilityAction(named: "Delete") { onDelete(entry) }
                    .listRowBackground(rowBackground)
            }
            if externalML > 0 {
                DrinkRow(amountML: externalML, title: FuelyFormat.water(externalML),
                         subtitle: "Other apps · read-only", date: nil)
                    .listRowBackground(rowBackground)
            }
        } header: {
            HStack(spacing: FuelySpacing.xs) {
                Text("Today's drinks")
                    .font(FuelyFont.cardTitle)
                    .foregroundStyle(.primary)
                if !entries.isEmpty {
                    DrinksInfoButton()
                }
            }
            .textCase(nil)
            .padding(.top, FuelySpacing.s)
        }
    }

    /// Rows sit straight on the screen background; separators keep them apart.
    private var rowBackground: some View { Color.clear }
}

/// The ⓘ beside a drinks section title (Today and day detail): explains swipe-to-delete in a
/// small popover instead of a permanent caption under the list.
struct DrinksInfoButton: View {
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .font(FuelyFont.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About deleting drinks")
        .popover(isPresented: $isShowing) {
            Text("Swipe left on a drink to delete it. It's removed from Apple Health too.")
                .font(FuelyFont.detail)
                .fontDesign(.rounded)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
                .padding(FuelySpacing.m)
                .presentationCompactAdaptation(.popover)
        }
    }
}

struct DrinkRow: View {
    var amountML: Int
    var title: String
    var subtitle: String?
    var date: Date?

    var body: some View {
        HStack(spacing: FuelySpacing.s) {
            Image(systemName: subtitle == nil ? "drop.fill" : "square.stack.3d.up.fill")
                .foregroundStyle(FuelyColor.water)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FuelyFont.body.weight(.semibold)).monospacedDigit()
                if let subtitle {
                    Text(subtitle).font(FuelyFont.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let date {
                Text(date, format: .dateTime.hour().minute())
                    .font(FuelyFont.detail)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = FuelyFormat.waterSpoken(amountML)
        if let subtitle { text += ", \(subtitle.replacingOccurrences(of: " · ", with: ", "))" }
        if let date { text += ", at \(date.formatted(date: .omitted, time: .shortened))" }
        return text
    }
}
