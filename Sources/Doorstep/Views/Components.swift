import AppKit
import SwiftUI

struct MerchantTile: View {
    let merchant: String
    var size: CGFloat = 36

    var body: some View {
        Text(merchant.prefix(1).uppercased())
            .font(.system(size: size * 0.39, weight: .bold))
            .foregroundStyle(MerchantTint.foreground(merchant))
            .frame(width: size, height: size)
            .background(MerchantTint.background(merchant), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The product photo when the email had one, otherwise the store's letter tile.
struct OrderThumbnail: View {
    @Environment(OrderStore.self) private var store
    let order: Order
    var size: CGFloat = 36

    var body: some View {
        content.heroMatched("thumb-\(order.id)")
    }

    @ViewBuilder
    private var content: some View {
        let _ = store.imagesVersion
        if let remote = order.imageURL, let image = NSImage(contentsOf: ImageStore.localFile(for: remote)) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(size * 0.08)
                .frame(width: size, height: size)
                .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))
                .accessibilityHidden(true)
        } else if order.itemsAreCategories == true, let symbol = CategoryIcon.symbol(for: order.title) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(MerchantTint.foreground(order.merchant))
                .frame(width: size, height: size)
                .background(MerchantTint.background(order.merchant), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                .accessibilityHidden(true)
        } else if let logo = LogoStore.image(for: order.merchantDomain) ?? LogoStore.image(for: order.carrierDomain) {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 0.56, height: size * 0.56)
                .frame(width: size, height: size)
                .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))
                .accessibilityHidden(true)
        } else {
            MerchantTile(merchant: order.merchant, size: size)
        }
    }
}

/// Four equal cells, each with a centered dot and half-lines either side, so
/// labels (when shown) sit exactly under their dots.
struct ProgressDots: View {
    let stage: Int
    let color: Color
    var showLabels = false
    var labels = ["Ordered", "Shipped", "Out for delivery", "Delivered"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                VStack(spacing: 7) {
                    HStack(spacing: 0) {
                        Rectangle().fill(i == 0 ? .clear : (i <= stage ? color : Palette.track)).frame(height: 2)
                        Circle()
                            .fill(i <= stage ? color : Palette.track)
                            .frame(width: i == stage ? 12 : 8, height: i == stage ? 12 : 8)
                            .background(Circle().fill(color.opacity(i == stage ? 0.24 : 0)).padding(-4))
                        Rectangle().fill(i == 3 ? .clear : (i < stage ? color : Palette.track)).frame(height: 2)
                    }
                    .frame(height: 12)
                    if showLabels {
                        Text(labels[i])
                            .font(.system(size: 10.5, weight: i == stage ? .semibold : .regular))
                            .foregroundStyle(i == stage ? .primary : .secondary)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress: \(labels[min(max(stage, 0), 3)])")
    }
}

/// Someone has to be home to sign.
struct SignatureBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "signature").font(.system(size: 9.5, weight: .bold))
            Text("Signature").font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.2), in: Capsule())
        .fixedSize()
        .help("Signature required: someone needs to be home")
        .accessibilityLabel("Signature required")
    }
}

struct SegmentBar: View {
    let stage: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(i <= stage ? color : Palette.track).frame(height: 3)
            }
        }
        .frame(width: 52)
        .accessibilityHidden(true)
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(animate ? 2.6 : 1)
                    .opacity(animate ? 0 : 0.7)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { animate = true }
            }
    }
}

struct SectionHeader: View {
    let title: String
    var color: Color = .secondary

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Subtle hover/press fill for rows and icon buttons.
struct HoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.gray.opacity(configuration.isPressed ? 0.24 : hovering ? 0.15 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration)
    }

    private struct CardBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                // Glass sits in its own layer behind the content, so the content always draws.
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card)
                        Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .brightness(hovering ? 0.03 : 0)
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .offset(y: hovering ? -1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var spinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(HoverButtonStyle(cornerRadius: 8))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Refresh, done properly: arrows at rest; while syncing, a thin ring that fills with
/// real progress (or a steady arc when there's nothing to count); on success the ring
/// closes in green and a checkmark draws itself, then the arrows return. Failure turns
/// the ring orange. A minimum duration keeps quick syncs from flickering.
struct SyncButton: View {
    let isSyncing: Bool
    let failed: Bool
    let progress: Double?
    let action: () -> Void

    private enum Phase: Equatable { case idle, syncing, done, failed }
    @State private var phase: Phase = .idle
    @State private var startedAt = Date.distantPast
    @State private var closeRing: CGFloat = 0
    @State private var drawCheck: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard phase == .idle || phase == .done || phase == .failed else { return }
            begin()
            action()
        } label: {
            ZStack {
                switch phase {
                case .idle:
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                case .syncing:
                    ring.transition(.scale(scale: 0.6).combined(with: .opacity))
                case .done:
                    finished(color: Palette.green, symbol: nil)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                case .failed:
                    finished(color: Palette.orange, symbol: "exclamationmark")
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .keyboardShortcut("r")
        .help(phase == .syncing ? "Syncing…" : "Refresh (⌘R)")
        .accessibilityLabel(phase == .syncing ? "Syncing" : "Refresh")
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "")
        .onChange(of: isSyncing) { _, syncing in
            if syncing { begin() } else { end() }
        }
    }

    /// Track + arc. Determinate when we know how many emails are left.
    @ViewBuilder
    private var ring: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 2)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(Palette.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: progress)
            } else {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Palette.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(reduceMotion ? 0 : (t * 400).truncatingRemainder(dividingBy: 360)))
                }
            }
        }
    }

    private func finished(color: Color, symbol: String?) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: closeRing)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
            } else {
                CheckmarkShape()
                    .trim(from: 0, to: drawCheck)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(4.5)
            }
        }
    }

    private func begin() {
        guard phase != .syncing else { return }
        startedAt = Date()
        closeRing = 0
        drawCheck = 0
        withAnimation(.snappy(duration: 0.25)) { phase = .syncing }
    }

    private func end() {
        let wait = max(0, 0.6 - Date().timeIntervalSince(startedAt))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            closeRing = progress ?? 0.28
            withAnimation(.snappy(duration: 0.2)) { phase = failed ? .failed : .done }
            withAnimation(.easeInOut(duration: 0.3)) { closeRing = 1 }
            try? await Task.sleep(for: .seconds(0.22))
            withAnimation(.easeOut(duration: 0.28)) { drawCheck = 1 }
            try? await Task.sleep(for: .seconds(failed ? 2.0 : 1.1))
            withAnimation(.snappy(duration: 0.3)) { if phase != .syncing { phase = .idle } }
        }
    }
}

/// A checkmark path that can be drawn on with `trim`.
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return p
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration)
    }

    private struct SecondaryBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .opacity(isEnabled ? 1 : 0.4)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Color.gray.opacity(configuration.isPressed ? 0.26 : 0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Palette.primaryButton.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A ScrollView that is only as tall as its content, up to a cap — so the
/// menu bar panel hugs short lists and scrolls long ones.
struct FittedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if Snapshot.isActive {
            content
        } else {
            scroll
        }
    }

    private var scroll: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }
}

/// Right-click actions shared by every order row and card.
struct OrderActions: View {
    @Environment(OrderStore.self) private var store
    let order: Order

    var body: some View {
        if let tracking = order.trackingNumber {
            Button("Copy Tracking Number") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tracking, forType: .string)
            }
        }
        if let url = order.carrier.trackingURL(tracking: order.trackingNumber, orderNumber: order.orderNumber) {
            Button("Track Package") { NSWorkspace.shared.open(url) }
        }
        if !["sample", "manual"].contains(order.latestThreadId) {
            Button("Open Email") {
                if let url = URL(string: "https://mail.google.com/mail/u/0/#all/\(order.latestThreadId)") { NSWorkspace.shared.open(url) }
            }
        }
        Divider()
        if order.isActive {
            Button("Mark as Received") { store.markReceived(order) }
        }
        Button("Hide") { withAnimation(.snappy) { store.hide(order) } }
    }
}

/// Highlight for the row selected with the arrow keys.
struct KeyboardHighlight: ViewModifier {
    @Environment(OrderStore.self) private var store
    let id: String

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.blue.opacity(store.highlightedID == id ? 0.18 : 0))
        )
    }
}

extension View {
    func keyboardHighlight(_ id: String) -> some View { modifier(KeyboardHighlight(id: id)) }
}

/// Secondary actions on glass, always in neutral ink (never picks up an accent tint).
struct NeutralGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NeutralGlassBody(configuration: configuration)
    }

    private struct NeutralGlassBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        }
    }
}
