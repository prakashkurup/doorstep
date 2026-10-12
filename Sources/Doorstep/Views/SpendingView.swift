import SwiftUI

/// Monthly spending from order totals in your email. One headline number, then a
/// single-hue bar per store (largest first), value at each bar's tip.
struct SpendingView: View {
    @Environment(OrderStore.self) private var store
    let back: () -> Void
    @State private var monthIndex = 0

    var body: some View {
        let months = store.spendingMonths
        let month = months.indices.contains(monthIndex) ? months[monthIndex] : Calendar.current.dateInterval(of: .month, for: Date())!.start
        let spend = store.spending(for: month)
        let previous = months.indices.contains(monthIndex + 1) ? store.spending(for: months[monthIndex + 1]) : nil

        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text("Deliveries")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.blue)
                    .padding(.leading, 4)
                    .padding(.trailing, 10)
                    .frame(minHeight: 30)
                }
                .buttonStyle(HoverButtonStyle(cornerRadius: 8))
                .keyboardShortcut(.cancelAction)
                Spacer()
                HStack(spacing: 2) {
                    GlassChevron(symbol: "chevron.left", label: "Previous month") { withAnimation(.snappy(duration: 0.35)) { monthIndex += 1 } }
                        .disabled(monthIndex + 1 >= months.count)
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(minWidth: 110)
                    GlassChevron(symbol: "chevron.right", label: "Next month") { withAnimation(.snappy(duration: 0.35)) { monthIndex -= 1 } }
                        .disabled(monthIndex == 0)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent in \(month.formatted(.dateTime.month(.wide)))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(spend.total, format: .currency(code: "USD"))
                        .font(.system(size: 40, weight: .semibold))
                        .kerning(-1)
                        .contentTransition(.numericText(value: spend.total))
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 0) {
                    StatCell(label: "Orders", value: "\(spend.orderCount)")
                    Palette.hairline.frame(width: 0.5, height: 34)
                    StatCell(label: previous.map { "vs \($0.month.formatted(.dateTime.month(.abbreviated)))" } ?? "vs last month",
                             value: changeText(spend, previous: previous),
                             symbol: changeSymbol(spend, previous: previous),
                             detail: previous.map { $0.total.formatted(.currency(code: "USD").precision(.fractionLength(0))) })
                    Palette.hairline.frame(width: 0.5, height: 34)
                    StatCell(label: "Refunds", value: spend.refunds > 0 ? spend.refunds.formatted(.currency(code: "USD")) : "None")
                }
                .padding(.vertical, 12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if spend.stores.isEmpty {
                    Text("No order totals found for this month.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "By store").padding(.horizontal, -8)
                        let maxAmount = spend.stores.map(\.amount).max() ?? 1
                        ForEach(spend.stores) { row in
                            StoreBar(row: row, fraction: row.amount / maxAmount)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if spend.missingTotals > 0 {
                        Label {
                            Text("No price in email: ").foregroundStyle(.secondary)
                                + Text(spend.missingStores.joined(separator: ", "))
                        } icon: {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                        }
                    }
                    Text("Last 60 days of order emails · refunds not subtracted")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    private func changeText(_ spend: OrderStore.MonthSpending, previous: OrderStore.MonthSpending?) -> String {
        guard let previous, previous.total > 0 else { return "—" }
        let change = (spend.total - previous.total) / previous.total * 100
        return "\(Int(abs(change).rounded()))%"
    }

    /// Direction only; spending more isn't inherently bad, so no red/green.
    private func changeSymbol(_ spend: OrderStore.MonthSpending, previous: OrderStore.MonthSpending?) -> String? {
        guard let previous, previous.total > 0 else { return nil }
        return spend.total >= previous.total ? "arrow.up" : "arrow.down"
    }
}

private struct StoreBar: View {
    let row: OrderStore.StoreSpend
    let fraction: Double
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(row.store)
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text(row.amount, format: .currency(code: "USD"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 1, bottomLeading: 1, bottomTrailing: 4, topTrailing: 4))
                        .fill(Palette.track)
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 1, bottomLeading: 1, bottomTrailing: 4, topTrailing: 4))
                        .fill(Palette.blue.opacity(hovering ? 1 : 0.85))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("\(row.store): \(row.amount.formatted(.currency(code: "USD"))) across \(row.orders) order\(row.orders == 1 ? "" : "s")")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.store), \(row.amount.formatted(.currency(code: "USD"))), \(row.orders) orders")
    }
}

/// One labeled figure in the summary card: small label, crisp value, optional detail.
private struct StatCell: View {
    let label: String
    let value: String
    var symbol: String?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                }
                Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct GlassChevron: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(label)
        .accessibilityLabel(label)
    }
}
