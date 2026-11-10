import FuelyCore
import SwiftUI

/// Today's drinks under the water card (DECISIONS T5): the "Today's drinks" title with ⓘ and
/// Show All, then one row: the newest Fuely drink (swipe to delete, W7), else other apps' water as
/// a read-only row (Fuely can't delete those), else "No drinks logged yet today." Show All opens
/// today's day detail with every drink.
struct TodayDrinksSection: View {
    var entries: [WaterEntry]
    var externalML: Int
    var onShowAll: () -> Void
    var onDelete: (WaterEntry) -> Void

    private var row: TodayDrinkRow { TodayDrinkRow(entries: entries, externalML: externalML) }

    var body: some View {
        let row = row
        Section {
            TodayDrinksHeader(showsInfo: !entries.isEmpty, showsAll: row.showsAll, onShowAll: onShowAll)
                .drinksRow(top: FuelySpacing.m, bottom: 0, minHeight: 0)
            switch row {
            case .fuely(let entry):
                DrinkRow(amountML: entry.amountML, title: FuelyFormat.water(entry.amountML),
                         subtitle: nil, date: entry.date)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
                    }
                    .accessibilityAction(named: "Delete") { onDelete(entry) }
                    .drinksRow()
            case .otherApps(let ml):
                DrinkRow(amountML: ml, title: FuelyFormat.water(ml), subtitle: "Other apps · read-only", date: nil)
                    .drinksRow()
            case .none:
                Text("No drinks logged yet today.")
                    .font(FuelyFont.detail)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .drinksRow()
            }
        }
    }
}

/// "Today's drinks ⓘ" on the left, "Show All ›" on the right. Stacks at accessibility sizes so
/// nothing truncates.
private struct TodayDrinksHeader: View {
    var showsInfo: Bool
    var showsAll: Bool
    var onShowAll: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The buttons keep 44 pt tap areas that overhang the text-height title row; at accessibility
    /// sizes the text is taller than that anyway, so nothing overhangs.
    private var tapAreaOverhang: CGFloat { dynamicTypeSize.isAccessibilitySize ? 0 : -FuelySpacing.s }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: FuelySpacing.xs))
        layout {
            HStack(spacing: FuelySpacing.xxs) {
                Text("Today's drinks")
                    .font(FuelyFont.cardTitle)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if showsInfo {
                    // Keeps its 44 pt tap area but lets the title row stay text-height, so the
                    // title sits close to its row.
                    DrinksInfoButton()
                        .padding(.vertical, tapAreaOverhang)
                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : -FuelySpacing.xs)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if showsAll {
                Button(action: onShowAll) {
                    HStack(spacing: FuelySpacing.xxs) {
                        Text("Show All")
                        Image(systemName: "chevron.right")
                            .font(FuelyFont.detail.weight(.semibold))
                            .imageScale(.small)
                    }
                    .font(FuelyFont.body)
                    .foregroundStyle(FuelyColor.ocean)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.vertical, tapAreaOverhang)
                .accessibilityLabel("Show all of today's drinks")
            }
        }
    }
}

private extension View {
    /// A drinks row straight on the screen background, aligned with the cards' content.
    func drinksRow(top: CGFloat = FuelySpacing.xxs, bottom: CGFloat = FuelySpacing.xxs,
                   minHeight: CGFloat = 44) -> some View {
        frame(minHeight: minHeight)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: FuelySpacing.gutter + FuelySpacing.xxs,
                                      bottom: bottom, trailing: FuelySpacing.gutter + FuelySpacing.xxs))
    }
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
