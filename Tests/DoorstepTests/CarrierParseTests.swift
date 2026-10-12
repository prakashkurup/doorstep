import Foundation
import Testing
@testable import Doorstep

private func json(_ s: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
}

/// Sample responses shaped after each carrier's published API spec.
@Suite struct CarrierParseTests {
    @Test func ups() throws {
        let live = try #require(UPSTracker.parse(try json("""
        {"trackResponse":{"shipment":[{"inquiryNumber":"1Z999AA10123456784","package":[{
          "trackingNumber":"1Z999AA10123456784",
          "deliveryDate":[{"type":"SDD","date":"20261012"}],
          "deliveryTime":{"type":"EDW","startTime":"103000","endTime":"143000"},
          "currentStatus":{"type":"I","description":"Out For Delivery Today","code":"OT"},
          "activity":[
            {"date":"20261012","time":"074100","status":{"type":"I","description":"Out For Delivery Today"},"location":{"address":{"city":"KENT","stateProvince":"WA"}}},
            {"date":"20261012","time":"030500","status":{"type":"I","description":"Arrived at Facility"},"location":{"address":{"city":"KENT","stateProvince":"WA"}}}
          ]}]}]}}
        """), now: Date()))
        #expect(live.status == "OutForDelivery")
        #expect(live.events.count == 2)
        #expect(live.events.first?.location == "Kent, WA")
        #expect(live.events.first?.description == "Out For Delivery Today")
        let from = try #require(live.estimatedFrom), to = try #require(live.estimatedTo)
        #expect(Calendar.current.component(.hour, from: from) == 10)
        #expect(Calendar.current.component(.hour, from: to) == 14)
    }

    @Test func upsDelivered() throws {
        let live = try #require(UPSTracker.parse(try json("""
        {"trackResponse":{"shipment":[{"package":[{"currentStatus":{"type":"D","description":"Delivered"},
          "activity":[{"date":"20261003","time":"141400","status":{"type":"D","description":"DELIVERED"},"location":{"address":{"city":"KIRKLAND","stateProvince":"WA"}}}]}]}]}}
        """), now: Date()))
        #expect(live.status == "Delivered")
        #expect(live.events.first?.description == "Delivered")
    }

    @Test func usps() throws {
        let live = try #require(USPSTracker.parse(try json("""
        {"trackingNumber":"9400111899223401776521","statusCategory":"Out for Delivery","status":"Out for Delivery",
         "predictedDeliveryDate":"2026-10-12","predictedDeliveryWindowStartTime":"10:00","predictedDeliveryWindowEndTime":"14:00",
         "trackingEvents":[
           {"eventType":"Out for Delivery","eventTimestamp":"2026-10-12T07:10:00","GMTTimestamp":"2026-10-12T14:10:00Z","eventCity":"KIRKLAND","eventState":"WA"},
           {"eventType":"Arrived at Post Office","eventTimestamp":"2026-10-12T05:02:00","GMTTimestamp":"2026-10-12T12:02:00Z","eventCity":"KIRKLAND","eventState":"WA"}
         ]}
        """), now: Date()))
        #expect(live.status == "OutForDelivery")
        #expect(live.events.first?.description == "Out for Delivery")
        #expect(live.events.first?.location == "Kirkland, WA")
        #expect(live.estimatedFrom.map { Calendar.current.component(.hour, from: $0) } == 10)
        #expect(live.estimatedTo.map { Calendar.current.component(.hour, from: $0) } == 14)
    }

    @Test func fedex() throws {
        let live = try #require(FedExTracker.parse(try json("""
        {"output":{"completeTrackResults":[{"trackingNumber":"771234567890","trackResults":[{
          "latestStatusDetail":{"code":"IT","derivedCode":"IT","description":"In transit"},
          "estimatedDeliveryTimeWindow":{"window":{"begins":"2026-10-14T09:00:00-07:00","ends":"2026-10-14T17:00:00-07:00"}},
          "scanEvents":[
            {"date":"2026-10-12T21:52:00-07:00","eventDescription":"Departed FedEx location","scanLocation":{"city":"PORTLAND","stateOrProvinceCode":"OR"}},
            {"date":"2026-10-12T16:18:00-07:00","eventDescription":"Arrived at FedEx location","scanLocation":{"city":"PORTLAND","stateOrProvinceCode":"OR"}}
          ]}]}]}}
        """), now: Date()))
        #expect(live.status == "InTransit")
        #expect(live.events.first?.description == "Departed FedEx location")
        #expect(live.events.first?.location == "Portland, OR")
        #expect(live.estimatedFrom != nil && live.estimatedTo != nil)
    }

    @Test func fedexError() throws {
        let parsed = FedExTracker.parse(try json("""
        {"output":{"completeTrackResults":[{"trackResults":[{"error":{"code":"TRACKING.TRACKINGNUMBER.NOTFOUND"}}]}]}}
        """), now: Date())
        #expect(parsed == nil)
    }

    @Test func dhl() throws {
        let live = try #require(DHLTracker.parse(try json("""
        {"shipments":[{"id":"1234567890","status":{"statusCode":"delivered","status":"DELIVERED","timestamp":"2026-10-10T14:30:00Z"},
          "events":[
            {"timestamp":"2026-10-10T14:30:00Z","statusCode":"delivered","description":"Delivered","location":{"address":{"addressLocality":"Seattle, WA"}}},
            {"timestamp":"2026-10-10T08:00:00Z","statusCode":"transit","description":"With delivery courier","location":{"address":{"addressLocality":"Seattle, WA"}}}
          ]}]}
        """), now: Date()))
        #expect(live.status == "Delivered")
        #expect(live.mappedStatus == .delivered)
        #expect(live.events.first?.location == "Seattle, WA")
    }

    @Test func carrierFromTrackingNumber() {
        #expect(CarrierCredentials.kind(for: Carrier.detect(tracking: "1Z999AA10123456784", name: nil, merchant: "")) == .ups)
        #expect(CarrierCredentials.kind(for: Carrier.detect(tracking: "9400111899223401776521", name: nil, merchant: "")) == .usps)
        #expect(CarrierCredentials.kind(for: Carrier.detect(tracking: "771234567890", name: nil, merchant: "")) == .fedex)
        #expect(CarrierCredentials.kind(for: Carrier.detect(tracking: "1234567890", name: "DHL Express", merchant: "")) == .dhl)
        #expect(CarrierCredentials.kind(for: .amazon) == nil)
    }
}
