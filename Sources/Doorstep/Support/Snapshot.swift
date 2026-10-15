import AppKit
import SwiftUI

/// `Doorstep --snapshot <dir>` renders every screen with sample data to PNGs and
/// exits. Used to check layout without opening the menu bar panel.
enum Snapshot {
    static let directory: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static var isActive: Bool { directory != nil }

    /// `Doorstep --dump <gmail message id>` prints the text the parser sees for one email.
    static let dumpMessageID: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dump"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    /// `Doorstep --search "<gmail query>"` lists matching emails (id, sender, subject).
    static let searchQuery: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--search"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    @MainActor
    static func search(_ query: String, auth: GoogleAuth) async {
        do {
            let client = GmailClient(token: try await auth.validAccessToken())
            for id in try await client.listMessageIDs(query: query, limit: 25) {
                let m = try await client.message(id: id)
                print("\(id) | \(m.fromName) <\(m.fromAddress)> | \(m.subject)")
            }
        } catch {
            print("search failed: \(error)")
        }
    }

    @MainActor
    static func dump(id: String, auth: GoogleAuth) async {
        do {
            let msg = try await GmailClient(token: auth.validAccessToken()).message(id: id)
            let text = msg.html.map(HTMLText.plain(from:)) ?? msg.plainText ?? ""
            print("From: \(msg.fromName) <\(msg.fromAddress)>\nSubject: \(msg.subject)\nHas JSON-LD: \(msg.html?.contains("application/ld+json") ?? false)\n---")
            print(String(text.prefix(3000)))
            if let html = msg.html {
                print("--- images:")
                for c in ProductImage.candidates(in: html) {
                    print("  \(c.width.map(String.init) ?? "?")x\(c.height.map(String.init) ?? "?") alt=\"\(c.alt.prefix(40))\" \(c.src.prefix(140))")
                }
            }
        } catch {
            print("dump failed: \(error)")
        }
    }

    @MainActor
    static func run(store: OrderStore) {
        guard let dir = directory else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        store.deliveredExpanded = true

        let list = AnyView(OrderListView(open: { _ in }, openReturn: { _ in }, openSettings: {}, openSpending: {}))
        // A florist order: a confirmation with a delivery date and nothing after.
        let placed = Calendar.current.date(byAdding: .hour, value: -15, to: Date())!
        var local = Order(id: "local", merchant: "Corner Florist", items: [OrderItem(name: "Spring Tulip Bouquet")],
                          fallbackTitle: "", orderNumber: "25100417", status: .ordered, stage: 0,
                          expectedDelivery: Calendar.current.startOfDay(for: Date()), orderedAt: placed, total: "$64.50",
                          events: [OrderEvent(messageId: "sample-local", status: .ordered, date: placed)],
                          latestMessageId: "sample", latestThreadId: "sample", lastUpdated: placed)
        let localView = AnyView(OrderDetailView(order: local, back: {}))
        local.status = .delivered; local.stage = 3; local.markedDelivered = true
        local.deliveredAt = Date(); local.expectedDelivery = nil
        let scenes: [(String, AnyView)] = [
            ("list", list),
            ("list-returns", list),
            ("list-delivered", list),
            ("spending", AnyView(SpendingView(back: {}))),
            ("return-detail", AnyView(ReturnDetailView(item: store.returns[0], back: {}))),
            ("detail-signature", AnyView(OrderDetailView(order: store.order(id: "cable")!, back: {}))),
            ("detail-today", AnyView(OrderDetailView(order: store.order(id: "aero")!, back: {}))),
            ("detail-delayed", AnyView(OrderDetailView(order: store.order(id: "drip")!, back: {}))),
            ("detail-multi", AnyView(OrderDetailView(order: store.order(id: "supp")!, back: {}))),
            ("detail-local", localView),
            ("detail-local-marked", AnyView(OrderDetailView(order: local, back: {}))),
            ("settings", AnyView(SettingsView(back: {}))),
            ("onboarding", AnyView(OnboardingView())),
            ("setup-guide", AnyView(SetupGuideView(back: {}))),
        ]

        for scheme in [ColorScheme.dark, .light] {
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
            appearance.performAsCurrentDrawingAppearance {
                for (name, view) in scenes {
                    store.listTab = name == "list-returns" ? .returns : name == "list-delivered" ? .delivered : .arriving
                    let content = view
                        .environment(store)
                        .frame(width: 372)
                        .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.95))
                        .environment(\.colorScheme, scheme)
                    write(content, to: url.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }

        let states: [(String, OrderStore.MenuBarState)] = [
            ("menubar-idle", .init(text: nil, needsAttention: false)),
            ("menubar-count", .init(text: "7", needsAttention: false)),
            ("menubar-today", .init(text: "1 today", needsAttention: true)),
            ("menubar-window", .init(text: "10:30–2:30", needsAttention: false)),
            ("menubar-delivered", .init(text: "Delivered", needsAttention: false)),
        ]
        for (name, state) in states {
            let img = MenuBarLabel.render(state)
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url.appendingPathComponent("\(name).png"))
            }
        }
        print("Snapshots written to \(url.path)")
    }

    @MainActor
    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
