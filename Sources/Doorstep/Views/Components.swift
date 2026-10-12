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

    private let labels = ["Ordered", "Shipped", "Out for delivery", "Delivered"]

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

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(.secondary)
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
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))
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
