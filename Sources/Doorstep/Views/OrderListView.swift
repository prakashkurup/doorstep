import SwiftUI

struct OrderListView: View {
    @Environment(OrderStore.self) private var store
    let open: (Order) -> Void
    let openReturn: (ReturnCase) -> Void
    let openSettings: () -> Void
    let openSpending: () -> Void
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            TabSwitcher()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            FittedScroll(maxHeight: 600) {
                VStack(alignment: .leading, spacing: 16) {
                    switch store.listTab {
                    case .arriving: ArrivingTab(open: open, goToReturns: { store.selectTab(.returns) })
                    case .returns: ReturnsTab(open: open, openReturn: openReturn)
                    case .delivered: DeliveredTab(open: open)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 14)
                .id(store.listTab)
                .transition(.push(from: store.tabMovedForward ? .trailing : .leading))
            }
            .clipped()
            footer
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(message: toast).padding(.bottom, 52)
            }
        }
        .background { keyboardCommands }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { store.moveHighlight(by: 1); return .handled }
        .onKeyPress(.upArrow) { store.moveHighlight(by: -1); return .handled }
        .onKeyPress(.return) {
            guard let id = store.highlightedID, let order = store.order(id: id) else { return .ignored }
            open(order)
            return .handled
        }
    }

    /// Invisible buttons that own the panel's shortcuts: ⌘1–3 for tabs, ⌘V to track a
    /// pasted number (not on Delivered, where ⌘V belongs to the search field).
    @ViewBuilder
    private var keyboardCommands: some View {
        ZStack {
            Button("") { store.selectTab(.arriving) }.keyboardShortcut("1")
            Button("") { store.selectTab(.returns) }.keyboardShortcut("2")
            Button("") { store.selectTab(.delivered) }.keyboardShortcut("3")
            if store.listTab != .delivered {
                Button("") { pasteTrackingNumber() }.keyboardShortcut("v")
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func pasteTrackingNumber() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            show("Copy a tracking number, then press ⌘V here.")
            return
        }
        Task {
            let message = await store.addTrackingNumber(text)
            show(message)
        }
    }

    private func show(_ message: String) {
        withAnimation(.snappy(duration: 0.25)) { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.3)) { if toast == message { toast = nil } }
        }
    }

    private var header: some View {
        HStack {
            Text("Deliveries")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.15)
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    Button(action: openSpending) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Spending")
                    .accessibilityLabel("Spending")
                    SyncButton(isSyncing: store.isSyncing, failed: store.lastError != nil, progress: store.syncProgress) {
                        Task { await store.refresh() }
                    }
                    .disabled(!store.isConnected)
                }
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// A floating glass capsule: sync status on the left, the app menu on the right.
    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 7) {
                    Circle()
                        .fill(store.lastError == nil ? Palette.green : Palette.orange)
                        .frame(width: 6, height: 6)
                    Text(syncText)
                        .lineLimit(1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: syncText)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            // One place for app-level actions, as in most menu bar apps.
            Menu {
                Button("Settings…", action: openSettings)
                Button("Open Gmail") { NSWorkspace.shared.open(URL(string: "https://mail.google.com/mail/u/0/#search/category%3Apurchases")!) }
                Divider()
                Button("Quit Doorstep") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(HoverButtonStyle(cornerRadius: 8))
            .fixedSize()
            .help("Settings and more")
            .accessibilityLabel("Settings and more")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    private var syncText: String {
        if let error = store.lastError { return error }
        if store.isSampleMode && !store.isConnected { return "Showing sample orders" }
        if store.isSyncing && store.syncTotal > 0 { return "Reading \(store.syncDone) of \(store.syncTotal) emails…" }
        if store.isSyncing { return "Syncing with Gmail…" }
        guard let last = store.lastSynced else { return "Not synced yet" }
        if Date().timeIntervalSince(last) < 60 { return "Synced with Gmail · just now" }
        return "Synced with Gmail · \(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
    }
}

// MARK: - Tabs

private struct TabSwitcher: View {
    @Environment(OrderStore.self) private var store
    @Namespace private var pill

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                tab(.arriving, "Arriving", symbol: "shippingbox.fill", tint: Palette.blue, count: store.arrivingCount)
                tab(.returns, "Returns", symbol: "arrow.uturn.left", tint: Palette.orange, count: store.returnsCount)
                tab(.delivered, "Delivered", symbol: "checkmark.circle.fill", tint: Palette.green, count: nil)
            }
            .padding(3)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    /// Icon and color identify each tab at a glance; the selected one is tinted in its color.
    private func tab(_ id: OrderStore.ListTab, _ label: String, symbol: String, tint: Color, count: Int?) -> some View {
        let selected = store.listTab == id
        return Button {
            store.selectTab(id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? tint : .secondary)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                        .animation(.snappy, value: count)
                        .foregroundStyle(selected ? tint : .secondary)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 16)
                        .background((selected ? tint : Color.gray).opacity(selected ? 0.2 : 0.18), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background {
                // One pill that glides to whichever tab is selected.
                if selected {
                    Color.clear
                        .glassEffect(.regular.tint(tint.opacity(0.32)).interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(count.map { "\(label), \($0)" } ?? label)
    }
}

/// A section that shows the first few rows and a "Show N more" toggle.
private struct CappedSection<Item: Identifiable, Row: View>: View {
    let title: String
    var titleColor: Color = .secondary
    let items: [Item]
    var limit = 5
    @ViewBuilder let row: (Item) -> Row
    @State private var expanded = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: title, color: titleColor)
                VStack(spacing: 2) {
                    ForEach(expanded ? items : Array(items.prefix(limit))) { row($0) }
                }
                if items.count > limit {
                    Button(expanded ? "Show less" : "Show \(items.count - limit) more") {
                        withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Arriving

private struct ArrivingTab: View {
    @Environment(OrderStore.self) private var store
    let open: (Order) -> Void
    let goToReturns: () -> Void

    var body: some View {
        if let urgent = store.urgentReturnWindows.first {
            ReturnNudge(order: urgent, others: store.urgentReturnWindows.count - 1, action: goToReturns) {
                withAnimation(.snappy(duration: 0.2)) { store.dismissNudge(for: urgent) }
            }
        }
        if store.showsWeekStrip {
            WeekStrip()
        }
        if let day = store.selectedDay {
            daySection(day)
        } else if store.arrivingCount == 0 {
            EmptyStateView()
        } else {
            if !store.today.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Today")
                    ForEach(store.today) { order in
                        if order.status == .outForDelivery {
                            TodayCard(order: order) { open(order) }
                        } else {
                            OrderRow(order: order, context: .today) { open(order) }
                        }
                    }
                }
            }
            CappedSection(title: "Tomorrow", items: store.tomorrow) { item in OrderRow(order: item, context: .tomorrow) { open(item) } }
            CappedSection(title: "Running late", titleColor: Palette.orange, items: store.late) { item in OrderRow(order: item, context: .late) { open(item) } }
            CappedSection(title: "Later", items: store.later) { item in OrderRow(order: item, context: .later) { open(item) } }
        }
    }

    @ViewBuilder
    private func daySection(_ day: Date) -> some View {
        let orders = store.arrivals(on: day)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionHeader(title: Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                Spacer()
                Button("Show all") { withAnimation(.snappy(duration: 0.2)) { store.selectedDay = nil } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.blue)
                    .padding(.trailing, 8)
            }
            if orders.isEmpty {
                Text("Nothing expected this day.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 2) {
                    ForEach(orders) { order in
                        OrderRow(order: order, context: Calendar.current.isDateInToday(day) ? .today : .tomorrow) { open(order) }
                    }
                }
            }
        }
    }
}

/// One line on the Arriving tab when a return window is about to close.
private struct ReturnNudge: View {
    let order: Order
    let others: Int
    let action: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.orange)
                    HStack(spacing: 4) {
                        (Text("Return ") + Text(order.title).fontWeight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("by \(order.returnBy?.formatted(.dateTime.weekday(.abbreviated)) ?? "soon")")
                            .fixedSize()
                    }
                    .font(.system(size: 12.5))
                    Spacer(minLength: 4)
                    Text(ReturnText.daysLeft(order.returnBy) + (others > 0 ? " · +\(others)" : ""))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.orange)
                        .fixedSize()
                }
                .padding(.leading, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows returns")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle(cornerRadius: 6))
            .help("Dismiss. It stays on the Returns tab.")
            .accessibilityLabel("Dismiss return reminder")
            .padding(.trailing, 6)
        }
        .glassEffect(.regular.tint(Palette.orange.opacity(0.22)).interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum ReturnText {
    static func days(_ date: Date?) -> Int? {
        guard let date else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day
    }

    static func daysLeft(_ date: Date?) -> String {
        guard let d = days(date) else { return "" }
        switch d {
        case ..<1: return "Last day"
        case 1: return "1 day"
        default: return "\(d) days"
        }
    }
}

// MARK: - Returns

private struct ReturnsTab: View {
    @Environment(OrderStore.self) private var store
    let open: (Order) -> Void
    let openReturn: (ReturnCase) -> Void

    var body: some View {
        if store.openReturnWindows.isEmpty && store.activeReturns.isEmpty && store.recentRefunds.isEmpty {
            TabEmptyState(symbol: "arrow.uturn.left", title: "No returns", detail: "Return deadlines and refunds will show up here.")
        }
        CappedSection(title: "Return by", items: store.openReturnWindows) { item in ReturnWindowRow(order: item) { open(item) } }
        CappedSection(title: "In progress", items: store.activeReturns) { item in ReturnRow(item: item) { openReturn(item) } }
        CappedSection(title: "Refunded", items: store.recentRefunds, limit: 3) { item in ReturnRow(item: item) { openReturn(item) } }
    }
}

// MARK: - Delivered

private struct DeliveredTab: View {
    @Environment(OrderStore.self) private var store
    let open: (Order) -> Void
    @State private var query = ""

    var body: some View {
        let all = store.deliveredHistory.filter { matches($0) }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let thisWeek = all.filter { ($0.deliveredAt ?? $0.lastUpdated) > weekAgo }
        let earlier = all.filter { ($0.deliveredAt ?? $0.lastUpdated) <= weekAgo }

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Search delivered", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

        if all.isEmpty {
            TabEmptyState(symbol: query.isEmpty ? "checkmark.circle" : "magnifyingglass",
                          title: query.isEmpty ? "Nothing delivered yet" : "No matches",
                          detail: query.isEmpty ? "Delivered packages from the last 60 days appear here." : "Try a store or item name.")
        }
        CappedSection(title: "This week", items: thisWeek, limit: 8) { item in DeliveredRow(order: item) { open(item) } }
        CappedSection(title: "Earlier", items: earlier, limit: 8) { item in DeliveredRow(order: item) { open(item) } }
    }

    private func matches(_ o: Order) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = ([o.title, o.merchant, o.orderNumber ?? "", o.trackingNumber ?? ""] + o.items.map(\.name)).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }
}

private struct DeliveredRow: View {
    let order: Order
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                OrderThumbnail(order: order, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(order.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(dateText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 44)
        }
        .buttonStyle(HoverButtonStyle())
        .keyboardHighlight(order.id)
        .contextMenu { OrderActions(order: order) }
    }

    private var subtitle: String {
        if order.deliveryInferred == true { return "\(order.merchant) · likely delivered" }
        if let returnBy = order.returnBy, returnBy > Date() {
            return "\(order.merchant) · return by \(returnBy.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return order.merchant
    }

    private var dateText: String {
        let at = order.deliveredAt ?? order.lastUpdated
        if Calendar.current.isDateInToday(at) { return at.formatted(date: .omitted, time: .shortened) }
        if Date().timeIntervalSince(at) < 6 * 86_400 { return at.formatted(.dateTime.weekday(.abbreviated)) }
        return at.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct TabEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Rows

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
                        Text(order.live?.isReadyForPickup == true ? "Ready for pickup" : order.status.label)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    Spacer()
                    Text(order.deliveryWindow ?? order.expectedByTime ?? "Today")
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
                        HStack(spacing: 6) {
                            Text(order.merchant)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            if order.signatureRequired == true { SignatureBadge() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                if order.status == .outForDelivery {
                    RouteProgress(color: color)
                } else {
                    ProgressDots(stage: order.stage, color: color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu { OrderActions(order: order) }
        .heroMatched("row-\(order.id)")
    }
}

/// A list row. The right side carries the one fact that matters for its section
/// (arrival day or time) or an exception in color; progress bars live on the Today
/// card and the detail screen, where they say something.
struct OrderRow: View {
    enum Context { case today, tomorrow, late, later }

    let order: Order
    let context: Context
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                OrderThumbnail(order: order, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if order.signatureRequired == true { SignatureBadge() }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(status.text)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                        .fixedSize()
                    SegmentBar(stage: order.stage, color: status.color)
                }
            }
            .padding(8)
            .frame(minHeight: 50)
        }
        .buttonStyle(HoverButtonStyle())
        .keyboardHighlight(order.id)
        .contextMenu { OrderActions(order: order) }
        .heroMatched("row-\(order.id)")
        .accessibilityElement(children: .combine)
    }

    /// Always present, so every row answers "where is it?" at a glance.
    private var status: (text: String, color: Color) {
        if context == .late && order.status != .delayed { return ("Late", Palette.orange) }
        // Due today but no "out for delivery" news (Amazon never emails that step): say what we know.
        if context == .today && order.status == .shipped { return ("Arriving today", Palette.blue) }
        return (order.live?.isReadyForPickup == true ? "Ready for pickup" : order.status.label, Palette.color(for: order.status))
    }

    /// Merchant, then the one timing fact for this section.
    private var subtitle: String {
        let eta = order.expectedDelivery
        func day(_ d: Date) -> String {
            d.timeIntervalSinceNow < 6 * 86_400 ? d.formatted(.dateTime.weekday(.abbreviated)) : d.formatted(.dateTime.month(.abbreviated).day())
        }
        let timing: String?
        switch context {
        case .late: timing = eta.map { "was due \(day($0))" }
        case .today: timing = order.deliveryWindow ?? order.expectedByTime
        case .tomorrow: timing = order.deliveryWindow
        case .later:
            if order.status == .ordered { timing = eta.map { "est. \(day($0))" } }
            else if order.status == .delayed { timing = eta.map { "now \(day($0))" } }
            else { timing = eta.map(day) }
        }
        return [order.merchant, timing].compactMap { $0 }.joined(separator: " · ")
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
