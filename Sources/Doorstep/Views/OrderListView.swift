import SwiftUI

struct OrderListView: View {
    @Environment(OrderStore.self) private var store
    let open: (Order) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            FittedScroll(maxHeight: 600) {
                VStack(alignment: .leading, spacing: 16) {
                    if store.isEmpty {
                        EmptyStateView()
                    }
                    if !store.today.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Today")
                            ForEach(store.today) { order in
                                TodayCard(order: order) { open(order) }
                            }
                        }
                    }
                    rowSection("Tomorrow", store.tomorrow, showDate: false)
                    rowSection("Later this week", store.later, showDate: true)
                    if !store.delivered.isEmpty {
                        DeliveredSection(orders: store.delivered, open: open)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("Deliveries")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.15)
            Spacer()
            HStack(spacing: 2) {
                IconButton(symbol: "arrow.clockwise", label: "Refresh", spinning: store.isSyncing) {
                    Task { await store.refresh() }
                }
                .disabled(!store.isConnected)
                Menu {
                    Button("Open Gmail") { NSWorkspace.shared.open(URL(string: "https://mail.google.com/mail/u/0/#search/category%3Apurchases")!) }
                    Button("Settings…", action: openSettings)
                    Divider()
                    Button("Quit Doorstep") { NSApp.terminate(nil) }
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
                .accessibilityLabel("More")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func rowSection(_ title: String, _ orders: [Order], showDate: Bool) -> some View {
        if !orders.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: title)
                VStack(spacing: 2) {
                    ForEach(orders) { order in
                        OrderRow(order: order, showDate: showDate) { open(order) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 7) {
                    Circle()
                        .fill(store.lastError == nil ? Palette.green : Palette.orange)
                        .frame(width: 6, height: 6)
                    Text(syncText)
                        .lineLimit(1)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(symbol: "slider.horizontal.3", label: "Settings", action: openSettings)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Palette.hairline.frame(height: 0.5) }
    }

    private var syncText: String {
        if let error = store.lastError { return error }
        if store.isSampleMode && !store.isConnected { return "Showing sample orders" }
        if store.isSyncing { return "Syncing with Gmail…" }
        guard let last = store.lastSynced else { return "Not synced yet" }
        if Date().timeIntervalSince(last) < 60 { return "Synced with Gmail · just now" }
        return "Synced with Gmail · \(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
    }
}

struct TodayCard: View {
    let order: Order
    let action: () -> Void

    var body: some View {
        let color = Palette.color(for: order.status)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        PulsingDot(color: color)
                        Text(order.status.label)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    Spacer()
                    Text(order.expectedByTime ?? "Today")
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack(spacing: 12) {
                    OrderThumbnail(order: order, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(order.title)
                            .font(.system(size: 14, weight: .semibold))
                            .kerning(-0.1)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(order.merchant)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                ProgressDots(stage: order.stage, color: color)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct OrderRow: View {
    let order: Order
    let showDate: Bool
    let action: () -> Void

    var body: some View {
        let color = Palette.color(for: order.status)
        Button(action: action) {
            HStack(spacing: 12) {
                OrderThumbnail(order: order, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if order.showsStatusInRow {
                        Text(order.status.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    SegmentBar(stage: order.stage, color: color)
                }
                .frame(width: 70, alignment: .trailing)
            }
            .padding(8)
            .frame(minHeight: 52)
        }
        .buttonStyle(HoverButtonStyle())
    }

    private var subtitle: String {
        guard showDate, let eta = order.expectedDelivery else { return order.merchant }
        let day = DateText.weekdayDay(eta)
        switch order.status {
        case .delayed: return "\(order.merchant) · now \(day)"
        case .ordered: return "\(order.merchant) · est. \(day)"
        default: return "\(order.merchant) · \(day)"
        }
    }
}

struct DeliveredSection: View {
    @Environment(OrderStore.self) private var store
    let orders: [Order]
    let open: (Order) -> Void

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.deliveredExpanded.toggle() }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Text("DELIVERED")
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(0.5)
                        Text("\(orders.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.16), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(store.deliveredExpanded ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
            }
            .buttonStyle(HoverButtonStyle())
            .accessibilityValue(store.deliveredExpanded ? "Expanded" : "Collapsed")

            if store.deliveredExpanded {
                ForEach(orders) { order in
                    Button { open(order) } label: {
                        HStack(spacing: 12) {
                            OrderThumbnail(order: order, size: 28).opacity(0.8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(order.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if order.deliveryInferred == true, let at = order.deliveredAt {
                                    Text("Likely delivered · \(DateText.weekdayDay(at))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                } else if let at = order.deliveredAt {
                                    Text("\(DateText.weekdayDay(at)) · \(at.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.green)
                                .accessibilityLabel("Delivered")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(HoverButtonStyle())
                    .transition(.opacity)
                }
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing on the way")
                .font(.system(size: 13, weight: .semibold))
            Text("New orders from your inbox will show up here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
