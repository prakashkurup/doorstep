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
            MenuBarLabel(state: store.menuBarState)
        }
        .menuBarExtraStyle(.window)
    }
}

struct PopoverView: View {
    @Environment(OrderStore.self) private var store
    @State private var route: Route = .list

    enum Route: Equatable {
        case list, detail(String), settings
    }

    var body: some View {
        ZStack {
            if store.showsOnboarding {
                OnboardingView()
            } else {
                switch route {
                case .list:
                    OrderListView(open: { order in go(.detail(order.id)) }, openSettings: { go(.settings) })
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .detail(let id):
                    if let order = store.order(id: id) {
                        OrderDetailView(order: order, back: { go(.list) })
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        Color.clear.onAppear { route = .list }
                    }
                case .settings:
                    SettingsView(back: { go(.list) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
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

    var body: some View {
        Image(nsImage: Self.render(state))
            .accessibilityLabel(state.text.map { "Doorstep, \($0)" } ?? "Doorstep")
    }

    @MainActor
    static func render(_ state: OrderStore.MenuBarState) -> NSImage {
        let view = HStack(spacing: 4) {
            Image(systemName: "shippingbox")
                .font(.system(size: 13.5, weight: .medium))
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
