import Foundation

/// Groups per-email findings into orders. Emails about the same order share an
/// order number, a tracking number, or a Gmail thread.
enum OrderBuilder {
    static func build(now: Date = Date(), from allFindings: [EmailFinding]) -> [Order] {
        let findings = allFindings.filter { $0.returnStatus == nil }
        // Union-find over findings keyed by any shared identifier.
        var parent = Array(findings.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        var firstByKey: [String: Int] = [:]
        for (i, f) in findings.enumerated() {
            let keys = [
                f.orderNumber.map { "o:" + normalize($0) },
                f.trackingNumber.map { "t:" + normalize($0) },
                "th:" + f.threadId,
            ].compactMap { $0 }
            for key in keys {
                if let j = firstByKey[key] { union(i, j) } else { firstByKey[key] = i }
            }
        }

        var groups: [Int: [EmailFinding]] = [:]
        for i in findings.indices { groups[find(i), default: []].append(findings[i]) }
        return mergeMismatchedDeliveries(Array(groups.values)).compactMap { makeOrder($0, now: now) }
    }

    /// Amazon sometimes puts a different order number on the "Delivered" email than on
    /// "Shipped". Join a shipment with no delivery to a delivery with no shipment when the
    /// store and items match and the delivery came within four days.
    private static func mergeMismatchedDeliveries(_ input: [[EmailFinding]]) -> [[EmailFinding]] {
        var groups = input
        func itemKey(_ g: [EmailFinding]) -> String? {
            guard let f = g.first(where: { $0.items.contains { !$0.name.isEmpty } }) else { return nil }
            return Heuristics.tidyMerchant(f.merchant).lowercased() + "#" + f.items.map(\.name).joined(separator: "|").lowercased()
        }
        func has(_ g: [EmailFinding], _ s: OrderStatus) -> Bool { g.contains { $0.status == s } }

        for i in groups.indices where !groups[i].isEmpty && !has(groups[i], .delivered) {
            guard let key = itemKey(groups[i]), let lastSeen = groups[i].map(\.date).max() else { continue }
            let match = groups.indices.first { j in
                guard j != i, !groups[j].isEmpty, has(groups[j], .delivered), !has(groups[j], .shipped),
                      itemKey(groups[j]) == key,
                      let delivered = groups[j].first(where: { $0.status == .delivered })?.date else { return false }
                let gap = delivered.timeIntervalSince(lastSeen)
                return gap >= 0 && gap <= 4 * 86_400
            }
            if let j = match {
                groups[j] += groups[i]
                groups[i] = []
            }
        }
        return groups.filter { !$0.isEmpty }
    }

    private static func normalize(_ s: String) -> String {
        s.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func makeOrder(_ group: [EmailFinding], now: Date) -> Order? {
        let sorted = group.sorted { $0.date < $1.date }
        guard let latest = sorted.last, let latestStatus = latest.status else { return nil }

        // The newest email decides; one misread email can't pin an order to a later stage.
        // "Delivered" is final, though: a late "shipped" email doesn't undo it.
        var status = latestStatus
        if sorted.contains(where: { $0.status == .delivered }) { status = .delivered }
        let maxStage = status == .delayed
            ? (sorted.compactMap { $0.status?.naturalStage }.filter { $0 < 3 }.max() ?? 1)
            : status.naturalStage

        // Email is a snapshot, not live tracking, so age it. Stores often skip the
        // final "delivered" email; without these rules old orders would sit in
        // "out for delivery" forever.
        let day: TimeInterval = 86_400
        let startOfToday = Calendar.current.startOfDay(for: now)
        let expectations = sorted.compactMap(\.expectedDate)
        var deliveredAt = sorted.last { $0.status == .delivered }?.date
        var inferred = false

        // Only a confirmation and nothing since: tickets, pickups, or an order that never shipped.
        if status == .ordered, now.timeIntervalSince(latest.date) > 7 * day { return nil }

        switch status {
        case .outForDelivery where latest.date < startOfToday:
            inferred = true
            deliveredAt = latest.date
        case .shipped, .delayed:
            if let eta = expectations.last, eta < startOfToday.addingTimeInterval(-2 * day) {
                inferred = true
                deliveredAt = eta
            } else if expectations.isEmpty, now.timeIntervalSince(latest.date) > 10 * day {
                inferred = true
                deliveredAt = latest.date
            }
        default:
            break
        }
        if inferred { status = .delivered }

        let items = sorted.reversed().first { $0.items.contains { !$0.name.isEmpty } }?.items
            ?? sorted.reversed().first { !$0.items.isEmpty }?.items ?? []
        let merchant = mostCommon(sorted.map { Heuristics.tidyMerchant($0.merchant) }) ?? latest.merchant

        var events: [OrderEvent] = []
        for f in sorted {
            guard let s = f.status, !events.contains(where: { $0.status == s }) else { continue }
            events.append(OrderEvent(messageId: f.messageId, status: s, date: f.date))
        }

        let id = sorted.compactMap(\.orderNumber).first.map { "o:" + normalize($0) }
            ?? sorted.compactMap(\.trackingNumber).first.map { "t:" + normalize($0) }
            ?? "th:" + latest.threadId

        return Order(
            id: id,
            merchant: merchant,
            items: items,
            fallbackTitle: fallbackTitle(subject: sorted.first?.subject ?? latest.subject, merchant: merchant),
            carrierName: sorted.reversed().compactMap(\.carrierName).first,
            trackingNumber: sorted.reversed().compactMap(\.trackingNumber).first,
            orderNumber: sorted.compactMap(\.orderNumber).first,
            status: status,
            stage: max(maxStage, status.naturalStage),
            expectedDelivery: status == .delivered ? nil : expectations.last,
            expectedByTime: sorted.reversed().compactMap(\.expectedByTime).first,
            originalExpected: status == .delayed && expectations.count > 1 ? expectations.first : nil,
            orderedAt: sorted.first { $0.status == .ordered }?.date ?? sorted.first?.date,
            deliveredAt: deliveredAt,
            deliveryInferred: inferred ? true : nil,
            total: sorted.compactMap(\.total).first,
            imageURL: sorted.reversed().compactMap(\.imageURL).first,
            itemsAreCategories: sorted.reversed().first { !$0.items.isEmpty }?.itemsAreCategories,
            merchantDomain: mostCommon(sorted.compactMap(\.senderDomain)) ?? Heuristics.guessDomain(forMerchant: merchant),
            signatureRequired: sorted.contains { $0.signatureRequired == true } ? true : nil,
            returnBy: returnDeadline(sorted, status: status, deliveredAt: deliveredAt, merchant: merchant).date,
            returnByEstimated: returnDeadline(sorted, status: status, deliveredAt: deliveredAt, merchant: merchant).estimated ? true : nil,
            isGrocery: sorted.contains { $0.isGrocery == true } ? true : nil,
            events: events,
            latestMessageId: latest.messageId,
            latestThreadId: latest.threadId,
            lastUpdated: latest.date
        )
    }

    /// A stated deadline wins; otherwise the store's usual window from delivery, marked as an estimate.
    private static func returnDeadline(_ sorted: [EmailFinding], status: OrderStatus, deliveredAt: Date?, merchant: String) -> (date: Date?, estimated: Bool) {
        if let stated = sorted.reversed().compactMap(\.returnBy).first { return (stated, false) }
        guard status == .delivered, let deliveredAt, !sorted.contains(where: { $0.isGrocery == true }),
              let days = ReturnPolicy.defaultDays(for: merchant) else { return (nil, false) }
        let date = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: deliveredAt))
        return (date, true)
    }

    // MARK: Returns

    static func buildReturns(from allFindings: [EmailFinding], orders: [Order]) -> [ReturnCase] {
        let findings = allFindings.filter { $0.returnStatus != nil }
        var groups: [String: [EmailFinding]] = [:]
        for f in findings {
            let key = f.orderNumber.map { "o:" + normalize($0) + (f.items.first.map { "#" + $0.name.lowercased() } ?? "") } ?? "th:" + f.threadId
            groups[key, default: []].append(f)
        }
        let shoppedAt = Set(orders.map { Heuristics.tidyMerchant($0.merchant).lowercased() })
        return groups.compactMap { key, group -> ReturnCase? in
            let sorted = group.sorted { $0.date < $1.date }
            guard let latest = sorted.last else { return nil }
            let status = sorted.compactMap(\.returnStatus).max { $0.stage < $1.stage } ?? .started
            let original = sorted.compactMap(\.orderNumber).first.flatMap { number in
                orders.first { $0.orderNumber.map(normalize) == normalize(number) }
            }
            var events: [ReturnEvent] = []
            for f in sorted {
                guard let s = f.returnStatus, !events.contains(where: { $0.status == s }) else { continue }
                events.append(ReturnEvent(messageId: f.messageId, status: s, date: f.date))
            }
            let merchant = mostCommon(sorted.map(\.merchant)) ?? latest.merchant
            // A refund from a store with no shipped orders (movie tickets, rides) isn't a return.
            if original == nil, !shoppedAt.contains(Heuristics.tidyMerchant(merchant).lowercased()) { return nil }
            let title = sorted.compactMap { $0.items.first?.name }.first { !$0.isEmpty } ?? original?.title ?? "Return to \(merchant)"
            return ReturnCase(
                id: "r:" + key,
                merchant: merchant,
                title: title,
                status: status,
                refundAmount: sorted.reversed().compactMap(\.refundAmount).first,
                orderNumber: sorted.compactMap(\.orderNumber).first,
                events: events,
                lastUpdated: latest.date,
                imageURL: sorted.compactMap(\.imageURL).first ?? original?.imageURL,
                merchantDomain: mostCommon(sorted.compactMap(\.senderDomain)) ?? Heuristics.guessDomain(forMerchant: merchant),
                latestThreadId: latest.threadId,
                isRefundOnly: status == .refunded && events.count == 1
            )
        }
    }

    private static func mostCommon(_ values: [String]) -> String? {
        let counts = values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    private static func fallbackTitle(subject: String, merchant: String) -> String {
        // Carrier emails ("UPS Update: Package Scheduled for Delivery Tomorrow") name no product.
        if subject.range(of: "\\b(UPS|USPS|FedEx|DHL)\\b|scheduled for delivery|expected delivery|package (was|has been) delivered",
                         options: [.regularExpression, .caseInsensitive]) != nil {
            return Heuristics.carriers.contains(merchant) ? "Package via \(merchant)" : "Package from \(merchant)"
        }
        var s = subject
        s = s.replacingOccurrences(of: "^(re|fwd?):\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "^(your )?(order|package|shipment)( has| is)?\\s*(shipped|been shipped|delivered|on its way|confirmed)?[:!.]?\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count < 4 { return "Order from \(merchant)" }
        return Heuristics.shorten(s)
    }
}
