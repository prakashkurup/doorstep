import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class OrderStore {
    private(set) var orders: [Order] = []
    private(set) var isSyncing = false
    private(set) var lastSynced: Date?
    private(set) var lastError: String?
    private(set) var accountEmail: String?
    var deliveredExpanded = false
    /// Bumped when product photos finish downloading so thumbnails redraw.
    private(set) var imagesVersion = 0

    var isSampleMode: Bool {
        didSet {
            guard !Snapshot.isActive else { return }
            UserDefaults.standard.set(isSampleMode, forKey: "sampleMode")
            reloadSampleIfNeeded()
        }
    }
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    let auth = GoogleAuth()
    private var findingsCache: [String: EmailFinding] = [:]
    private var nonOrderIDs: Set<String> = []
    private var hiddenIDs: Set<String> = []
    private var knownStatuses: [String: OrderStatus] = [:]

    var isConnected: Bool { auth.isSignedIn }
    var showsOnboarding: Bool { !isConnected && !isSampleMode }

    init() {
        if Snapshot.isActive {
            isSampleMode = true
            notificationsEnabled = true
            orders = SampleData.orders()
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

    var later: [Order] {
        let shown = Set((today + tomorrow).map(\.id))
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

    var isEmpty: Bool { today.isEmpty && tomorrow.isEmpty && later.isEmpty && delivered.isEmpty }

    func order(id: String) -> Order? { orders.first { $0.id == id } }

    private func isToday(_ date: Date?) -> Bool { date.map(Calendar.current.isDateInToday) ?? false }
    private func isTomorrow(_ date: Date?) -> Bool { date.map(Calendar.current.isDateInTomorrow) ?? false }

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
        if !today.isEmpty { return .init(text: "\(today.count) today", needsAttention: attention) }
        if !active.isEmpty { return .init(text: "\(active.count)", needsAttention: attention) }
        return .init(text: nil, needsAttention: false)
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

    func refresh() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await auth.validAccessToken()
            let client = GmailClient(token: token)
            if accountEmail == nil { accountEmail = try? await client.profileEmail() }

            let ids = try await client.listMessageIDs()
            let newIDs = ids.filter { findingsCache[$0] == nil && !nonOrderIDs.contains($0) }

            // Fetch in small parallel batches; the on-device model runs one email at a time.
            for batch in stride(from: 0, to: newIDs.count, by: 6).map({ Array(newIDs[$0..<min($0 + 6, newIDs.count)]) }) {
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
                }
                // Show progress during a long first sync instead of an empty list.
                if orders.isEmpty || newIDs.count > 12 {
                    orders = OrderBuilder.build(from: Array(findingsCache.values))
                }
            }

            let keep = Set(ids)
            findingsCache = findingsCache.filter { keep.contains($0.key) }
            nonOrderIDs = nonOrderIDs.intersection(keep)

            let built = OrderBuilder.build(from: Array(findingsCache.values))
            announceChanges(in: built)
            orders = built
            lastSynced = Date()
            lastError = nil
            saveState()
            let photosAdded = await ImageStore.prefetch(built.compactMap(\.imageURL))
            let logosAdded = await LogoStore.prefetch(built.flatMap { [$0.merchantDomain, $0.carrierDomain].compactMap { $0 } })
            if photosAdded || logosAdded { imagesVersion += 1 }
        } catch AuthError.notSignedIn {
            lastError = "Gmail disconnected. Connect again in Settings."
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func announceChanges(in newOrders: [Order]) {
        let firstSync = knownStatuses.isEmpty
        for order in newOrders {
            let previous = knownStatuses[order.id]
            knownStatuses[order.id] = order.status
            guard !firstSync, notificationsEnabled, previous != order.status, !hiddenIDs.contains(order.id) else { continue }
            // Only fresh news: skip emails older than a day (e.g. a backfill).
            guard Date().timeIntervalSince(order.lastUpdated) < 86_400 else { continue }
            Notifier.shared.announce(order)
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
            lastSynced = Date()
        } else if !isSampleMode && !isConnected {
            orders = []
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
    private static let parserVersion = 10

    private struct SavedState: Codable {
        var parserVersion: Int?
        var orders: [Order]
        var findings: [String: EmailFinding]
        var nonOrderIDs: Set<String>
        var hiddenIDs: Set<String>
        var knownStatuses: [String: OrderStatus]
        var lastSynced: Date?
        var accountEmail: String?
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: AppPaths.stateFile),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        hiddenIDs = state.hiddenIDs
        guard state.parserVersion == Self.parserVersion else { return }
        findingsCache = state.findings
        nonOrderIDs = state.nonOrderIDs
        knownStatuses = state.knownStatuses
        accountEmail = state.accountEmail
        if isConnected {
            orders = state.orders
            lastSynced = state.lastSynced
        }
    }

    private func saveState() {
        guard !Snapshot.isActive else { return }
        let state = SavedState(parserVersion: Self.parserVersion, orders: isSampleMode && !isConnected ? [] : orders, findings: findingsCache,
                               nonOrderIDs: nonOrderIDs, hiddenIDs: hiddenIDs, knownStatuses: knownStatuses,
                               lastSynced: lastSynced, accountEmail: accountEmail)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: AppPaths.stateFile, options: .atomic)
    }
}
