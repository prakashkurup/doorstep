import AppKit
import SwiftUI

struct OrderDetailView: View {
    @Environment(OrderStore.self) private var store
    let order: Order
    let back: () -> Void
    @State private var copied = false

    private var color: Color { Palette.color(for: order) }
    private var trackURL: URL? { order.carrier.trackingURL(tracking: order.trackingNumber, orderNumber: order.orderNumber) }

    var body: some View {
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
                Menu {
                    if let number = order.orderNumber {
                        Button("Copy order number") { copy(number) }
                    }
                    // Without a Track button, marking delivered is the main action below instead.
                    if order.isActive, trackURL != nil {
                        Button("Mark as delivered") { store.markDelivered(order) }
                    } else if order.markedDelivered == true {
                        Button("Mark as not delivered") { store.unmarkDelivered(id: order.id) }
                    }
                    Button("Hide order") { store.hide(order); back() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(HoverButtonStyle(cornerRadius: 8))
                .fixedSize()
                .accessibilityLabel("More actions")
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

            FittedScroll(maxHeight: 640) {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock
                    statusCard
                    if !Snapshot.isActive, order.status != .delivered, let place = order.live?.events.first?.location {
                        LastScanMap(place: place)
                    }
                    updates
                    if order.items.filter({ !$0.name.isEmpty }).count > 1 { itemsSection }
                    detailsList
                    actions
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
        }
    }

    private var titleBlock: some View {
        HStack(spacing: 14) {
            OrderThumbnail(order: order, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(order.title)
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.15)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(order.merchant)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(order.statusLabel, systemImage: Palette.symbol(for: order))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                    Spacer()
                    if let live = order.live {
                        HStack(spacing: 5) {
                            Circle().fill(Palette.green).frame(width: 6, height: 6)
                            Text("Live · \(live.carrierName ?? order.carrier.displayName) · \(live.lastChecked.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("Status straight from the carrier, via 17TRACK")
                    }
                }
                Text(etaText)
                    .font(.system(size: 24, weight: .semibold))
                    .kerning(-0.5)
                if order.deliveryInferred == true, let at = order.deliveredAt {
                    Text("No delivery email. It was due \(DateText.weekdayDay(at)).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if order.markedDelivered == true {
                    Text("You marked this as delivered.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if let scan = order.live?.events.first, order.status != .delivered {
                    Text("Last scan \(scan.date.formatted(date: .omitted, time: .shortened))\(scan.location.map { " in \($0)" } ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if order.status == .delayed, let original = order.originalExpected {
                    Text("Originally due \(DateText.weekdayDay(original))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressDots(stage: order.stage, color: color, showLabels: true)
            if order.signatureRequired == true, order.status != .delivered {
                Label("Signature required. Someone needs to be home to sign.", systemImage: "signature")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var etaText: String {
        let cal = Calendar.current
        if order.deliveryInferred == true { return "Likely delivered" }
        // The time you marked it isn't when it arrived, so only the day.
        if order.markedDelivered == true, let at = order.deliveredAt {
            return cal.isDateInToday(at) ? "Delivered today" : "Delivered \(at.formatted(.dateTime.weekday(.abbreviated)))"
        }
        if order.status == .delivered, let at = order.deliveredAt {
            let day = cal.isDateInToday(at) ? "today" : at.formatted(.dateTime.weekday(.abbreviated))
            return "Delivered \(day), \(at.formatted(date: .omitted, time: .shortened))"
        }
        if order.status == .outForDelivery {
            if let window = order.deliveryWindow { return "Today, \(window)" }
            return order.expectedByTime.map { "Today, \($0)" } ?? "Today"
        }
        guard let eta = order.expectedDelivery else { return "Arrival date not known yet" }
        if cal.isDateInToday(eta) { return order.expectedByTime.map { "Today, \($0)" } ?? "Today" }
        if cal.isDateInTomorrow(eta) { return "Tomorrow" }
        let day = DateText.weekdayDay(eta)
        return order.status == .ordered ? "Est. \(day)" : day
    }

    private struct TimelineEntry: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    private var timeline: [TimelineEntry] {
        if let live = order.live, !live.events.isEmpty {
            return live.events.enumerated().map { i, e in
                TimelineEntry(id: "live-\(i)", title: e.description,
                              detail: DateText.eventTime(e.date) + (e.location.map { " · \($0)" } ?? ""))
            }
        }
        return order.events.sorted { $0.date > $1.date }.map {
            TimelineEntry(id: $0.id, title: $0.status.eventLabel, detail: DateText.eventTime($0.date))
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: order.live?.events.isEmpty == false ? "Carrier scans" : "Updates").padding(.horizontal, -8)
            let events = timeline
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(index == 0 ? color : Palette.track)
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(index == events.count - 1 ? .clear : Palette.track)
                                .frame(width: 1.5)
                                .frame(minHeight: 20)
                        }
                        .padding(.top, 5)
                        .frame(width: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                            Text(event.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 14)
                    }
                }
            }
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Items").padding(.horizontal, -8)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(order.items.filter { !$0.name.isEmpty }.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(item.quantity)×").foregroundStyle(.secondary).monospacedDigit()
                        Text(item.name)
                    }
                    .font(.system(size: 13))
                }
            }
        }
    }

    private var detailsList: some View {
        let rows: [(String, String)] = [
            ("Order", order.orderNumber),
            ("Carrier", order.carrierName),
            ("Ordered", order.orderedAt.map(DateText.weekdayDay)),
            ("Total", order.total),
            ("Return by", returnByText),
        ].compactMap { label, value in value.map { (label, $0) } }

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                detailRow(row.0, divider: index > 0) {
                    Text(row.1).monospacedDigit().textSelection(.enabled)
                }
            }
            detailRow("Tracking", divider: !rows.isEmpty, trailing: order.trackingNumber == nil ? 14 : 6) {
                HStack(spacing: 4) {
                    Text(order.trackingNumber ?? "Not assigned yet")
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let tracking = order.trackingNumber {
                        Button(copied ? "Copied" : "Copy") {
                            copy(tracking)
                            copied = true
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 26)
                        .buttonStyle(HoverButtonStyle(cornerRadius: 6))
                    }
                }
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))
    }

    private var returnByText: String? {
        if let returned = store.returnCase(for: order) { return returned.status.label }
        guard let date = order.returnBy else { return nil }
        let text = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return order.returnByEstimated == true ? "\(text) (est.)" : text
    }

    private func detailRow<V: View>(_ label: String, divider: Bool, trailing: CGFloat = 14, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value()
        }
        .font(.system(size: 12.5))
        .padding(.leading, 14)
        .padding(.trailing, trailing)
        .frame(minHeight: 38)
        .overlay(alignment: .top) {
            if divider { Palette.hairline.frame(height: 0.5) }
        }
    }

    // No GlassEffectContainer here: it would blend the blue primary into its neighbors.
    private var actions: some View {
        Group {
            VStack(spacing: 8) {
                if let url = trackURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 6) {
                            Text(trackLabel)
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.primaryButton)
                } else if order.isActive {
                    // Stores without tracking (florists, local shops) never say it arrived.
                    Button { store.markDelivered(order) } label: {
                        Label("Mark as delivered", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.primaryButton)
                }
                HStack(spacing: 8) {
                    Button("Open email") { openEmail() }
                        .buttonStyle(NeutralGlassButtonStyle())
                        .disabled(["sample", "manual"].contains(order.latestThreadId))
                    Button("Hide order") { store.hide(order); back() }
                        .buttonStyle(NeutralGlassButtonStyle())
                }
            }
        }
    }

    private var trackLabel: String {
        switch order.carrier {
        case .amazon: "Track on Amazon"
        case .other: "Look up tracking"
        default: "Track with \(order.carrier.displayName)"
        }
    }

    private func openEmail() {
        if let url = URL(string: "https://mail.google.com/mail/u/0/#all/\(order.latestThreadId)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
