import SwiftUI

// MARK: - Shared geometry for hero transitions

/// The popover's namespace, so a row's thumbnail can grow into the detail header and
/// rows can glide between sections when an order changes state.
private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

private struct HeroMatched: ViewModifier {
    @Environment(\.heroNamespace) private var namespace
    let id: String

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Pairs this view with any other view using the same id in the popover.
    func heroMatched(_ id: String) -> some View { modifier(HeroMatched(id: id)) }
}

// MARK: - Today card route

/// The four-step track for a package that's out for delivery: a small truck rides the
/// last stretch, with the road ahead drawn as moving dashes. Still under Reduce Motion.
struct RouteProgress: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let centers = (0..<4).map { (CGFloat($0) + 0.5) * w / 4 }
            let y: CGFloat = 13
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    // Travelled road.
                    Path { p in
                        p.move(to: CGPoint(x: centers[0], y: y))
                        p.addLine(to: CGPoint(x: centers[2], y: y))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    // Road still to go: dashes marching toward the door.
                    Path { p in
                        p.move(to: CGPoint(x: centers[2], y: y))
                        p.addLine(to: CGPoint(x: centers[3], y: y))
                    }
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4],
                                                                    dashPhase: reduceMotion ? 0 : CGFloat(-(t * 14).truncatingRemainder(dividingBy: 7))))

                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i <= 2 ? color : Palette.track)
                            .frame(width: 8, height: 8)
                            .position(x: centers[i], y: y)
                    }

                    // The truck, gently idling between the last two stops.
                    let drift = reduceMotion ? 0 : CGFloat(sin(t * 1.6)) * 5
                    let bob = reduceMotion ? 0 : CGFloat(abs(sin(t * 6))) * -1
                    Image(systemName: "truck.box.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(3)
                        .background(Circle().fill(.background.opacity(0.0001)))
                        .position(x: (centers[2] + centers[3]) / 2 + drift, y: y - 1 + bob)
                }
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Out for delivery")
    }
}

// MARK: - Toast

/// A brief confirmation at the bottom of the panel (e.g. after pasting a tracking number).
struct Toast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
