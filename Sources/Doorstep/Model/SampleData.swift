import Foundation

/// The orders from the mockup, anchored to today so the preview always looks current.
enum SampleData {
    static func orders(now: Date = Date()) -> [Order] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            cal.date(byAdding: .day, value: offset, to: today)!.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        func order(_ id: String, _ merchant: String, _ items: [String], carrier: String?, tracking: String?, orderNo: String,
                   status: OrderStatus, stage: Int, eta: Date?, by: String? = nil, original: Date? = nil,
                   total: String, events: [(OrderStatus, Date)]) -> Order {
            Order(
                id: id, merchant: merchant, items: items.map { OrderItem(name: $0) }, fallbackTitle: items.first ?? "",
                carrierName: carrier, trackingNumber: tracking, orderNumber: orderNo, status: status, stage: stage,
                expectedDelivery: eta, expectedByTime: by, originalExpected: original,
                orderedAt: events.first?.1, deliveredAt: status == .delivered ? events.last?.1 : nil, total: total,
                events: events.map { OrderEvent(messageId: "sample-\(id)-\($0.0.rawValue)", status: $0.0, date: $0.1) },
                latestMessageId: "sample", latestThreadId: "sample", lastUpdated: events.last?.1 ?? now
            )
        }

        return [
            order("aero", "Amazon", ["AeroPress Go Travel Coffee Press"], carrier: "Amazon Logistics", tracking: "TBA318402957000",
                  orderNo: "113-4820193-5527409", status: .outForDelivery, stage: 2, eta: today, by: "by 8 PM", total: "$39.95",
                  events: [(.ordered, day(-3, 21, 14)), (.shipped, day(-2, 18, 25)), (.outForDelivery, day(0, 7, 42))]),
            order("supp", "Amazon", ["Vitamin D3 + K2, 5000 IU", "Magnesium Glycinate, 120 ct"], carrier: "USPS", tracking: "9400111899223401776521",
                  orderNo: "113-2291837-0418226", status: .shipped, stage: 1, eta: day(1, 0), total: "$31.48",
                  events: [(.ordered, day(-2, 8, 2)), (.shipped, day(-1, 16, 47))]),
            order("cable", "Amazon", ["Anker USB-C Cable, 6 ft (2-pack)"], carrier: "UPS", tracking: "1Z999AA10123456784",
                  orderNo: "113-7730415-2209931", status: .shipped, stage: 1, eta: day(1, 0), total: "$14.99",
                  events: [(.ordered, day(-2, 22, 31)), (.shipped, day(-1, 21, 12))]),
            order("swan", "Swanson Vitamins", ["Swanson Celery Seed Extract, 500 mg"], carrier: "USPS", tracking: "9405511206204815203744",
                  orderNo: "SW-48210377", status: .shipped, stage: 1, eta: day(1, 0), total: "$12.79",
                  events: [(.ordered, day(-4, 13, 20)), (.shipped, day(-2, 11, 5))]),
            order("drip", "Etsy", ["Ceramic Pour-Over Dripper"], carrier: "USPS", tracking: "9361289876543210987655",
                  orderNo: "3194028817", status: .delayed, stage: 1, eta: day(2, 0), original: day(-1, 0), total: "$48.00",
                  events: [(.ordered, day(-7, 19, 55)), (.shipped, day(-5, 14, 10)), (.delayed, day(-1, 20, 3))]),
            order("shoe", "Allbirds", ["Tree Runners, Size 10"], carrier: "FedEx", tracking: "771234567890",
                  orderNo: "AB-1029384", status: .shipped, stage: 1, eta: day(3, 0), total: "$98.00",
                  events: [(.ordered, day(-2, 12, 40)), (.shipped, day(0, 9, 18))]),
            order("swtr", "Everlane", ["Merino Crew Sweater, Navy"], carrier: nil, tracking: nil,
                  orderNo: "EV-5530291", status: .ordered, stage: 0, eta: day(4, 0), total: "$88.00",
                  events: [(.ordered, day(-1, 15, 33))]),
            order("case", "Amazon", ["Kindle Paperwhite Case"], carrier: "Amazon Logistics", tracking: "TBA317700281000",
                  orderNo: "113-0091726-6618304", status: .delivered, stage: 3, eta: nil, total: "$19.99",
                  events: [(.ordered, day(-4, 18, 12)), (.shipped, day(-3, 17, 40)), (.outForDelivery, day(-1, 9, 3)), (.delivered, day(-1, 14, 14))]),
            order("sock", "Bombas", ["Running Socks, 3-pack"], carrier: "USPS", tracking: "9400111899223399001287",
                  orderNo: "BMB-772031", status: .delivered, stage: 3, eta: nil, total: "$42.00",
                  events: [(.ordered, day(-6, 8, 30)), (.shipped, day(-5, 16, 15)), (.outForDelivery, day(-2, 7, 48)), (.delivered, day(-2, 11, 2))]),
            order("lamp", "IKEA", ["Desk Lamp, Matte White"], carrier: "FedEx", tracking: "771099882231",
                  orderNo: "1258834902", status: .delivered, stage: 3, eta: nil, total: "$29.99",
                  events: [(.ordered, day(-8, 13, 2)), (.shipped, day(-6, 10, 20)), (.outForDelivery, day(-3, 8, 11)), (.delivered, day(-3, 16, 37))]),
        ]
    }
}
