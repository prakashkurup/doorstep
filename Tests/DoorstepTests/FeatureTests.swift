import Foundation
import Testing
@testable import Doorstep

private let cal = Calendar.current
private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

@Suite struct ReturnParsingTests {
    @Test func statuses() {
        #expect(Heuristics.returnStatus(subject: "Your return is started", head: "") == .started)
        #expect(Heuristics.returnStatus(subject: "Your return label is ready", head: "") == .started)
        #expect(Heuristics.returnStatus(subject: "Your return was dropped off", head: "") == .shipped)
        #expect(Heuristics.returnStatus(subject: "We've received your return", head: "") == .received)
        #expect(Heuristics.returnStatus(subject: "Your refund has been issued", head: "") == .refunded)
        #expect(Heuristics.returnStatus(subject: "You're getting a $5.49 refund: [Great Value Paper Plates]", head: "") == .refunded)
    }

    @Test func deliveryEmailMentioningReturnsIsNotAReturn() {
        // The body has "return label" boilerplate; the subject is a delivery.
        #expect(Heuristics.returnStatus(subject: "Delivered: Kindle Paperwhite Case", head: "Need to return? Print a return label") == nil)
    }

    @Test func refundDetails() {
        #expect(Heuristics.refundAmount(in: "You're getting a $5.49 refund: [Plates]") == "$5.49")
        #expect(Heuristics.refundAmount(in: "Refund amount: $42.00 to your Visa") == "$42.00")
        #expect(Heuristics.bracketedItem("You're getting a $5.49 refund: [Great Value Paper Plates]") == "Great Value Paper Plates")
    }

    @Test func buildsReturnCases() {
        func f(_ id: String, _ s: ReturnStatus, _ d: Date, amount: String? = nil) -> EmailFinding {
            EmailFinding(messageId: id, threadId: "t\(id)", date: d, subject: "s", merchant: "Uniqlo",
                         items: [OrderItem(name: "Down Jacket")], orderNumber: "UQ-883104", status: nil,
                         returnStatus: s, refundAmount: amount)
        }
        let cases = OrderBuilder.buildReturns(from: [
            f("1", .started, date(2026, 10, 8)),
            f("2", .shipped, date(2026, 10, 9)),
            f("3", .refunded, date(2026, 10, 12), amount: "$59.90"),
        ], orders: OrderBuilder.build(now: date(2026, 10, 12), from: [
            EmailFinding(messageId: "o", threadId: "to", date: date(2026, 10, 1), subject: "Delivered", merchant: "Uniqlo",
                         orderNumber: "UQ-883104", status: .delivered),
        ]))
        #expect(cases.count == 1)
        #expect(cases.first?.status == .refunded)
        #expect(cases.first?.refundAmount == "$59.90")
        #expect(cases.first?.isRefundOnly == false)
        #expect(cases.first?.events.count == 3)
    }

    @Test func refundFromStoreWithNoOrdersIsIgnored() {
        let movie = EmailFinding(messageId: "1", threadId: "t", date: date(2026, 10, 9), subject: "Your refund", merchant: "AMC Theatres",
                                 orderNumber: "8812", status: nil, returnStatus: .refunded, refundAmount: "$48.28")
        #expect(OrderBuilder.buildReturns(from: [movie], orders: []).isEmpty)
    }

    @Test func returnsAreNotOrders() {
        let finding = EmailFinding(messageId: "1", threadId: "t", date: date(2026, 10, 9), subject: "s", merchant: "Walmart",
                                   orderNumber: "1", status: nil, returnStatus: .refunded, refundAmount: "$5.49")
        #expect(OrderBuilder.build(now: date(2026, 10, 11), from: [finding]).isEmpty)
    }
}

@Suite struct DeliveryDetailTests {
    @Test func signature() {
        #expect(Heuristics.signatureRequired(in: "Adult signature required for this delivery"))
        #expect(Heuristics.signatureRequired(in: "This package requires a signature"))
        #expect(!Heuristics.signatureRequired(in: "No signature required. Leave at door."))
        #expect(!Heuristics.signatureRequired(in: "Your package is on its way"))
    }

    @Test func statedReturnDeadline() {
        let d = Heuristics.returnDeadline(in: "Return or replace items: Eligible through November 10, 2026", emailDate: date(2026, 10, 11))
        #expect(d == cal.startOfDay(for: date(2026, 11, 10)))
    }

    @Test func defaultReturnWindowFromDelivery() {
        let delivered = EmailFinding(messageId: "1", threadId: "t", date: date(2026, 10, 1), subject: "Delivered: Case", merchant: "Amazon",
                                     orderNumber: "113-1", status: .delivered)
        let order = OrderBuilder.build(now: date(2026, 10, 11), from: [delivered]).first
        #expect(order?.returnBy == cal.startOfDay(for: date(2026, 10, 31)))
        #expect(order?.returnByEstimated == true)
    }

    @Test func groceryHasNoReturnWindow() {
        var delivered = EmailFinding(messageId: "1", threadId: "t", date: date(2026, 10, 7), subject: "Delivered: Milk +19 items", merchant: "Walmart",
                                     orderNumber: "2000-1", status: .delivered)
        delivered.isGrocery = true
        #expect(OrderBuilder.build(now: date(2026, 10, 11), from: [delivered]).first?.returnBy == nil)
    }

    @Test func moneyAmounts() {
        #expect(OrderStore.amount("$1,234.56") == 1234.56)
        #expect(OrderStore.amount(nil) == nil)
    }
}

@Suite struct LiveTrackingParseTests {
    @Test func parses17TrackResponse() throws {
        let json = """
        {"number":"1Z999AA10123456785","carrier":100002,
         "track_info":{
           "latest_status":{"status":"OutForDelivery","sub_status":"OutForDelivery_Other"},
           "time_metrics":{"estimated_delivery_date":{"source":"Official","from":"2026-10-12T10:30:00-07:00","to":"2026-10-12T14:30:00-07:00"}},
           "tracking":{"providers":[{"provider":{"key":100002,"name":"UPS"},
             "events":[
               {"time_iso":"2026-10-12T03:05:00-07:00","description":"Arrived at Facility","location":"Kent, WA, US"},
               {"time_iso":"2026-10-12T07:41:00-07:00","description":"Out For Delivery Today","location":"Kent, WA, US"}
             ]}]}}}
        """
        let item = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let live = TrackingService.parse(item, now: date(2026, 10, 12, 8))
        #expect(live.status == "OutForDelivery")
        #expect(live.mappedStatus == .outForDelivery)
        #expect(live.carrierName == "UPS")
        #expect(live.events.count == 2)
        #expect(live.events.first?.description == "Out For Delivery Today")   // newest first
        #expect(live.events.first?.location == "Kent, WA, US")
        #expect(live.estimatedFrom != nil && live.estimatedTo != nil)
    }

    @Test func toleratesMissingFields() {
        let live = TrackingService.parse(["number": "X"], now: Date())
        #expect(live.status == "NotFound")
        #expect(live.mappedStatus == nil)
        #expect(live.events.isEmpty)
    }
}
