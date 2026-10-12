import Foundation

struct LiveEvent: Codable, Hashable {
    let date: Date
    let description: String
    let location: String?
}

/// What the carrier itself reports for a tracking number, via 17TRACK.
struct LiveTracking: Codable, Hashable {
    /// 17TRACK main status: InfoReceived, InTransit, OutForDelivery, AvailableForPickup,
    /// Delivered, DeliveryFailure, Exception, Expired, NotFound.
    var status: String
    var events: [LiveEvent]   // newest first
    var estimatedFrom: Date?
    var estimatedTo: Date?
    var carrierName: String?
    var lastChecked: Date

    var mappedStatus: OrderStatus? {
        switch status {
        case "InTransit": .shipped
        case "OutForDelivery", "AvailableForPickup": .outForDelivery
        case "Delivered": .delivered
        case "DeliveryFailure", "Exception": .delayed
        default: nil
        }
    }

    var isReadyForPickup: Bool { status == "AvailableForPickup" }
}
