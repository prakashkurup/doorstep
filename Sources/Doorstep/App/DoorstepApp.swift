import AppKit
import SwiftUI

@main
struct DoorstepApp: App {
    @State private var store: OrderStore

    init() {
        let store = OrderStore()
        _store = State(initialValue: store)
        if Snapshot.isActive {
            Snapshot.run(store: store)
            exit(0)
        }
        if !Snapshot.isActive { GlobalHotKey.register() }
        if let query = Snapshot.searchQuery {
            Task { @MainActor in
                await Snapshot.search(query, auth: store.auth)
                exit(0)
            }
        }
        if let id = Snapshot.dumpMessageID {
            Task { @MainActor in
                await Snapshot.dump(id: id, auth: store.auth)
                exit(0)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            MenuBarLabel(state: store.menuBarState, pulse: store.menuBarPulse)
        }
        .menuBarExtraStyle(.window)
    }
}

struct PopoverView: View {
    @Environment(OrderStore.self) private var store
    @State private var route: Route = .list
    @Namespace private var hero

    enum Route: Equatable {
        case list, detail(String), returnDetail(String), settings, spending
    }

    var body: some View {
        ZStack {
            if store.showsOnboarding {
                OnboardingView()
            } else {
                switch route {
                case .list:
                    OrderListView(open: { order in go(.detail(order.id)) },
                                  openReturn: { item in go(.returnDetail(item.id)) },
                                  openSettings: { go(.settings) },
                                  openSpending: { go(.spending) })
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .detail(let id):
                    if let order = store.order(id: id) {
                        OrderDetailView(order: order, back: { go(.list) })
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        Color.clear.onAppear { route = .list }
                    }
                case .returnDetail(let id):
                    if let item = store.returnCase(id: id) {
                        ReturnDetailView(item: item, back: { go(.list) })
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        Color.clear.onAppear { route = .list }
                    }
                case .settings:
                    SettingsView(back: { go(.list) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .spending:
                    SpendingView(back: { go(.list) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .environment(\.heroNamespace, hero)
        .frame(width: 372)
        .clipped()
    }

    private func go(_ next: Route) {
        withAnimation(.snappy(duration: 0.25)) { route = next }
    }
}

/// Rendered to a template image so the icon, text and warning mark sit together
/// and follow the menu bar's light/dark tint.
struct MenuBarLabel: View {
    let state: OrderStore.MenuBarState
    var pulse: OrderStore.MenuBarPulse?
    /// Current animation frame for the box: vertical offset and tilt.
    @State private var pose = (dy: CGFloat(0), angle: Double(0))

    var body: some View {
        Image(nsImage: Self.render(state, dy: pose.dy, angle: pose.angle))
            .accessibilityLabel(state.text.map { "Doorstep, \($0)" } ?? "Doorstep")
            .onChange(of: pulse) { _, pulse in
                guard let pulse else { return }
                animate(pulse.kind)
            }
    }

    /// The menu bar shows a rendered image, so animate by stepping through a few frames:
    /// a hop when something heads out for delivery, a happy wiggle when it's delivered.
    private func animate(_ kind: OrderStore.MenuBarPulse.Kind) {
        let frames: [(CGFloat, Double)] = kind == .outForDelivery
            ? [(-2, 0), (-3.5, 0), (-2, 0), (0, 0), (-1.5, 0), (0, 0)]
            : [(0, -14), (0, 12), (0, -9), (0, 6), (0, -3), (0, 0)]
        Task { @MainActor in
            for frame in frames {
                pose = (frame.0, frame.1)
                try? await Task.sleep(for: .milliseconds(70))
            }
            pose = (0, 0)
        }
    }

    @MainActor
    static func render(_ state: OrderStore.MenuBarState, dy: CGFloat = 0, angle: Double = 0) -> NSImage {
        let view = HStack(spacing: 4) {
            Image(systemName: "shippingbox")
                .font(.system(size: 13.5, weight: .medium))
                .rotationEffect(.degrees(angle))
                .offset(y: dy)
            if let text = state.text {
                Text(text).font(.system(size: 13, weight: .medium))
            }
            if state.needsAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(.black)
        .padding(.vertical, 2)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }
}
