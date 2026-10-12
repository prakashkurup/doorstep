import Foundation
import FoundationModels

/// On-device extraction with Apple's Foundation Models. Nothing leaves the Mac.
/// Used to clean up item names and catch emails the patterns can't read.
enum AIExtractor {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let schema: GenerationSchema? = {
        let string = DynamicGenerationSchema(type: String.self)
        let root = DynamicGenerationSchema(
            name: "OrderEmail",
            properties: [
                .init(name: "isPackageOrder",
                      description: "True only if this email is about physical goods bought from a store that are being shipped or delivered to the reader: an order confirmation, shipping update, out-for-delivery notice, delivery confirmation, or delay. False for event tickets, passes and memberships, restaurant or food pickup orders, rides, travel, bank or credit cards being mailed, mail digests, marketing, newsletters, invoices, subscriptions, refunds and returns.",
                      schema: DynamicGenerationSchema(type: Bool.self)),
                .init(name: "merchant", description: "The store or brand the order was placed with, e.g. Amazon, Allbirds. Empty if unknown.", schema: string),
                .init(name: "items",
                      description: "Product names listed in the email body, each shortened to under 50 characters, keeping brand and key detail (size, strength). Do not use generic category words like Supplements or Household Supplies. Empty list if no product is named.",
                      schema: DynamicGenerationSchema(arrayOf: string, maximumElements: 6)),
                .init(name: "status",
                      description: "Current state of the order according to this email.",
                      schema: DynamicGenerationSchema(name: "Status", anyOf: ["ordered", "shipped", "out_for_delivery", "delivered", "delayed", "cancelled", "unknown"])),
                .init(name: "expectedDelivery", description: "Expected delivery date stated in the email as YYYY-MM-DD, resolved against the email date. Empty if none.", schema: string),
                .init(name: "orderNumber", description: "Order number exactly as written. Empty if none.", schema: string),
                .init(name: "trackingNumber", description: "Shipment tracking number exactly as written. Empty if none.", schema: string),
                .init(name: "carrier", description: "Shipping carrier, e.g. UPS, USPS, FedEx, Amazon Logistics. Empty if none.", schema: string),
            ]
        )
        return try? GenerationSchema(root: root, dependencies: [])
    }()

    static func extract(subject: String, sender: String, text: String, emailDate: Date) async -> PartialFinding? {
        guard isAvailable, let schema else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd (EEEE)"
        // The on-device context is small; the useful part of shipping mail is near the top.
        let body = String(text.prefix(2400))
        let prompt = """
        Email date: \(dateFormatter.string(from: emailDate))
        From: \(sender)
        Subject: \(subject)

        \(body)
        """

        let session = LanguageModelSession(instructions: "You read shopping emails and extract order details. Only report facts stated in the email. The current status is what the subject and headline say; progress trackers that list every step (Ordered, Shipped, Out for delivery, Delivered) do not indicate the status.")
        do {
            let response = try await session.respond(to: prompt, schema: schema, options: GenerationOptions(temperature: 0))
            let c = response.content
            func str(_ key: String) -> String? {
                let v = (try? c.value(String.self, forProperty: key))?.trimmingCharacters(in: .whitespaces) ?? ""
                return v.isEmpty ? nil : v
            }

            var r = PartialFinding()
            r.isOrder = (try? c.value(Bool.self, forProperty: "isPackageOrder")) ?? false
            r.merchant = str("merchant")
            r.items = ((try? c.value([String].self, forProperty: "items")) ?? []).filter { !$0.isEmpty }
            r.orderNumber = str("orderNumber")
            r.trackingNumber = str("trackingNumber")?.replacingOccurrences(of: " ", with: "")
            r.carrierName = str("carrier")
            switch str("status") {
            case "ordered": r.status = .ordered
            case "shipped": r.status = .shipped
            case "out_for_delivery": r.status = .outForDelivery
            case "delivered": r.status = .delivered
            case "delayed": r.status = .delayed
            case "cancelled": r.isOrder = false
            default: break
            }
            if let d = str("expectedDelivery") {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                r.expectedDate = f.date(from: d)
            }
            return r
        } catch {
            return nil
        }
    }
}
