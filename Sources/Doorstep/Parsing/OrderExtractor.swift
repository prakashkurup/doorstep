import Foundation

enum OrderExtractor {
    /// Returns nil when the email isn't about a package.
    static func extract(_ msg: GmailMessage) async -> EmailFinding? {
        if Heuristics.isExcluded(subject: msg.subject, fromAddress: msg.fromAddress) { return nil }
        let text = msg.html.map(HTMLText.plain(from:)) ?? msg.plainText ?? ""
        if let returnFinding = extractReturn(msg, text: text) { return returnFinding }

        let schema = msg.html.flatMap(SchemaOrgParser.parse(html:))
        let heuristic = Heuristics.extract(subject: msg.subject, text: text, fromName: msg.fromName,
                                           fromAddress: msg.fromAddress, emailDate: msg.date)
        // The model takes a few seconds per email, so only ask it when it adds something:
        // skip mail with no shipping language at all, and mail whose markup already says everything.
        let needsModel: Bool
        if let schema {
            needsModel = schema.items.isEmpty || schema.status == nil
        } else {
            needsModel = heuristic.status != nil
        }
        let ai = needsModel
            ? await AIExtractor.extract(subject: msg.subject, sender: "\(msg.fromName) <\(msg.fromAddress)>",
                                        text: text, emailDate: msg.date)
            : nil

        // Structured markup is most trustworthy, then patterns for exact numbers,
        // then the model for names and anything left.
        var merged = schema ?? PartialFinding()
        let subjectItems = heuristic.items.filter { !$0.isEmpty }
        if merged.items.isEmpty, !subjectItems.isEmpty { merged.items = heuristic.items }
        // The sender is the store unless a carrier sent the email on the store's behalf
        // ("UPS Update" for a Costco order); only then trust the model's store name.
        let senderMerchant = Heuristics.merchant(fromName: msg.fromName, address: msg.fromAddress)
        let senderIsCarrier = Heuristics.carriers.contains { senderMerchant.caseInsensitiveCompare($0) == .orderedSame }
        if merged.merchant == nil, !senderIsCarrier { merged.merchant = senderMerchant }
        if let ai {
            if merged.items.isEmpty { merged.items = ai.items }
            if merged.merchant == nil { merged.merchant = ai.merchant }
        }
        merged.fillGaps(from: heuristic)
        if let ai { merged.fillGaps(from: ai) }

        // An order needs something to hang it on: markup, or an order/tracking number.
        // That alone rules out "your card is on its way" and similar mail.
        let hasIdentifier = merged.orderNumber != nil || merged.trackingNumber != nil
        let isOrder: Bool
        if schema != nil {
            isOrder = true
        } else if let ai {
            isOrder = ai.isOrder && hasIdentifier
        } else {
            isOrder = heuristic.isOrder && hasIdentifier
        }
        guard isOrder, let status = merged.status else { return nil }

        // Discard dates that can't be an arrival for this email.
        if let eta = merged.expectedDate {
            let earliest = msg.date.addingTimeInterval(-86_400)
            let latest = msg.date.addingTimeInterval(45 * 86_400)
            if eta < Calendar.current.startOfDay(for: earliest) || eta > latest { merged.expectedDate = nil }
        }

        let items = Heuristics.cleanItems(merged.items, merchant: merged.merchant).map { OrderItem(name: Heuristics.shorten($0)) }
        return EmailFinding(
            messageId: msg.id,
            threadId: msg.threadId,
            date: msg.date,
            subject: msg.subject,
            merchant: Heuristics.tidyMerchant(merged.merchant ?? senderMerchant),
            items: items,
            orderNumber: merged.orderNumber,
            trackingNumber: merged.trackingNumber,
            carrierName: merged.carrierName,
            status: status,
            expectedDate: merged.expectedDate,
            expectedByTime: merged.expectedByTime,
            total: merged.total,
            imageURL: msg.html.flatMap { ProductImage.best(in: $0, itemNames: items.map(\.name)) },
            itemsAreCategories: Heuristics.amazonCategoryTitle(msg.subject).map { items.first?.name == $0 } == true ? true : nil,
            senderDomain: senderIsCarrier ? nil : Heuristics.registrableDomain(of: msg.fromAddress),
            signatureRequired: Heuristics.signatureRequired(in: msg.subject + "\n" + text) ? true : nil,
            returnBy: Heuristics.returnDeadline(in: text, emailDate: msg.date),
            isGrocery: Heuristics.isGroceryDelivery(subject: msg.subject) ? true : nil
        )
    }

    /// Returns and refunds. Patterns only: these emails are formulaic, and an order or
    /// refund amount is required so marketing ("easy returns!") never qualifies.
    private static func extractReturn(_ msg: GmailMessage, text: String) -> EmailFinding? {
        guard let status = Heuristics.returnStatus(subject: msg.subject, head: text) else { return nil }
        let orderNumber = Heuristics.orderNumber(in: msg.subject + "\n" + text)
        let amount = Heuristics.refundAmount(in: msg.subject + "\n" + text)
        guard orderNumber != nil || amount != nil else { return nil }

        let item = Heuristics.bracketedItem(msg.subject)
            ?? Heuristics.subjectItems(msg.subject).first { !$0.isEmpty }
        let merchant = Heuristics.merchant(fromName: msg.fromName, address: msg.fromAddress)
        return EmailFinding(
            messageId: msg.id,
            threadId: msg.threadId,
            date: msg.date,
            subject: msg.subject,
            merchant: Heuristics.tidyMerchant(merchant),
            items: item.map { [OrderItem(name: Heuristics.shorten($0))] } ?? [],
            orderNumber: orderNumber,
            status: nil,
            imageURL: msg.html.flatMap { ProductImage.best(in: $0, itemNames: item.map { [$0] } ?? []) },
            senderDomain: Heuristics.registrableDomain(of: msg.fromAddress),
            returnStatus: status,
            refundAmount: amount
        )
    }
}
