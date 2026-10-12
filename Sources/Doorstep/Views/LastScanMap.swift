import MapKit
import SwiftUI

/// A small, non-interactive map of the carrier's last scan ("Kent, WA").
struct LastScanMap: View {
    let place: String
    @State private var coordinate: CLLocationCoordinate2D?

    private static var cache: [String: CLLocationCoordinate2D] = [:]

    var body: some View {
        Group {
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)),
                    interactionModes: []) {
                    Marker(place, systemImage: "shippingbox.fill", coordinate: coordinate)
                        .tint(Palette.orange)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))
                .overlay(alignment: .bottomLeading) {
                    Label("Last scan · \(place)", systemImage: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .accessibilityLabel("Map showing the last scan in \(place)")
            }
        }
        .task(id: place) { await locate() }
    }

    private func locate() async {
        if let cached = Self.cache[place] { coordinate = cached; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return }
        let found = item.location.coordinate
        Self.cache[place] = found
        withAnimation(.easeOut(duration: 0.3)) { coordinate = found }
    }
}
