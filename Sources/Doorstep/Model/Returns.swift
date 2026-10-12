import Foundation

enum ReturnStatus: String, Codable, CaseIterable {
    case started, shipped, received, refunded

    var stage: Int {
        switch self {
        case .started: 0
        case .shipped: 1
        case .received: 2
        case .refunded: 3
        }
    }

    var label: String {
        switch self {
        case .started: "Return started"
        case .shipped: "Return on its way"
        case .received: "Return received"
        case .refunded: "Refunded"
        }
    }

    static let stepLabels = ["Started", "Sent back", "Received", "Refunded"]
}

struct ReturnEvent: Codable, Hashable, Identifiable {
    var id: String { messageId + status.rawValue }
    let messageId: String
    let status: ReturnStatus
    let date: Date
}

/// A return (or a refund with no return, like an unavailable grocery item).
struct ReturnCase: Codable, Identifiable, Hashable {
    var id: String
    var merchant: String
    var title: String
    var status: ReturnStatus
    var refundAmount: String?
    var orderNumber: String?
    var events: [ReturnEvent]
    var lastUpdated: Date
    var imageURL: String?
    var merchantDomain: String?
    var latestThreadId: String
    /// Money back without anything being sent back.
    var isRefundOnly: Bool

    var isActive: Bool { status != .refunded }
}

/// Typical return windows, used only when the email doesn't state a deadline.
/// Shown as an estimate; stores change these and some items are excluded.
enum ReturnPolicy {
    private static let days: [(String, Int)] = [
        ("amazon", 30), ("walmart", 90), ("target", 90), ("best buy", 15), ("bestbuy", 15),
        ("apple", 14), ("nike", 60), ("macys", 30), ("macy's", 30),
    ]

    static func defaultDays(for merchant: String) -> Int? {
        let m = merchant.lowercased()
        return days.first { m.contains($0.0) }?.1
    }
}
