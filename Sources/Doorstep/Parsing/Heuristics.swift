import Foundation

/// Pattern-based extraction. Works without Apple Intelligence and catches the
/// structured bits (tracking numbers, order numbers) more reliably than a model.
enum Heuristics {
    static func extract(subject: String, text: String, fromName: String, fromAddress: String, emailDate: Date) -> PartialFinding {
        var r = PartialFinding()
        let head = subject + "\n" + String(text.prefix(1200))

        r.status = status(subject: subject, head: head)
        r.items = subjectItems(subject)
        r.trackingNumber = tracking(in: text)
        r.carrierName = carrierName(in: head + String(text.prefix(3000)), tracking: r.trackingNumber)
        r.orderNumber = orderNumber(in: subject + "\n" + text)
        (r.expectedDate, r.expectedByTime) = expected(in: head, emailDate: emailDate)
        r.total = total(in: text)
        r.merchant = merchant(fromName: fromName, address: fromAddress)
        r.isOrder = r.status != nil && (r.trackingNumber != nil || r.orderNumber != nil || !r.items.isEmpty)
        return r
    }

    // MARK: Exclusions

    /// Mail that talks about deliveries but is never an order: USPS Informed Delivery
    /// digests (letters in the mailbox).
    static func isExcluded(subject: String, fromAddress: String) -> Bool {
        let s = subject.lowercased()
        let from = fromAddress.lowercased()
        return from.contains("informeddelivery") || s.contains("daily digest")
    }

    // MARK: Returns and refunds

    /// Returns emails are recognized from the subject (and the first lines), strongest state first.
    static func returnStatus(subject: String, head: String) -> ReturnStatus? {
        let s = subject.lowercased()
        let h = String(head.lowercased().prefix(500))
        func has(_ p: String, _ t: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        // Delivery emails often say "Need to return? Print a return label", so the body only
        // counts when the subject is about a return or refund.
        let texts = has("return|refund", s) ? [s, h] : [s]
        for text in texts {
            if has("refund (has been |was )?(issued|processed|completed|initiated|is on its way)|you('re| are) getting a \\$[\\d.,]+ refund|your refund|refunded|refund of \\$", text) { return .refunded }
            if has("(we('ve| have) )?received your return|return (has been |was )?received|return (is )?complete", text) { return .received }
            if has("return (was |has been )?(dropped off|shipped|in transit|scanned|on its way)|we('ll| will) let you know when (we|your return)", text) { return .shipped }
            if has("return (is |has been |was )?(request(ed)?|started|initiated|authorization|label|confirmation|ready|created)|drop-?off code|your return (of|for)|return(ing)? your item", text) { return .started }
        }
        return nil
    }

    static func refundAmount(in text: String) -> String? {
        let patterns = [
            "(?i)refund(?:ed)?(?: amount)?(?: of)?\\s*:?\\s*(\\$\\s?[\\d,]+\\.\\d{2})",
            "(?i)(\\$\\s?[\\d,]+\\.\\d{2})\\s+refund",
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1)).replacingOccurrences(of: " ", with: "")
            }
        }
        return nil
    }

    /// `You're getting a $5.49 refund: [Great Value Paper Plates]` → "Great Value Paper Plates"
    static func bracketedItem(_ subject: String) -> String? {
        guard let open = subject.firstIndex(of: "["), let close = subject[open...].firstIndex(of: "]") else { return nil }
        let name = subject[subject.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: Delivery details

    static func signatureRequired(in text: String) -> Bool {
        let t = text.lowercased()
        guard t.range(of: "(adult |direct |indirect )?signature (is )?required|requires? (a|an adult) signature|must (be )?sign(ed)? for", options: .regularExpression) != nil else { return false }
        return t.range(of: "no signature (is )?required|signature not required", options: .regularExpression) == nil
    }

    /// "Return by Nov 9", "eligible for return through November 10, 2026", "returnable until …".
    static func returnDeadline(in text: String, emailDate: Date) -> Date? {
        let lower = text.lowercased()
        guard let kw = lower.range(of: "return(s)? (by|until|before)|returnable (until|through|by)|eligible for (a )?return(s)? (until|through|by)|return window (closes|ends)( on)?|eligible through", options: .regularExpression) else { return nil }
        let window = String(text[kw.upperBound...].prefix(40))
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: window, range: NSRange(location: 0, length: (window as NSString).length)),
              let date = match.date else { return nil }
        // A return deadline is after the email and within a year.
        guard date > emailDate, date < emailDate.addingTimeInterval(400 * 86_400) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    static func isGroceryDelivery(subject: String) -> Bool {
        subject.range(of: "delivery order|your delivery should arrive|grocery|curbside|pickup order|order is ready for pickup",
                      options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Status

    // MARK: Status

    static func status(subject: String, head: String) -> OrderStatus? {
        let s = subject.lowercased()
        // Progress trackers print every step ("Ordered / Shipped / Out for delivery / Delivered")
        // as separate lines; those say nothing about the current state, so remove them.
        let h = head.lowercased().replacingOccurrences(
            of: "(?m)^\\s*(ordered|shipped|out for delivery|delivered|in transit|order placed)\\s*$",
            with: "", options: .regularExpression)
        func has(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

        for text in [s, h] {
            if has("out for delivery|arriving today|will be delivered today|delivering today", text) { return .outForDelivery }
            if has("delay|running late|delivery exception|unable to deliver|delivery attempt", text) { return .delayed }
            if has("\\bdelivered\\b", text) && !has("(will|to) be delivered|get(s)? delivered|delivered by|be delivered", text) { return .delivered }
            if has("(has|have|was|were) arrived|was left (at|in|by)|dropped off|left at your", text) { return .delivered }
            if has("shipped|on (its|the) way|in transit|has been dispatched|dispatched|shipment|out of the warehouse", text) { return .shipped }
            if has("order (confirmation|confirmed|received|placed)|order #?[a-z0-9-]{4,} (is )?confirmed|thanks for (your order|shopping)|thank you for (your (order|purchase)|shopping)|^ordered\\b|we('ve| have) received your order", text) { return .ordered }
            // Confirmations also say "Arriving Monday", so this is the weakest signal.
            if has("\\barriving\\b", text) { return .shipped }
        }
        return nil
    }

    /// Amazon-style subjects: `Shipped: "Anker USB-C Cable…" and 1 more item`.
    static func subjectItems(_ subject: String) -> [String] {
        if let walmartStyle = truncatedSubjectItems(subject) { return walmartStyle }
        if let category = amazonCategoryTitle(subject) { return [category] }
        guard let regex = try? NSRegularExpression(pattern: "[\"“]([^\"”]{3,})[\"”]") else { return [] }
        let ns = subject as NSString
        guard let m = regex.firstMatch(in: subject, range: NSRange(location: 0, length: ns.length)) else { return [] }
        var name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        name = name.replacingOccurrences(of: "\\.{3}$|…$", with: "", options: .regularExpression)
        var items = [shorten(name)]
        if let more = subject.range(of: "and (\\d+) more item", options: .regularExpression) {
            let n = Int(subject[more].filter(\.isNumber)) ?? 0
            items += Array(repeating: "", count: n)
        }
        return items
    }

    /// `Delivered: Nancy's Organic Whole... +19 items`, `Shipped: Method Daily Shower Sp... and 1 other item`.
    /// Amazon's `Shipped 2 items: Supplements` names a category, not a product, so it's skipped.
    private static func truncatedSubjectItems(_ subject: String) -> [String]? {
        let pattern = "^([^:]{3,40}):\\s*(.+?)(?:\\.{3}|…)\\s*(?:\\+\\s*(\\d+)\\s*(?:more\\s+)?items?|and\\s+(\\d+)\\s+(?:other|more)\\s+items?)?\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = subject as NSString
        guard let m = re.firstMatch(in: subject, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let prefix = ns.substring(with: m.range(at: 1))
        if prefix.range(of: "\\d+\\s+items?", options: .regularExpression) != nil { return nil }
        let name = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        var extra = 0
        for g in [3, 4] where m.range(at: g).location != NSNotFound { extra = Int(ns.substring(with: m.range(at: g))) ?? 0 }
        return [name] + Array(repeating: "", count: extra)
    }

    /// Amazon no longer names products in shipping mail, only categories:
    /// `Shipped 2 items: Supplements` → "2 items · Supplements" (as Gmail shows it).
    static func amazonCategoryTitle(_ subject: String) -> String? {
        let pattern = "^(?:shipped|delivered|out for delivery|arriving[^:]*|ordered)\\s+(\\d+)\\s+items?:\\s*(.+)$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = subject as NSString
        guard let m = re.firstMatch(in: subject, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let count = Int(ns.substring(with: m.range(at: 1))) ?? 1
        var categories = ns.substring(with: m.range(at: 2))
        categories = categories.replacingOccurrences(of: ",?\\s*(and|&)\\s+more$", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return count > 1 ? "\(count) items · \(categories)" : categories
    }

    /// Drops things the model sometimes mistakes for products: tracking numbers,
    /// driver names ("JANE D."), "1 item unavailable".
    static func cleanItems(_ items: [String], merchant: String?) -> [String] {
        items.filter { raw in
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { return true }  // placeholder for "and N more"
            if !s.contains(" "), s.count >= 8, s.contains(where: \.isNumber) { return false }
            if s.range(of: "^[A-Z]+ [A-Z]\\.?$", options: .regularExpression) != nil { return false }
            if s.range(of: "unavailable|^\\d+ items?$|substitut", options: [.regularExpression, .caseInsensitive]) != nil { return false }
            if let merchant, s.caseInsensitiveCompare(merchant) == .orderedSame { return false }
            return true
        }
    }

    static func shorten(_ raw: String, limit: Int = 60) -> String {
        // "Rain Jacket | 012 | L" → "Rain Jacket, 012, L"; drop a trailing "..." from truncated names.
        let name = raw.replacingOccurrences(of: "\\s*\\|\\s*", with: ", ", options: .regularExpression)
            .replacingOccurrences(of: "(\\.{3}|…)$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard name.count > limit else { return name }
        let cut = name.prefix(limit)
        if let space = cut.lastIndex(of: " ") { return String(cut[..<space]) }
        return String(cut)
    }

    // MARK: Tracking + order numbers

    static func tracking(in text: String) -> String? {
        let patterns = [
            "\\b1Z[0-9A-Z]{16}\\b",
            "\\bTBA\\d{12}\\b",
            "\\b9[2-5](?:[ ]?\\d){20}\\b",
            "(?i)(?:fedex|tracking (?:number|#|no\\.?))[^0-9A-Za-z]{0,30}(\\d{12}|\\d{15})\\b",
            "(?i)(?:dhl)[^0-9]{0,40}(\\d{10})\\b",
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let range = m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range
                return ns.substring(with: range).replacingOccurrences(of: " ", with: "")
            }
        }
        return nil
    }

    static func carrierName(in text: String, tracking: String?) -> String? {
        let l = text.lowercased()
        if l.contains("usps") || l.contains("postal service") { return "USPS" }
        if l.range(of: "\\bups\\b", options: .regularExpression) != nil { return "UPS" }
        if l.contains("fedex") { return "FedEx" }
        if l.contains("dhl") { return "DHL" }
        if l.contains("ontrac") { return "OnTrac" }
        if l.contains("amazon logistics") || tracking?.hasPrefix("TBA") == true { return "Amazon Logistics" }
        if let t = tracking {
            let c = Carrier.detect(tracking: t, name: nil, merchant: "")
            if c != .other { return c.displayName }
        }
        return nil
    }

    static func orderNumber(in text: String) -> String? {
        let patterns = [
            "\\b(\\d{3}-\\d{7}-\\d{7})\\b",
            "(?i)order\\s*(?:number|no\\.?|id|#)\\s*[:#]?\\s*#?\\s*([A-Z0-9][A-Z0-9-]{4,24})\\b",
            "(?i)order\\s+#\\s*([A-Z0-9][A-Z0-9-]{4,24})\\b",
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let value = ns.substring(with: m.range(at: 1))
                if value.contains(where: \.isNumber) { return value }
            }
        }
        return nil
    }

    // MARK: Dates

    static func expected(in text: String, emailDate: Date) -> (Date?, String?) {
        let cal = Calendar.current
        let lower = text.lowercased()
        let keywords = "(arriving|arrives|expected|estimated delivery|delivery date|will arrive|get it|delivered by|deliver(?:y|ed)? on|eta)"

        var byTime: String?
        if let r = lower.range(of: "by \\d{1,2}(:\\d{2})?\\s?(am|pm)", options: .regularExpression) {
            byTime = String(text[r]).replacingOccurrences(of: "am", with: "AM").replacingOccurrences(of: "pm", with: "PM")
        }

        guard let kw = lower.range(of: keywords, options: .regularExpression) else { return (nil, byTime) }
        let window = String(text[kw.upperBound...].prefix(60))
        let w = window.lowercased()

        if w.range(of: "\\btoday\\b", options: .regularExpression) != nil { return (cal.startOfDay(for: emailDate), byTime) }
        if w.range(of: "\\btomorrow\\b", options: .regularExpression) != nil {
            return (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: emailDate)), byTime)
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let match = detector.firstMatch(in: window, range: NSRange(location: 0, length: (window as NSString).length)),
           var date = match.date {
            // Detector resolves relative to "now"; re-anchor bare weekdays to the email's date.
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            if let idx = weekdays.firstIndex(where: { w.contains($0) }), w.range(of: "\\d", options: .regularExpression) == nil {
                var d = cal.startOfDay(for: emailDate)
                for _ in 0..<7 where cal.component(.weekday, from: d) != idx + 1 { d = cal.date(byAdding: .day, value: 1, to: d)! }
                date = d
            }
            return (cal.startOfDay(for: date), byTime)
        }
        return (nil, byTime)
    }

    /// The amount charged. Stores lay this out differently, so try in order:
    /// 1. a total label with the amount on the same line — "Total $20.74" (Amazon);
    /// 2. an explicit charge — "Amount $152.19" (Columbia, whose labels and amounts sit in
    ///    separate columns, so "Order Total:" is followed by the subtotal);
    /// 3. a total label with the amount a line or two below — "Order total / Includes all
    ///    fees, taxes and discounts $39.45" (Walmart).
    /// Savings and subtotals never count.
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).replacingOccurrences(of: " ", with: "")
        }
    }

    static func total(in text: String) -> String? {
        let amount = "(\\$\\s?[\\d,]+\\.\\d{2})"
        let strong = "(?:order total|grand total|total charged|amount charged|total paid|payment total|order amount|estimated total|total amount)"
        let weakTotal = "(?i)(?<!sub)(?<!item )(?<!saved a )(?<!saved )\\btotal\\b[ \\t]*:?[ \\t]*" + amount
        // "Total: $39.99" repeated with different amounts is a per-item column, not the order total.
        let weakValues = Set(matches(weakTotal, in: text))
        var patterns = ["(?i)\\b" + strong + "\\b[^$\\n]{0,40}?" + amount]
        if weakValues.count <= 1 { patterns.append(weakTotal) }
        patterns += [
            "(?i)(?:^|\\n)\\s*(?:amount(?: charged| paid)?|you paid|charged to [^$\\n]{0,30})\\s*:?\\s*" + amount,
            "(?i)\\b" + strong + "\\b[^$\\n]{0,70}\\n[^$\\n]{0,70}?" + amount,
            // "Total" alone on its line, amount on the next (Igloo).
            "(?i)(?:^|\\n)[ \\t]*total[ \\t]*:?[ \\t]*\\n[ \\t]*" + amount,
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1)).replacingOccurrences(of: " ", with: "")
            }
        }
        return nil
    }

    // MARK: Merchant

    /// "COLUMBIA SPORTSWEAR COMPANY" → "Columbia Sportswear", "Walmart.com" → "Walmart", "USPS Tracking" → "USPS".
    static func tidyMerchant(_ raw: String) -> String {
        var name = raw
        let noise = ["\\.com\\b", "\\s*(shipment tracking|tracking|shipping|order updates?|orders?|customer (service|care)|notifications?|support|team|store|shop|no-?reply|company|inc\\.?|llc)\\s*$", "^(the )"]
        for _ in 0..<2 {
            for n in noise { name = name.replacingOccurrences(of: n, with: "", options: [.regularExpression, .caseInsensitive]) }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " -|·\""))
        if name.count > 4, name == name.uppercased(), name.contains(where: \.isLetter) { name = name.capitalized }
        return name
    }

    static let carriers: Set<String> = ["UPS", "USPS", "FedEx", "DHL", "OnTrac"]

    /// Services that send shipping mail on a store's behalf; their domain isn't the store's.
    static let sendingPlatforms: Set<String> = [
        "narvar.com", "aftership.com", "shopify.com", "shopifyemail.com", "myshopify.com", "klaviyomail.com",
        "klaviyo.com", "route.com", "parcelpanel.com", "wonderment.com", "malomo.com", "sendgrid.net",
        "amazonses.com", "mcsv.net", "rsgsv.net", "mailchimpapp.com", "exacttarget.com", "bluecore.com",
        "shipstation.com", "shippo.com", "easypost.com", "ordergroove.com", "attn.tv", "gorgias.com",
    ]

    /// shipment-tracking@email.amazon.com → amazon.com; nil for sending platforms.
    static func registrableDomain(of address: String) -> String? {
        guard let host = address.split(separator: "@").last?.lowercased(), host.contains(".") else { return nil }
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return nil }
        let domain = labels.suffix(2).joined(separator: ".")
        return sendingPlatforms.contains(domain) ? nil : domain
    }

    /// Best guess at a store's website from its name: "Costco" → costco.com.
    static func guessDomain(forMerchant merchant: String) -> String? {
        let known = ["amazon": "amazon.com", "walmart": "walmart.com", "target": "target.com", "costco": "costco.com",
                     "macys": "macys.com", "macy's": "macys.com", "columbia sportswear": "columbia.com", "columbia": "columbia.com",
                     "best buy": "bestbuy.com", "home depot": "homedepot.com", "etsy": "etsy.com", "ikea": "ikea.com",
                     "apple": "apple.com", "nike": "nike.com", "rei": "rei.com", "wayfair": "wayfair.com", "usps": "usps.com",
                     "ups": "ups.com", "fedex": "fedex.com", "dhl": "dhl.com", "chewy": "chewy.com", "nordstrom": "nordstrom.com"]
        let key = merchant.lowercased()
        if let d = known[key] { return d }
        let slug = key.filter { $0.isLetter || $0.isNumber }
        return slug.count >= 3 ? slug + ".com" : nil
    }

    static func merchant(fromName: String, address: String) -> String {
        let name = tidyMerchant(fromName)
        if !name.isEmpty, !name.contains("@") { return name }

        // Fall back to the sender's domain: orders@shop.allbirds.com → Allbirds
        let domain = address.split(separator: "@").last.map(String.init) ?? address
        let parts = domain.split(separator: ".")
        let core = parts.count >= 2 ? String(parts[parts.count - 2]) : domain
        return core.prefix(1).uppercased() + core.dropFirst()
    }
}
