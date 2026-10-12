import Foundation

/// What one email says about one order. Several findings (ordered, shipped,
/// delivered…) are merged into a single `Order` by `OrderBuilder`.
struct EmailFinding: Codable, Hashable {
    let messageId: String
    let threadId: String
    let date: Date
    var subject: String
    var merchant: String
    var items: [OrderItem] = []
    var orderNumber: String?
    var trackingNumber: String?
    var carrierName: String?
    var status: OrderStatus?
    var expectedDate: Date?
    var expectedByTime: String?
    var total: String?
    var imageURL: String?
    /// The email named only a category ("Supplements"), not a product.
    var itemsAreCategories: Bool?
    /// The store's website when the store itself sent the email (not a carrier).
    var senderDomain: String?
    var signatureRequired: Bool?
    var returnBy: Date?
    var isGrocery: Bool?
    /// Set when this email is about a return or refund rather than a delivery.
    var returnStatus: ReturnStatus?
    var refundAmount: String?
}

/// Partial result from one extraction source; later sources only fill gaps.
struct PartialFinding {
    var isOrder = false
    var merchant: String?
    var items: [String] = []
    var orderNumber: String?
    var trackingNumber: String?
    var carrierName: String?
    var status: OrderStatus?
    var expectedDate: Date?
    var expectedByTime: String?
    var total: String?

    mutating func fillGaps(from other: PartialFinding) {
        isOrder = isOrder || other.isOrder
        if merchant == nil { merchant = other.merchant }
        if items.isEmpty { items = other.items }
        if orderNumber == nil { orderNumber = other.orderNumber }
        if trackingNumber == nil { trackingNumber = other.trackingNumber }
        if carrierName == nil { carrierName = other.carrierName }
        if status == nil { status = other.status }
        if expectedDate == nil { expectedDate = other.expectedDate }
        if expectedByTime == nil { expectedByTime = other.expectedByTime }
        if total == nil { total = other.total }
    }
}

enum HTMLText {
    /// Rough HTML → readable text, good enough for regexes and the on-device model.
    static func plain(from html: String) -> String {
        var s = html
        for tag in ["style", "script", "head"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</tr>|</h[1-6]>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&#8217;": "'", "&rsquo;": "'", "&#8211;": "–", "&ndash;": "–", "&#8212;": "—", "&mdash;": "—", "&zwnj;": "", "&#847;": "", "&#8199;": ""]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "&shy;", with: "")
        s = s.replacingOccurrences(of: "&#\\d+;|&[a-zA-Z]+;", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t\\u{00A0}\\u{200C}\\u{034F}]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
