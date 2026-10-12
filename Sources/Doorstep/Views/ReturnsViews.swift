import AppKit
import SwiftUI

/// A delivered order that can still be returned: urgency in orange, otherwise the date.
struct ReturnWindowRow: View {
    let order: Order
    let action: () -> Void

    var body: some View {
        let days = ReturnText.days(order.returnBy) ?? 99
        Button(action: action) {
            HStack(spacing: 12) {
                OrderThumbnail(order: order, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(order.returnByEstimated == true ? "\(order.merchant) · est." : order.merchant)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(days <= 7 ? ReturnText.daysLeft(order.returnBy) : (order.returnBy?.formatted(.dateTime.month(.abbreviated).day()) ?? ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(days <= 7 ? Palette.orange : .secondary)
                    .fixedSize()
            }
            .padding(8)
            .frame(minHeight: 50)
        }
        .buttonStyle(HoverButtonStyle())
        .keyboardHighlight(order.id)
        .contextMenu { OrderActions(order: order) }
        .help(order.returnBy.map { "Return by \($0.formatted(.dateTime.weekday(.wide).month().day()))" } ?? "")
    }
}

struct ReturnThumbnail: View {
    @Environment(OrderStore.self) private var store
    let item: ReturnCase
    var size: CGFloat = 36

    var body: some View {
        content.heroMatched("thumb-\(item.id)")
    }

    @ViewBuilder
    private var content: some View {
        let _ = store.imagesVersion
        if let remote = item.imageURL, let image = NSImage(contentsOf: ImageStore.localFile(for: remote)) {
            Image(nsImage: image)
                .resizable().interpolation(.high).scaledToFit()
                .padding(size * 0.08)
                .frame(width: size, height: size)
                .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                .accessibilityHidden(true)
        } else if let logo = LogoStore.image(for: item.merchantDomain) {
            Image(nsImage: logo)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: size * 0.56, height: size * 0.56)
                .frame(width: size, height: size)
                .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                .accessibilityHidden(true)
        } else {
            MerchantTile(merchant: item.merchant, size: size)
        }
    }
}

struct ReturnRow: View {
    let item: ReturnCase
    let action: () -> Void

    private var color: Color { item.status == .refunded ? Palette.green : Palette.blue }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ReturnThumbnail(item: item, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(rightText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.status == .refunded ? Palette.green : (item.status == .started ? Palette.blue : .secondary))
                    .fixedSize()
            }
            .padding(8)
            .frame(minHeight: 52)
        }
        .buttonStyle(HoverButtonStyle())
    }

    private var subtitle: String {
        if item.status == .refunded {
            return "\(item.merchant) · \(item.lastUpdated.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        }
        return item.merchant
    }

    private var rightText: String {
        switch item.status {
        case .refunded: item.refundAmount ?? "Refunded"
        case .received: "Waiting for refund"
        case .shipped: "Sent back"
        case .started: "Started"
        }
    }
}

struct ReturnDetailView: View {
    let item: ReturnCase
    let back: () -> Void

    private var color: Color { item.status == .refunded ? Palette.green : Palette.blue }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text("Deliveries")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.blue)
                    .padding(.leading, 4)
                    .padding(.trailing, 10)
                    .frame(minHeight: 30)
                }
                .buttonStyle(HoverButtonStyle(cornerRadius: 8))
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    ReturnThumbnail(item: item, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.merchant).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(item.isRefundOnly ? "Refund" : item.status.label,
                              systemImage: item.status == .refunded ? "checkmark" : "arrow.uturn.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                        Text(headline)
                            .font(.system(size: 24, weight: .semibold))
                            .kerning(-0.5)
                    }
                    if !item.isRefundOnly {
                        ProgressDots(stage: item.status.stage, color: color, showLabels: true, labels: ReturnStatus.stepLabels)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Updates").padding(.horizontal, -8)
                    ForEach(item.events.sorted { $0.date > $1.date }) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.status.label).font(.system(size: 13, weight: .medium))
                            Text(DateText.eventTime(event.date)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                }

                if let number = item.orderNumber {
                    HStack {
                        Text("Order").foregroundStyle(.secondary)
                        Spacer()
                        Text(number).monospacedDigit().textSelection(.enabled)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button("Open email") {
                    if let url = URL(string: "https://mail.google.com/mail/u/0/#all/\(item.latestThreadId)") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(item.latestThreadId == "sample")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
    }

    private var headline: String {
        switch item.status {
        case .refunded: item.refundAmount.map { "\($0) refunded" } ?? "Refunded"
        case .received: "Waiting for refund"
        case .shipped: "On its way back"
        case .started: "Send it back"
        }
    }
}
