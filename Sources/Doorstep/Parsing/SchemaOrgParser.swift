import Foundation

/// Reads schema.org `Order` / `ParcelDelivery` JSON-LD that many stores embed in
/// their emails (the same markup Gmail uses for its "Happening soon" cards).
enum SchemaOrgParser {
    static func parse(html: String) -> PartialFinding? {
        let pattern = "<script[^>]*application/ld\\+json[^>]*>([\\s\\S]*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        var result = PartialFinding()
        var found = false

        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let json = ns.substring(with: match.range(at: 1))
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            let nodes: [[String: Any]] = (obj as? [[String: Any]]) ?? [(obj as? [String: Any])].compactMap { $0 }
            for node in nodes {
                if absorb(node, into: &result) { found = true }
            }
        }
        if found { result.isOrder = true }
        return found ? result : nil
    }

    private static func absorb(_ node: [String: Any], into r: inout PartialFinding) -> Bool {
        let type = (node["@type"] as? String) ?? ""
        switch type {
        case "ParcelDelivery":
            r.trackingNumber = r.trackingNumber ?? node["trackingNumber"] as? String
            r.carrierName = r.carrierName ?? name(node["carrier"]) ?? name(node["provider"])
            if let until = node["expectedArrivalUntil"] as? String ?? node["expectedArrivalFrom"] as? String {
                r.expectedDate = r.expectedDate ?? parseISO(until)
            }
            r.status = r.status ?? status(from: (node["deliveryStatus"] as? [String: Any])?["@type"] as? String ?? node["deliveryStatus"] as? String)
            if let order = node["partOfOrder"] as? [String: Any] { _ = absorb(order.merging(["@type": "Order"]) { a, _ in a }, into: &r) }
            for item in list(node["itemShipped"]) { if let n = item["name"] as? String { r.items.append(n) } }
            return true
        case "Order":
            r.orderNumber = r.orderNumber ?? node["orderNumber"] as? String
            r.merchant = r.merchant ?? name(node["merchant"]) ?? name(node["seller"])
            if r.status == nil { r.status = status(from: node["orderStatus"] as? String) }
            for offer in list(node["acceptedOffer"]) {
                if let item = offer["itemOffered"] as? [String: Any], let n = item["name"] as? String { r.items.append(n) }
            }
            if let price = node["price"] as? String ?? (node["price"] as? NSNumber)?.stringValue {
                r.total = r.total ?? "$" + price
            }
            if let delivery = node["orderDelivery"] as? [String: Any] { _ = absorb(delivery.merging(["@type": "ParcelDelivery"]) { a, _ in a }, into: &r) }
            return true
        default:
            return false
        }
    }

    private static func name(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        return (value as? [String: Any])?["name"] as? String
    }

    private static func list(_ value: Any?) -> [[String: Any]] {
        if let arr = value as? [[String: Any]] { return arr }
        if let one = value as? [String: Any] { return [one] }
        return []
    }

    private static func status(from value: String?) -> OrderStatus? {
        guard let v = value?.lowercased() else { return nil }
        if v.contains("delivered") { return .delivered }
        if v.contains("outfordelivery") || v.contains("out_for_delivery") { return .outForDelivery }
        if v.contains("transit") || v.contains("shipped") { return .shipped }
        if v.contains("problem") { return .delayed }
        if v.contains("processing") || v.contains("paymentdue") { return .ordered }
        return nil
    }

    private static func parseISO(_ s: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let d = full.date(from: s) { return d }
        full.formatOptions = [.withFullDate]
        return full.date(from: String(s.prefix(10)))
    }
}
