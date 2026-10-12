import Foundation
import Testing
@testable import Doorstep

private let cal = Calendar.current
private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

@Suite struct HeuristicsTests {
    @Test func amazonShippedSubject() {
        let r = Heuristics.extract(
            subject: "Shipped: \"Anker USB-C Cable, 6 ft (2-pack)\" and 1 more item",
            text: "Your package is on the way. Arriving tomorrow by 10 PM. Order # 113-7730415-2209931. Shipped with UPS 1Z999AA10123456784",
            fromName: "Amazon.com", fromAddress: "shipment-tracking@amazon.com", emailDate: date(2026, 10, 10))
        #expect(r.status == .shipped)
        #expect(r.items.first == "Anker USB-C Cable, 6 ft (2-pack)")
        #expect(r.items.count == 2)
        #expect(r.orderNumber == "113-7730415-2209931")
        #expect(r.trackingNumber == "1Z999AA10123456784")
        #expect(r.carrierName == "UPS")
        #expect(r.merchant == "Amazon")
        #expect(r.expectedByTime == "by 10 PM")
        #expect(r.expectedDate == cal.startOfDay(for: date(2026, 10, 11)))
        #expect(r.isOrder)
    }

    @Test func outForDeliveryBeatsShipped() {
        let s = Heuristics.status(subject: "Out for delivery: Your package has shipped and is arriving today", head: "")
        #expect(s == .outForDelivery)
    }

    @Test func futureDeliveredWordingIsNotDelivered() {
        let s = Heuristics.status(subject: "Your order will be delivered Wednesday", head: "Your order has shipped")
        #expect(s == .shipped)
    }

    @Test func progressTrackerTextIsIgnored() {
        let body = "Prakash, thanks for your order\nTrack package\nOrdered\nShipped\nOut for delivery\nDelivered\nArriving Monday"
        #expect(Heuristics.status(subject: "Ordered 1 item: Household Supplies", head: body) == .ordered)
        #expect(Heuristics.status(subject: "Your Amazon.com order", head: body) == .ordered)
    }

    @Test func confirmationPhrases() {
        #expect(Heuristics.status(subject: "Thanks for shopping with us!", head: "") == .ordered)
        #expect(Heuristics.status(subject: "Order #1975888 confirmed", head: "") == .ordered)
    }

    @Test func delivered() {
        #expect(Heuristics.status(subject: "Delivered: \"Kindle Paperwhite Case\"", head: "") == .delivered)
    }

    @Test func delayed() {
        #expect(Heuristics.status(subject: "Your package is running late", head: "") == .delayed)
    }

    @Test func uspsTrackingWithSpaces() {
        let t = Heuristics.tracking(in: "USPS Tracking: 9400 1118 9922 3401 7765 21 — see details")
        #expect(t == "9400111899223401776521")
    }

    @Test func weekdayResolvesFromEmailDate() {
        // Email sent Friday Oct 9 2026; "Arriving Wednesday" means Oct 14.
        let (d, _) = Heuristics.expected(in: "Arriving Wednesday", emailDate: date(2026, 10, 9))
        #expect(d == cal.startOfDay(for: date(2026, 10, 14)))
    }

    @Test func promoEmailIsNotAnOrder() {
        let r = Heuristics.extract(
            subject: "20% off your next order — this weekend only",
            text: "Shop the sale. Free shipping on orders over $50.",
            fromName: "Everlane", fromAddress: "hello@everlane.com", emailDate: date(2026, 10, 9))
        #expect(!r.isOrder)
    }

    @Test func arrivedMeansDelivered() {
        #expect(Heuristics.status(subject: "Your order has arrived!", head: "") == .delivered)
        #expect(Heuristics.status(subject: "Your package has arrived!", head: "") == .delivered)
    }

    @Test func nonOrderMailIsExcluded() {
        #expect(Heuristics.isExcluded(subject: "Your Daily Digest for Wed, 9/30 is ready to view", fromAddress: "USPSInformeddelivery@email.informeddelivery.usps.com"))
        // Refunds aren't excluded any more; they become entries in the Returns section.
        #expect(!Heuristics.isExcluded(subject: "You're getting a $5.49 refund: [Great Value Paper Plates]", fromAddress: "help@walmart.com"))
        #expect(!Heuristics.isExcluded(subject: "Shipped 1 item: Supplements", fromAddress: "shipment-tracking@amazon.com"))
    }

    @Test func walmartSubjectItems() {
        #expect(Heuristics.subjectItems("Delivered: Nancy's Organic Whole... +19 items") == ["Nancy's Organic Whole"] + Array(repeating: "", count: 19))
        #expect(Heuristics.subjectItems("Shipped: Method Daily Shower Sp... and 1 other item") == ["Method Daily Shower Sp", ""])
        #expect(Heuristics.subjectItems("Shipped 2 items: Supplements") == ["2 items · Supplements"])
        #expect(Heuristics.subjectItems("Shipped 1 item: Household Supplies") == ["Household Supplies"])
        #expect(Heuristics.subjectItems("Delivered 3 items: Swimwear, Hair Care, and more") == ["3 items · Swimwear, Hair Care"])
        #expect(Heuristics.shorten("Men’s Watertight II Rain Jacket | 012 | L") == "Men’s Watertight II Rain Jacket, 012, L")
        #expect(Heuristics.shorten("Swanson Celery Seed Ex...") == "Swanson Celery Seed Ex")
    }

    @Test func junkItemsDropped() {
        #expect(Heuristics.cleanItems(["JANE D.", "1 item unavailable", "1Z999BB10123456781", "Rain Jacket"], merchant: nil) == ["Rain Jacket"])
    }

    @Test func merchantTidying() {
        #expect(Heuristics.tidyMerchant("COLUMBIA SPORTSWEAR COMPANY") == "Columbia Sportswear")
        #expect(Heuristics.tidyMerchant("USPS Tracking") == "USPS")
        #expect(Heuristics.tidyMerchant("Walmart.com") == "Walmart")
        #expect(Heuristics.tidyMerchant("MACYS") == "Macys")
    }

    @Test func totals() {
        #expect(Heuristics.total(in: "Order #   111-1234567-7654321\nTotal         $20.74") == "$20.74")
        #expect(Heuristics.total(in: "Order total\nIncludes all fees, taxes and discounts      $39.45\nYou saved a total of        $9.95") == "$39.45")
        #expect(Heuristics.total(in: "You saved a total of $9.95") == nil)
        #expect(Heuristics.total(in: "Subtotal $30.00\nGrand Total: $32.85") == "$32.85")
        // Columbia: labels in one column, amounts in the next; the charge is stated separately.
        let columbia = "Item Subtotal:  $70.00\nSubtotal:\nShipping:\nTax:\nOrder Total:\n$137.85\n$0.00\n$14.34\n$152.19\nPayment\nVisa ending 1234\nAmount $152.19"
        #expect(Heuristics.total(in: columbia) == "$152.19")
        // Igloo: "Total" alone on a line in the confirmation; per-item "Total:" lines in the shipping email.
        #expect(Heuristics.total(in: "Subtotal\n$87.53\nShipping\n$9.99\nTax\n$10.15\nTotal\n$107.67") == "$107.67")
        #expect(Heuristics.total(in: "Cooler\nTotal: $ 39.99\nJug\nTotal: $ 22.99\nCooler\nTotal: $ 39.99") == nil)
        // Walmart: the temporary hold isn't the total.
        #expect(Heuristics.total(in: "Order total\nIncludes all fees, taxes and discounts      $64.25\nYou saved a total of        $10.37\n$69.47\nTemporary hold: $69.47") == "$64.25")
    }

    @Test func merchantFromSender() {
        #expect(Heuristics.merchant(fromName: "Swanson Vitamins Order Updates", address: "orders@swansonvitamins.com") == "Swanson Vitamins")
        #expect(Heuristics.merchant(fromName: "", address: "noreply@shop.allbirds.com") == "Allbirds")
    }

    @Test func longTitleShortened() {
        let long = "Swanson Celery Seed Extract Cellery Urinary Health Antioxidant Support Phytochemicals Volatile Oils Supplement"
        #expect(Heuristics.shorten(long).count <= 60)
    }
}

@Suite struct SchemaOrgTests {
    @Test func parcelDelivery() {
        let html = """
        <html><head><script type="application/ld+json">
        {"@context":"http://schema.org","@type":"ParcelDelivery",
         "carrier":{"@type":"Organization","name":"FedEx"},
         "trackingNumber":"771234567890",
         "expectedArrivalUntil":"2026-10-14T20:00:00-07:00",
         "deliveryStatus":{"@type":"OrderInTransit"},
         "itemShipped":{"@type":"Product","name":"Tree Runners, Size 10"},
         "partOfOrder":{"@type":"Order","orderNumber":"AB-1029384","merchant":{"@type":"Organization","name":"Allbirds"}}}
        </script></head><body>Hi</body></html>
        """
        let r = SchemaOrgParser.parse(html: html)
        #expect(r != nil)
        #expect(r?.trackingNumber == "771234567890")
        #expect(r?.carrierName == "FedEx")
        #expect(r?.status == .shipped)
        #expect(r?.orderNumber == "AB-1029384")
        #expect(r?.merchant == "Allbirds")
        #expect(r?.items == ["Tree Runners, Size 10"])
        #expect(r?.expectedDate != nil)
    }

    @Test func noMarkup() {
        #expect(SchemaOrgParser.parse(html: "<html><body>Thanks</body></html>") == nil)
    }
}

@Suite struct OrderBuilderTests {
    private let now = date(2026, 10, 11, 18)
    private func finding(_ id: String, _ status: OrderStatus, _ d: Date, order: String? = "113-1", tracking: String? = nil,
                         thread: String? = nil, items: [String] = []) -> EmailFinding {
        EmailFinding(messageId: id, threadId: thread ?? "t-\(id)", date: d, subject: "s", merchant: "Amazon",
                     items: items.map { OrderItem(name: $0) }, orderNumber: order, trackingNumber: tracking,
                     carrierName: nil, status: status)
    }

    @Test func mergesEmailsForSameOrder() {
        let orders = OrderBuilder.build(now: now, from: [
            finding("1", .ordered, date(2026, 10, 7), items: ["AeroPress Go"]),
            finding("2", .shipped, date(2026, 10, 8), tracking: "TBA318402957000"),
            finding("3", .outForDelivery, date(2026, 10, 11), order: nil, tracking: "TBA318402957000"),
        ])
        #expect(orders.count == 1)
        let o = orders[0]
        #expect(o.status == .outForDelivery)
        #expect(o.stage == 2)
        #expect(o.title == "AeroPress Go")
        #expect(o.events.map(\.status) == [.ordered, .shipped, .outForDelivery])
    }

    @Test func neverStepsBackwards() {
        let orders = OrderBuilder.build(now: now, from: [
            finding("1", .delivered, date(2026, 10, 10)),
            finding("2", .shipped, date(2026, 10, 11)),
        ])
        #expect(orders.first?.status == .delivered)
    }

    @Test func separateOrdersStaySeparate() {
        let orders = OrderBuilder.build(now: now, from: [
            finding("1", .shipped, date(2026, 10, 10), order: "A-1"),
            finding("2", .shipped, date(2026, 10, 10), order: "B-2"),
        ])
        #expect(orders.count == 2)
    }

    @Test func newestEmailWins() {
        // A misread "out for delivery" followed by a real "shipped" must show shipped.
        let orders = OrderBuilder.build(now: now, from: [
            finding("1", .outForDelivery, date(2026, 10, 10, 21)),
            finding("2", .shipped, date(2026, 10, 11, 3)),
        ])
        #expect(orders.first?.status == .shipped)
        #expect(orders.first?.stage == 1)
    }

    @Test func staleOutForDeliveryBecomesLikelyDelivered() {
        // Igloo: "out for delivery" on Sep 16 and nothing the app understood after.
        let orders = OrderBuilder.build(now: now, from: [finding("1", .outForDelivery, date(2026, 9, 16))])
        #expect(orders.first?.status == .delivered)
        #expect(orders.first?.deliveryInferred == true)
    }

    @Test func overdueShipmentBecomesLikelyDelivered() {
        var f = finding("1", .shipped, date(2026, 9, 25))
        f.expectedDate = date(2026, 9, 25, 0)
        let orders = OrderBuilder.build(now: now, from: [f])
        #expect(orders.first?.status == .delivered)
    }

    @Test func recentShipmentStaysActive() {
        var f = finding("1", .shipped, date(2026, 10, 11))
        f.expectedDate = date(2026, 10, 12, 0)
        #expect(OrderBuilder.build(now: now, from: [f]).first?.status == .shipped)
    }

    @Test func oldConfirmationWithNoShipmentIsDropped() {
        // San Diego Zoo pass, Top Pot pickup.
        #expect(OrderBuilder.build(now: now, from: [finding("1", .ordered, date(2026, 9, 27))]).isEmpty)
    }

    @Test func amazonMismatchedOrderNumbersMerge() {
        let orders = OrderBuilder.build(now: now, from: [
            finding("1", .shipped, date(2026, 9, 25), order: "112-1111111-2222222", items: ["Swimwear"]),
            finding("2", .delivered, date(2026, 9, 26), order: "112-3333333-4444444", items: ["Swimwear"]),
        ])
        #expect(orders.count == 1)
        #expect(orders.first?.deliveryInferred == nil)
    }

    @Test func carrierEmailTitle() {
        var f = finding("1", .delivered, date(2026, 10, 3), order: nil, tracking: "1Z999AA10123456795")
        f.subject = "Your UPS Package was delivered"
        f.merchant = "COSTCO"
        #expect(OrderBuilder.build(now: now, from: [f]).first?.title == "Package from Costco")
    }

    @Test func multiItemTitle() {
        let orders = OrderBuilder.build(now: now, from: [finding("1", .shipped, date(2026, 10, 10), items: ["Vitamin D3 + K2", "Magnesium"])])
        #expect(orders.first?.title == "Vitamin D3 + K2 and 1 more item")
    }
}

@Suite struct CarrierTests {
    @Test func detection() {
        #expect(Carrier.detect(tracking: "1Z999AA10123456784", name: nil, merchant: "") == .ups)
        #expect(Carrier.detect(tracking: "9400111899223401776521", name: nil, merchant: "") == .usps)
        #expect(Carrier.detect(tracking: "771234567890", name: nil, merchant: "") == .fedex)
        #expect(Carrier.detect(tracking: "TBA318402957000", name: nil, merchant: "") == .amazon)
        #expect(Carrier.detect(tracking: nil, name: "USPS", merchant: "") == .usps)
    }

    @Test func amazonLinksToOrder() {
        let url = Carrier.amazon.trackingURL(tracking: "TBA1", orderNumber: "113-1")
        #expect(url?.absoluteString.contains("orderID=113-1") == true)
    }
}
