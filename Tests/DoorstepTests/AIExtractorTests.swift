import Foundation
import Testing
@testable import Doorstep

/// Runs the real on-device model; skipped where Apple Intelligence is off.
@Suite(.enabled(if: AIExtractor.isAvailable))
struct AIExtractorTests {
    @Test func readsAShippingEmail() async throws {
        let text = """
        Hi Prakash, your package has shipped!
        Swanson Celery Seed Extract Cellery Urinary Health Antioxidant Support Phytochemicals Volatile Oils Supplement Maximum Strength 500 mg 60 Capsules
        Qty: 1
        Order #SW-48210377
        Shipped via USPS — tracking 9405 5112 0620 4815 2037 44
        Estimated delivery: Monday, October 12
        """
        let r = try #require(await AIExtractor.extract(subject: "Your Swanson order has shipped",
                                                       sender: "Swanson Vitamins <orders@swansonvitamins.com>",
                                                       text: text,
                                                       emailDate: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9))!))
        print("AI result:", r.merchant ?? "-", r.items, r.status as Any, r.orderNumber ?? "-", r.trackingNumber ?? "-", r.expectedDate as Any)
        #expect(r.isOrder)
        #expect(r.status == .shipped)
        #expect(r.items.first.map { $0.count <= 60 } == true)
    }

    @Test func ignoresMarketing() async throws {
        let r = await AIExtractor.extract(subject: "Our biggest sale of the year starts now",
                                          sender: "Allbirds <hello@allbirds.com>",
                                          text: "Take 25% off everything. Free shipping on all orders this weekend. Shop now.",
                                          emailDate: Date())
        #expect(r?.isOrder != true)
    }
}
