import Foundation

enum Carrier: String, Codable {
    case ups, usps, fedex, dhl, amazon, ontrac, other

    var displayName: String {
        switch self {
        case .ups: "UPS"
        case .usps: "USPS"
        case .fedex: "FedEx"
        case .dhl: "DHL"
        case .amazon: "Amazon"
        case .ontrac: "OnTrac"
        case .other: "Carrier"
        }
    }

    var domain: String? {
        switch self {
        case .ups: "ups.com"
        case .usps: "usps.com"
        case .fedex: "fedex.com"
        case .dhl: "dhl.com"
        case .amazon: "amazon.com"
        case .ontrac: "ontrac.com"
        case .other: nil
        }
    }

    static func detect(tracking: String?, name: String?, merchant: String) -> Carrier {
        let n = (name ?? "").lowercased()
        if n.contains("ups") && !n.contains("usps") { return .ups }
        if n.contains("usps") || n.contains("postal") { return .usps }
        if n.contains("fedex") { return .fedex }
        if n.contains("dhl") { return .dhl }
        if n.contains("ontrac") { return .ontrac }
        if n.contains("amazon") { return .amazon }
        if let t = tracking?.uppercased() {
            if t.hasPrefix("1Z") { return .ups }
            if t.hasPrefix("TBA") { return .amazon }
            if t.count >= 20, t.allSatisfy(\.isNumber), t.hasPrefix("9") { return .usps }
            if (t.count == 12 || t.count == 15), t.allSatisfy(\.isNumber) { return .fedex }
        }
        if merchant.lowercased().contains("amazon") { return .amazon }
        return .other
    }

    func trackingURL(tracking: String?, orderNumber: String?) -> URL? {
        if self == .amazon {
            guard let orderNumber else { return URL(string: "https://www.amazon.com/gp/css/order-history") }
            return URL(string: "https://www.amazon.com/gp/your-account/order-details?orderID=\(orderNumber)")
        }
        guard let t = tracking?.replacingOccurrences(of: " ", with: ""), !t.isEmpty else { return nil }
        let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
        switch self {
        case .ups: return URL(string: "https://www.ups.com/track?tracknum=\(q)")
        case .usps: return URL(string: "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(q)")
        case .fedex: return URL(string: "https://www.fedex.com/fedextrack/?trknbr=\(q)")
        case .dhl: return URL(string: "https://www.dhl.com/us-en/home/tracking.html?tracking-id=\(q)")
        case .ontrac: return URL(string: "https://www.ontrac.com/tracking/?number=\(q)")
        case .amazon, .other: return URL(string: "https://www.google.com/search?q=\(q)")
        }
    }
}
