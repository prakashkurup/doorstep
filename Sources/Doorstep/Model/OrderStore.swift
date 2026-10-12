import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class OrderStore {
    private(set) var orders: [Order] = []
    private(set) var returns: [ReturnCase] = []
    private(set) var isSyncing = false
    /// Emails read so far in the current sync, out of `syncTotal` (0 when nothing new).
    private(set) var syncDone = 0
    private(set) var syncTotal = 0
    var syncProgress: Double? { syncTotal > 0 ? Double(syncDone) / Double(syncTotal) : nil }
    private(set) var lastSynced: Date?
    private(set) var lastError: String?
    private(set) var accountEmail: String?
    var deliveredExpanded = false
    /// Week strip filter; nil shows everything.
    var selectedDay: Date?

    enum ListTab: String, CaseIterable { case arriving, returns, delivered }
    var listTab: ListTab = .arriving
    /// Row highlighted with the arrow keys.
    var highlightedID: String?
    /// Which way the tab content slides.
    var tabMovedForward = true

    func selectTab(_ tab: ListTab) {
        let order = ListTab.allCases
        tabMovedForward = (order.firstIndex(of: tab) ?? 0) >= (order.firstIndex(of: listTab) ?? 0)
        highlightedID = nil
        selectedDay = nil
        withAnimation(.snappy(duration: 0.3)) { listTab = tab }
    }

    /// Orders in the order they appear on the current tab, for ↑/↓ navigation.
    var navigableOrders: [Order] {
        switch listTab {
        case .arriving: selectedDay.map { arrivals(on: $0) } ?? (today + tomorrow + late + later)
        case .returns: openReturnWindows
        case .delivered: deliveredHistory
        }
    }

    func moveHighlight(by step: Int) {
        let list = navigableOrders
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == highlightedID }
        let next = current.map { min(max($0 + step, 0), list.count - 1) } ?? (step > 0 ? 0 : list.count - 1)
        withAnimation(.snappy(duration: 0.15)) { highlightedID = list[next].id }
    }

    /// Fires the menu bar icon's bounce (out for delivery) or wiggle (delivered).
    struct MenuBarPulse: Equatable {
        enum Kind { case outForDelivery, delivered }
        let kind: Kind
        let token = UUID()
    }
    private(set) var menuBarPulse: MenuBarPulse?

    /// Tracking numbers pasted into the panel, with no email behind them.
    private(set) var manualOrders: [Order] = []
    /// Orders the user marked as received themselves.
    private var receivedOverrides: [String: Date] = [:]
    /// Bumped when product photos finish downloading so thumbnails redraw.
    private(set) var imagesVersion = 0

    // Live tracking: official carrier APIs first, 17TRACK as an optional catch-all.
    private(set) var connectedCarriers: Set<CarrierCredentials.Kind> = Snapshot.isActive ? []
        : Set(CarrierCredentials.Kind.allCases.filter { CarrierCredentials.load($0) != nil })
    private(set) var hasLiveTrackingKey = Snapshot.isActive ? false : Keychain.get(TrackingService.keychainAccount) != nil
    var isLiveTrackingOn: Bool { !connectedCarriers.isEmpty || hasLiveTrackingKey }
    private(set) var liveError: String?
    private(set) var liveQuota: (used: Int, total: Int)?
    private var liveCache: [String: LiveTracking] = [:]
    private var registeredNumbers: Set<String> = []

    var isSampleMode: Bool {
        didSet {
            guard !Snapshot.isActive else { return }
            UserDefaults.standard.set(isSampleMode, forKey: "sampleMode")
            reloadSampleIfNeeded()
        }
    }
    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            Notifier.shared.scheduleReturnReminders(for: notificationsEnabled ? returnReminderCandidates : [])
        }
    }

    let auth = GoogleAuth()
    private var findingsCache: [String: EmailFinding] = [:]
    private var nonOrderIDs: Set<String> = []
    private var hiddenIDs: Set<String> = []
    private var knownStatuses: [String: OrderStatus] = [:]
    private var builtOrders: [Order] = []

    var isConnected: Bool { auth.isSignedIn }
    var showsOnboarding: Bool { !isConnected && !isSampleMode }

    init() {
        if Snapshot.isActive {
            isSampleMode = true
            notificationsEnabled = true
            orders = SampleData.orders()
            returns = SampleData.returns()
            lastSynced = Date().addingTimeInterval(-120)
            return
        }
        isSampleMode = UserDefaults.standard.bool(forKey: "sampleMode")
        notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        loadState()
        reloadSampleIfNeeded()
        Notifier.shared.setUp()
        startAutoRefresh()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        if isConnected { Task { await refresh() } }
    }

    // MARK: Sections

    private var visible: [Order] { orders.filter { !hiddenIDs.contains($0.id) } }
    private var active: [Order] { visible.filter(\.isActive) }

    var today: [Order] {
        active.filter { $0.status == .outForDelivery || isToday($0.expectedDelivery) }
            .sorted { $0.lastUpdated > $1.lastUpdated }
    }

    var tomorrow: [Order] {
        active.filter { $0.status != .outForDelivery && isTomorrow($0.expectedDelivery) }
            .sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// Expected before today, not delivered, and not out for delivery.
    var late: [Order] {
        let start = Calendar.current.startOfDay(for: Date())
        return active.filter { $0.status != .outForDelivery && ($0.expectedDelivery.map { $0 < start } ?? false) }
            .sorted { ($0.expectedDelivery ?? .distantPast) < ($1.expectedDelivery ?? .distantPast) }
    }

    var later: [Order] {
        let shown = Set((today + tomorrow + late).map(\.id))
        return active.filter { !shown.contains($0.id) }.sorted {
            switch ($0.expectedDelivery, $1.expectedDelivery) {
            case let (a?, b?): a < b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.lastUpdated > $1.lastUpdated
            }
        }
    }

    var delivered: [Order] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return visible.filter { $0.status == .delivered && ($0.deliveredAt ?? $0.lastUpdated) > cutoff }
            .sorted { ($0.deliveredAt ?? $0.lastUpdated) > ($1.deliveredAt ?? $1.lastUpdated) }
    }

    /// Everything delivered, newest first (the Delivered tab).
    var deliveredHistory: [Order] {
        visible.filter { $0.status == .delivered }
            .sorted { ($0.deliveredAt ?? $0.lastUpdated) > ($1.deliveredAt ?? $1.lastUpdated) }
    }

    /// Return windows still open, soonest first (the Returns tab).
    var openReturnWindows: [Order] {
        let start = Calendar.current.startOfDay(for: Date())
        return returnable.filter { ($0.returnBy ?? .distantPast) >= start }
            .sorted { ($0.returnBy ?? .distantFuture) < ($1.returnBy ?? .distantFuture) }
    }

    /// Windows closing within 3 days: surfaced as one line on the Arriving tab,
    /// unless dismissed (they stay listed on the Returns tab either way).
    var urgentReturnWindows: [Order] {
        let limit = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3 * 86_400)
        return openReturnWindows.filter { ($0.returnBy ?? .distantFuture) <= limit && !dismissedNudges.contains($0.id) }
    }

    private(set) var dismissedNudges: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "dismissedReturnNudges") ?? [])

    func dismissNudge(for order: Order) {
        dismissedNudges.insert(order.id)
        UserDefaults.standard.set(Array(dismissedNudges), forKey: "dismissedReturnNudges")
    }

    var activeReturns: [ReturnCase] { returns.filter(\.isActive).sorted { $0.lastUpdated > $1.lastUpdated } }

    var recentRefunds: [ReturnCase] {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return returns.filter { !$0.isActive && $0.lastUpdated > cutoff }.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    var arrivingCount: Int { active.count }
    /// Returns in progress plus windows closing within a week.
    var returnsCount: Int { activeReturns.count + returnsClosing.count }

    /// The week strip earns its space only when packages spread over several days.
    var showsWeekStrip: Bool {
        weekDays.filter { !arrivals(on: $0).isEmpty }.count >= 3
    }

    /// Delivered orders whose return window closes within a week and haven't been returned.
    var returnsClosing: [Order] {
        let now = Date()
        let soon = now.addingTimeInterval(7 * 86_400)
        return returnable.filter { ($0.returnBy ?? .distantPast) >= Calendar.current.startOfDay(for: now) && ($0.returnBy ?? .distantFuture) <= soon }
            .sorted { ($0.returnBy ?? .distantFuture) < ($1.returnBy ?? .distantFuture) }
    }

    /// Returns in progress, plus refunds from the last two weeks.
    var visibleReturns: [ReturnCase] {
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        return returns.filter { $0.isActive || $0.lastUpdated > cutoff }
            .sorted { ($0.isActive ? 0 : 1, $1.lastUpdated) < ($1.isActive ? 0 : 1, $0.lastUpdated) }
    }

    var isEmpty: Bool { today.isEmpty && tomorrow.isEmpty && later.isEmpty && delivered.isEmpty && visibleReturns.isEmpty }

    func order(id: String) -> Order? { orders.first { $0.id == id } }
    func returnCase(id: String) -> ReturnCase? { returns.first { $0.id == id } }

    func returnCase(for order: Order) -> ReturnCase? {
        guard let number = order.orderNumber?.uppercased().filter({ $0.isLetter || $0.isNumber }) else { return nil }
        return returns.first { $0.orderNumber?.uppercased().filter({ $0.isLetter || $0.isNumber }) == number && !$0.isRefundOnly }
    }

    private var returnable: [Order] {
        visible.filter { $0.status == .delivered && $0.returnBy != nil && returnCase(for: $0) == nil }
    }

    private var returnReminderCandidates: [Order] {
        returnable.filter { ($0.returnBy ?? .distantPast) > Date() }
    }

    private func isToday(_ date: Date?) -> Bool { date.map(Calendar.current.isDateInToday) ?? false }
    private func isTomorrow(_ date: Date?) -> Bool { date.map(Calendar.current.isDateInTomorrow) ?? false }

    // MARK: Week strip

    var weekDays: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    func arrivals(on day: Date) -> [Order] {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return today }
        return active.filter { o in
            o.status != .outForDelivery && (o.expectedDelivery.map { cal.isDate($0, inSameDayAs: day) } ?? false)
        }
    }

    // MARK: Spending

    struct StoreSpend: Identifiable, Hashable {
        var id: String { store }
        let store: String
        let amount: Double
        let orders: Int
    }

    struct MonthSpending {
        let month: Date
        let total: Double
        let orderCount: Int
        let missingTotals: Int
        /// Stores whose emails had no price (e.g. only a carrier's shipping notice).
        let missingStores: [String]
        let refunds: Double
        let stores: [StoreSpend]
    }

    nonisolated static func amount(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text.filter { $0.isNumber || $0 == "." })
    }

    /// Months that have at least one order, newest first.
    var spendingMonths: [Date] {
        let cal = Calendar.current
        let months = Set(orders.compactMap { o in (o.orderedAt ?? o.events.first?.date).flatMap { cal.dateInterval(of: .month, for: $0)?.start } })
        return months.sorted(by: >)
    }

    func spending(for month: Date) -> MonthSpending {
        let cal = Calendar.current
        let inMonth = orders.filter { o in
            guard let d = o.orderedAt ?? o.events.first?.date else { return false }
            return cal.isDate(d, equalTo: month, toGranularity: .month)
        }
        // Group by the store's website so "Columbia" and "Columbia Sportswear" are one store;
        // show the shortest name seen for it.
        var byStore: [String: (Double, Int)] = [:]
        var names: [String: String] = [:]
        var total = 0.0
        var missing = 0
        var missingStores: [String] = []
        for o in inMonth {
            guard let value = Self.amount(o.total) else {
                missing += 1
                if !missingStores.contains(o.merchant) { missingStores.append(o.merchant) }
                continue
            }
            let key = o.merchantDomain ?? o.merchant.lowercased()
            if names[key].map({ o.merchant.count < $0.count }) ?? true { names[key] = o.merchant }
            total += value
            byStore[key, default: (0, 0)].0 += value
            byStore[key, default: (0, 0)].1 += 1
        }
        let refunds = returns.filter { r in
            r.status == .refunded && cal.isDate(r.lastUpdated, equalTo: month, toGranularity: .month)
        }.compactMap { Self.amount($0.refundAmount) }.reduce(0, +)

        var stores = byStore.map { StoreSpend(store: names[$0.key] ?? $0.key, amount: $0.value.0, orders: $0.value.1) }
            .sorted { $0.amount > $1.amount }
        // More than six stores: fold the tail into "Other" rather than adding rows.
        if stores.count > 6 {
            let tail = stores[5...]
            stores = Array(stores[..<5]) + [StoreSpend(store: "Other", amount: tail.map(\.amount).reduce(0, +), orders: tail.map(\.orders).reduce(0, +))]
        }
        return MonthSpending(month: month, total: total, orderCount: inMonth.count, missingTotals: missing,
                             missingStores: missingStores, refunds: refunds, stores: stores)
    }

    // MARK: Menu bar

    struct MenuBarState: Equatable {
        var text: String?
        var needsAttention: Bool
    }

    var menuBarState: MenuBarState {
        guard !showsOnboarding else { return .init(text: nil, needsAttention: false) }
        let attention = active.contains { $0.status == .delayed }
        if let recent = delivered.first?.deliveredAt, Date().timeIntervalSince(recent) < 3600 {
            return .init(text: "Delivered", needsAttention: attention)
        }
        if today.count == 1, let window = Self.compactWindow(today[0].live) {
            return .init(text: window, needsAttention: attention)
        }
        if !today.isEmpty { return .init(text: "\(today.count) today", needsAttention: attention) }
        if !active.isEmpty { return .init(text: "\(active.count)", needsAttention: attention) }
        return .init(text: nil, needsAttention: false)
    }

    /// "10:30–2:30" for the menu bar.
    static func compactWindow(_ live: LiveTracking?) -> String? {
        guard let from = live?.estimatedFrom, let to = live?.estimatedTo, to > from,
              Calendar.current.isDateInToday(from), Calendar.current.isDate(from, inSameDayAs: to) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return "\(f.string(from: from))–\(f.string(from: to))"
    }

    // MARK: Actions

    func connect() async {
        do {
            try await auth.signIn()
            isSampleMode = false
            lastError = nil
            Notifier.shared.requestPermission()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        auth.signOut()
        orders = []
        returns = []
        findingsCache = [:]
        nonOrderIDs = []
        knownStatuses = [:]
        accountEmail = nil
        lastSynced = nil
        saveState()
    }

    func hide(_ order: Order) {
        hiddenIDs.insert(order.id)
        saveState()
    }

    func saveLiveTrackingKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.set(trimmed, for: TrackingService.keychainAccount)
        hasLiveTrackingKey = true
        liveError = nil
        await refreshLive(force: true)
    }

    /// Saves a carrier's credentials after checking them. Returns an error message on failure.
    func connectCarrier(_ kind: CarrierCredentials.Kind, id: String, secret: String?) async -> String? {
        let creds = CarrierCredentials(id: id.trimmingCharacters(in: .whitespacesAndNewlines),
                                       secret: secret?.trimmingCharacters(in: .whitespacesAndNewlines))
        TokenCache.shared.clear(kind.rawValue)
        do {
            try await kind.tracker(creds).verify()
        } catch {
            return error.localizedDescription
        }
        CarrierCredentials.save(kind, creds)
        connectedCarriers.insert(kind)
        await refreshLive(force: true)
        saveState()
        return nil
    }

    func disconnectCarrier(_ kind: CarrierCredentials.Kind) {
        CarrierCredentials.delete(kind)
        connectedCarriers.remove(kind)
        // Drop cached results that came from this carrier so email takes over again.
        liveCache = liveCache.filter { $0.value.carrierName != kind.name }
        publish()
        saveState()
    }

    func removeLiveTrackingKey() {
        Keychain.delete(TrackingService.keychainAccount)
        hasLiveTrackingKey = false
        liveCache = [:]
        registeredNumbers = []
        liveQuota = nil
        publish()
        saveState()
    }

    var liveTrackedCount: Int { orders.filter { $0.live != nil && $0.isActive }.count }

    func refresh() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        syncDone = 0
        syncTotal = 0
        defer { isSyncing = false; syncTotal = 0; syncDone = 0 }
        do {
            let token = try await auth.validAccessToken()
            let client = GmailClient(token: token)
            if accountEmail == nil { accountEmail = try? await client.profileEmail() }

            let ids = try await client.listMessageIDs()
            let newIDs = ids.filter { findingsCache[$0] == nil && !nonOrderIDs.contains($0) }
            syncTotal = newIDs.count

            // Fetch in small parallel batches; the on-device model runs one email at a time.
            for batch in newIDs.chunked(6) {
                let messages = try await withThrowingTaskGroup(of: GmailMessage.self) { group in
                    for id in batch { group.addTask { try await client.message(id: id) } }
                    return try await group.reduce(into: []) { $0.append($1) }
                }
                for msg in messages {
                    if let finding = await OrderExtractor.extract(msg) {
                        findingsCache[msg.id] = finding
                    } else {
                        nonOrderIDs.insert(msg.id)
                    }
                    withAnimation(.easeOut(duration: 0.3)) { syncDone += 1 }
                }
                // Show progress during a long first sync instead of an empty list.
                if orders.isEmpty || newIDs.count > 12 {
                    builtOrders = OrderBuilder.build(from: Array(findingsCache.values))
                    publish()
                }
            }

            let keep = Set(ids)
            findingsCache = findingsCache.filter { keep.contains($0.key) }
            nonOrderIDs = nonOrderIDs.intersection(keep)

            let findings = Array(findingsCache.values)
            builtOrders = OrderBuilder.build(from: findings)
            returns = OrderBuilder.buildReturns(from: findings, orders: builtOrders)
            await refreshLive(force: false)
            lastSynced = Date()
            lastError = nil
            saveState()
            Notifier.shared.scheduleReturnReminders(for: notificationsEnabled ? returnReminderCandidates : [])

            let photosAdded = await ImageStore.prefetch((orders.compactMap(\.imageURL) + returns.compactMap(\.imageURL)))
            let domains = orders.flatMap { [$0.merchantDomain, $0.carrierDomain].compactMap { $0 } } + returns.compactMap(\.merchantDomain)
            let logosAdded = await LogoStore.prefetch(domains)
            if photosAdded || logosAdded { imagesVersion += 1 }
        } catch AuthError.notSignedIn {
            lastError = "Gmail disconnected. Connect again in Settings."
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Live tracking

    private static func normalizedNumber(_ s: String) -> String { s.uppercased().filter { $0.isLetter || $0.isNumber } }

    /// Numbers worth asking the carrier about: moving packages, plus ones we only guessed
    /// were delivered. Amazon's own TBA numbers can't be tracked outside Amazon.
    private func trackableNumbers(in list: [Order]) -> [String: Order] {
        var result: [String: Order] = [:]
        for o in list where o.isActive || o.deliveryInferred == true {
            guard o.isGrocery != true, let t = o.trackingNumber.map(Self.normalizedNumber), t.count >= 8,
                  !t.hasPrefix("TBA") else { continue }
            result[t] = o
        }
        return result
    }

    private func isDue(_ number: String, _ order: Order, force: Bool, now: Date) -> Bool {
        guard let cached = liveCache[number] else { return true }
        if cached.status == "Delivered" { return false }
        let interval: TimeInterval = (cached.status == "OutForDelivery" || order.status == .outForDelivery) ? 10 * 60 : 30 * 60
        return force || now.timeIntervalSince(cached.lastChecked) >= interval
    }

    private func refreshLive(force: Bool) async {
        defer { publish(); announceChanges(in: orders) }
        let candidates = trackableNumbers(in: baseOrders)
        guard !candidates.isEmpty else { return }
        let now = Date()
        var errors: [String] = []

        // 1. Official carrier APIs, for carriers with saved credentials.
        var jobs: [(number: String, tracker: CarrierTracker)] = []
        var handledOfficially = Set<String>()
        for (number, order) in candidates {
            guard let kind = CarrierCredentials.kind(for: order.carrier), connectedCarriers.contains(kind),
                  let creds = CarrierCredentials.load(kind) else { continue }
            handledOfficially.insert(number)
            if isDue(number, order, force: force, now: now) { jobs.append((number, kind.tracker(creds))) }
        }
        for batch in jobs.chunked(4) {
            let results = await withTaskGroup(of: (String, Result<LiveTracking?, Error>).self) { group in
                for job in batch {
                    group.addTask {
                        do { return (job.number, .success(try await job.tracker.track(job.number))) }
                        catch { return (job.number, .failure(error)) }
                    }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
            for (number, result) in results {
                switch result {
                case .success(let info?): liveCache[number] = info
                case .success(nil): break   // carrier doesn't know this number (yet)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
        }

        // 2. 17TRACK for everything else, if a key is saved.
        if let key = Keychain.get(TrackingService.keychainAccount) {
            let service = TrackingService(key: key)
            let rest = candidates.filter { !handledOfficially.contains($0.key) }
            do {
                let unregistered = rest.keys.filter { !registeredNumbers.contains($0) }
                if !unregistered.isEmpty {
                    registeredNumbers.formUnion(try await service.register(Array(unregistered)))
                }
                let due = rest.filter { registeredNumbers.contains($0.key) && isDue($0.key, $0.value, force: force, now: now) }.map(\.key)
                if !due.isEmpty {
                    for (number, info) in try await service.trackInfo(due) { liveCache[Self.normalizedNumber(number)] = info }
                }
                liveQuota = await service.quota()
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        liveError = errors.first
    }

    /// Carrier data beats email when it's newer; "delivered" from the carrier is final.
    private func applyLive(_ list: [Order]) -> [Order] {
        let cal = Calendar.current
        return list.map { original in
            guard let number = original.trackingNumber.map(Self.normalizedNumber), let live = liveCache[number] else { return original }
            var o = original
            o.live = live
            if let mapped = live.mappedStatus {
                let liveDate = live.events.first?.date ?? live.lastChecked
                if mapped == .delivered || o.deliveryInferred == true || liveDate >= o.lastUpdated.addingTimeInterval(-3600) {
                    o.status = mapped
                    o.stage = mapped == .delayed ? max(min(o.stage, 2), 1) : mapped.naturalStage
                    o.deliveryInferred = nil
                    o.lastUpdated = max(o.lastUpdated, liveDate)
                    if mapped == .delivered {
                        o.deliveredAt = live.events.first?.date ?? o.deliveredAt
                        o.expectedDelivery = nil
                        if o.returnBy == nil || o.returnByEstimated == true, let at = o.deliveredAt,
                           let days = ReturnPolicy.defaultDays(for: o.merchant), o.isGrocery != true {
                            o.returnBy = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: at))
                            o.returnByEstimated = true
                        }
                    }
                }
            }
            if o.status != .delivered, let from = live.estimatedFrom ?? live.estimatedTo {
                o.expectedDelivery = cal.startOfDay(for: from)
                if let to = live.estimatedTo, to > from, cal.isDate(from, inSameDayAs: to) {
                    o.deliveryWindow = "\(from.formatted(date: .omitted, time: .shortened)) – \(to.formatted(date: .omitted, time: .shortened))"
                }
            }
            return o
        }
    }

    // MARK: Publishing

    /// Email orders (or the sample set), before live data and the user's own changes.
    private var baseOrders: [Order] {
        let emailOrders = (isSampleMode && !isConnected) || Snapshot.isActive ? SampleData.orders() : builtOrders
        let known = Set(emailOrders.compactMap { $0.trackingNumber.map(Self.normalizedNumber) })
        return emailOrders + manualOrders.filter { !known.contains(Self.normalizedNumber($0.trackingNumber ?? "")) }
    }

    /// The one place the visible list is set, animated so rows glide between sections.
    private func publish() {
        let next = applyOverrides(applyLive(baseOrders))
        withAnimation(.snappy(duration: 0.35)) { orders = next }
    }

    private func applyOverrides(_ list: [Order]) -> [Order] {
        list.map { original in
            guard let at = receivedOverrides[original.id], original.status != .delivered else { return original }
            var o = original
            o.status = .delivered
            o.stage = 3
            o.deliveredAt = at
            o.deliveryInferred = nil
            o.expectedDelivery = nil
            if o.returnBy == nil, o.isGrocery != true, let days = ReturnPolicy.defaultDays(for: o.merchant) {
                o.returnBy = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: at))
                o.returnByEstimated = true
            }
            return o
        }
    }

    func markReceived(_ order: Order) {
        receivedOverrides[order.id] = Date()
        publish()
        saveState()
    }

    /// Adds a pasted tracking number. Returns a short message for the panel.
    @discardableResult
    func addTrackingNumber(_ raw: String) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = Heuristics.tracking(in: text) ?? Self.normalizedNumber(text)
        let carrier = Carrier.detect(tracking: number, name: nil, merchant: "")
        guard number.count >= 10, number.count <= 34, number.contains(where: \.isNumber), carrier != .other || Heuristics.tracking(in: text) != nil else {
            return "That doesn't look like a tracking number."
        }
        if orders.contains(where: { $0.trackingNumber.map(Self.normalizedNumber) == Self.normalizedNumber(number) }) {
            return "Already tracking \(number)."
        }
        let name = carrier == .other ? "Carrier" : carrier.displayName
        let order = Order(
            id: "m:" + Self.normalizedNumber(number), merchant: name, items: [], fallbackTitle: "Package via \(name)",
            carrierName: carrier == .other ? nil : name, trackingNumber: number, orderNumber: nil,
            status: .shipped, stage: 1, expectedDelivery: nil, expectedByTime: nil, originalExpected: nil,
            orderedAt: nil, deliveredAt: nil, total: nil, events: [],
            latestMessageId: "manual", latestThreadId: "manual", lastUpdated: Date()
        )
        manualOrders.append(order)
        listTab = .arriving
        publish()
        saveState()
        await refreshLive(force: true)
        return isLiveTrackingOn ? "Tracking \(number)." : "Added \(number). Connect \(name) in Settings for live status."
    }

    private func announceChanges(in newOrders: [Order]) {
        let firstSync = knownStatuses.isEmpty
        for order in newOrders {
            let previous = knownStatuses[order.id]
            knownStatuses[order.id] = order.status
            guard !firstSync, previous != order.status, !hiddenIDs.contains(order.id) else { continue }
            // Only fresh news: skip updates older than a day (e.g. a backfill).
            guard Date().timeIntervalSince(order.lastUpdated) < 86_400 else { continue }
            if order.status == .outForDelivery { menuBarPulse = MenuBarPulse(kind: .outForDelivery) }
            if order.status == .delivered { menuBarPulse = MenuBarPulse(kind: .delivered) }
            if notificationsEnabled { Notifier.shared.announce(order) }
        }
    }

    private func startAutoRefresh() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(15 * 60))
                await self?.refresh()
            }
        }
    }

    private func reloadSampleIfNeeded() {
        if isSampleMode && !isConnected {
            orders = SampleData.orders()
            returns = SampleData.returns()
            lastSynced = Date()
        } else if !isSampleMode && !isConnected {
            orders = []
            returns = []
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Couldn't change launch at login: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Persistence

    /// Bump when extraction rules change so cached emails are read again.
    private static let parserVersion = 14

    private struct SavedState: Codable {
        var parserVersion: Int?
        var orders: [Order]
        var returns: [ReturnCase]?
        var findings: [String: EmailFinding]
        var nonOrderIDs: Set<String>
        var hiddenIDs: Set<String>
        var knownStatuses: [String: OrderStatus]
        var lastSynced: Date?
        var accountEmail: String?
        var liveCache: [String: LiveTracking]?
        var registeredNumbers: Set<String>?
        var manualOrders: [Order]?
        var receivedOverrides: [String: Date]?
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: AppPaths.stateFile),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        hiddenIDs = state.hiddenIDs
        liveCache = state.liveCache ?? [:]
        registeredNumbers = state.registeredNumbers ?? []
        guard state.parserVersion == Self.parserVersion else { return }
        findingsCache = state.findings
        nonOrderIDs = state.nonOrderIDs
        knownStatuses = state.knownStatuses
        accountEmail = state.accountEmail
        if isConnected {
            builtOrders = state.orders
            manualOrders = state.manualOrders ?? []
            receivedOverrides = state.receivedOverrides ?? [:]
            orders = applyOverrides(applyLive(builtOrders + manualOrders))
            returns = state.returns ?? []
            lastSynced = state.lastSynced
        }
    }

    private func saveState() {
        guard !Snapshot.isActive else { return }
        let sample = isSampleMode && !isConnected
        let state = SavedState(parserVersion: Self.parserVersion, orders: sample ? [] : builtOrders, returns: sample ? [] : returns,
                               findings: findingsCache, nonOrderIDs: nonOrderIDs, hiddenIDs: hiddenIDs,
                               knownStatuses: knownStatuses, lastSynced: lastSynced, accountEmail: accountEmail,
                               liveCache: liveCache, registeredNumbers: registeredNumbers,
                               manualOrders: manualOrders, receivedOverrides: receivedOverrides)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: AppPaths.stateFile, options: .atomic)
    }
}
