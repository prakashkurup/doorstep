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

        var list = [
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
            order("late", "USPS", [], carrier: "USPS", tracking: "9534600000000000000017",
                  orderNo: "", status: .shipped, stage: 1, eta: day(-1, 0), total: "",
                  events: [(.shipped, day(-3, 2, 10))]),
            order("boots", "Amazon", ["Trail Hiking Boots, Size 10"], carrier: "Amazon Logistics", tracking: "TBA316620193000",
                  orderNo: "113-5520183-1100492", status: .delivered, stage: 3, eta: nil, total: "$89.99",
                  events: [(.ordered, day(-30, 9, 12)), (.shipped, day(-29, 15, 40)), (.delivered, day(-27, 13, 5))]),
        ]

        func update(_ id: String, _ change: (inout Order) -> Void) {
            if let i = list.firstIndex(where: { $0.id == id }) { change(&list[i]) }
        }
        // Live carrier scans on the package arriving today.
        update("aero") { o in
            o.carrierName = "UPS"
            o.trackingNumber = "1Z999AA10123456785"
            o.live = LiveTracking(
                status: "OutForDelivery",
                events: [
                    LiveEvent(date: day(0, 7, 41), description: "Out for delivery", location: "Kent, WA"),
                    LiveEvent(date: day(0, 3, 5), description: "Arrived at facility", location: "Kent, WA"),
                    LiveEvent(date: day(-1, 21, 52), description: "Departed facility", location: "Portland, OR"),
                    LiveEvent(date: day(-1, 16, 18), description: "Arrived at facility", location: "Portland, OR"),
                    LiveEvent(date: day(-2, 18, 30), description: "Picked up", location: "Portland, OR"),
                ],
                estimatedFrom: day(0, 10, 30), estimatedTo: day(0, 14, 30), carrierName: "UPS", lastChecked: now.addingTimeInterval(-240))
            o.deliveryWindow = "10:30 AM – 2:30 PM"
            o.expectedByTime = nil
        }
        update("cable") { $0.signatureRequired = true }
        update("late") { o in
            o.fallbackTitle = "Package via USPS"
            o.orderNumber = nil
            o.total = nil
        }
        for id in ["case", "sock", "lamp", "boots"] {
            update(id) { o in
                guard let at = o.deliveredAt, let days = ReturnPolicy.defaultDays(for: o.merchant) else { return }
                o.returnBy = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: at))
                o.returnByEstimated = true
            }
        }
        return list
    }

    static func returns(now: Date = Date()) -> [ReturnCase] {
        let day: (Int, Int) -> Date = { offset, hour in
            Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: now))!.addingTimeInterval(TimeInterval(hour * 3600))
        }
        return [
            ReturnCase(id: "r:sweater", merchant: "Uniqlo", title: "Ultra Light Down Jacket, M", status: .shipped, refundAmount: nil,
                       orderNumber: "UQ-883104", events: [
                        ReturnEvent(messageId: "s1", status: .started, date: day(-3, 10)),
                        ReturnEvent(messageId: "s2", status: .shipped, date: day(-1, 17)),
                       ], lastUpdated: day(-1, 17), imageURL: nil, merchantDomain: nil, latestThreadId: "sample", isRefundOnly: false),
            ReturnCase(id: "r:plates", merchant: "Walmart", title: "Great Value Paper Plates", status: .refunded, refundAmount: "$5.49",
                       orderNumber: "2000131-88341", events: [ReturnEvent(messageId: "s3", status: .refunded, date: day(-2, 9))],
                       lastUpdated: day(-2, 9), imageURL: nil, merchantDomain: nil, latestThreadId: "sample", isRefundOnly: true),
        ]
    }
}
