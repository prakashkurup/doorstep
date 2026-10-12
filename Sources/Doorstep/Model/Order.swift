import Foundation

enum OrderStatus: String, Codable, CaseIterable {
    case ordered, shipped, outForDelivery, delivered, delayed

    /// Position on the Ordered → Shipped → Out for delivery → Delivered track.
    /// A delay keeps whatever stage the order had already reached.
    var naturalStage: Int {
        switch self {
        case .ordered: 0
        case .shipped, .delayed: 1
        case .outForDelivery: 2
        case .delivered: 3
        }
    }

    var label: String {
        switch self {
        case .ordered: "Preparing"
        case .shipped: "Shipped"
        case .outForDelivery: "Out for delivery"
        case .delivered: "Delivered"
        case .delayed: "Delayed"
        }
    }

    var eventLabel: String {
        switch self {
        case .ordered: "Order placed"
        case .shipped: "Shipped"
        case .outForDelivery: "Out for delivery"
        case .delivered: "Delivered"
        case .delayed: "Delivery delayed"
        }
    }
}

struct OrderItem: Codable, Hashable {
    var name: String
    var quantity: Int = 1
}

struct OrderEvent: Codable, Hashable, Identifiable {
    var id: String { messageId + status.rawValue }
    let messageId: String
    let status: OrderStatus
    let date: Date
}

struct Order: Codable, Identifiable, Hashable {
    var id: String
    var merchant: String
    var items: [OrderItem]
    var fallbackTitle: String
    var carrierName: String?
    var trackingNumber: String?
    var orderNumber: String?
    var status: OrderStatus
    var stage: Int
    var expectedDelivery: Date?
    var expectedByTime: String?
    var originalExpected: Date?
    var orderedAt: Date?
    var deliveredAt: Date?
    /// True when there was no delivery email and time says it has surely arrived.
    var deliveryInferred: Bool?
    var total: String?
    var imageURL: String?
    var itemsAreCategories: Bool?
    var merchantDomain: String?
    var signatureRequired: Bool?
    /// Last day to return; stated in an email, or estimated from the store's usual window.
    var returnBy: Date?
    var returnByEstimated: Bool?
    /// Grocery and same-day deliveries: no return window, no live tracking.
    var isGrocery: Bool?
    var live: LiveTracking?
    /// "10:30 AM – 2:30 PM" when the carrier gives a same-day window.
    var deliveryWindow: String?
    var events: [OrderEvent]
    var latestMessageId: String
    var latestThreadId: String
    var lastUpdated: Date

    var title: String {
        guard let first = items.first?.name, !first.isEmpty else { return fallbackTitle }
        let extra = items.count - 1
        if extra <= 0 { return first }
        return "\(first) and \(extra) more item\(extra == 1 ? "" : "s")"
    }

    var carrier: Carrier { Carrier.detect(tracking: trackingNumber, name: carrierName, merchant: merchant) }

    /// Website whose logo stands in for the carrier when the store is unknown.
    var carrierDomain: String? { carrier.domain }

    var isActive: Bool { status != .delivered }

    /// Words appear on list rows only when something needs a look.
    var showsStatusInRow: Bool { status == .delayed || status == .ordered }
}
