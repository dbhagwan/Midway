import Foundation
import MapKit

/// Finds candidate venues near a coordinate using MapKit local search.
struct PlacesService {
    /// Search for venues of the given kind near `center`.
    func searchVenues(near center: Coordinate,
                      query: String,
                      radiusMeters: CLLocationDistance = 3000,
                      limit: Int = 12) async throws -> [Venue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: center.clCoordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(limit).compactMap { item in
            guard let name = item.name else { return nil }
            return Venue(
                name: name,
                category: item.pointOfInterestCategory.map(Self.label(for:)) ?? query,
                areaName: item.placemark.subLocality
                    ?? item.placemark.locality
                    ?? "",
                coordinate: Coordinate(item.placemark.coordinate),
                priceLevel: nil // MapKit does not expose price; the engine treats unknown as neutral.
            )
        }
    }

    private static func label(for category: MKPointOfInterestCategory) -> String {
        // "MKPOICategoryCafe" -> "Cafe"
        let raw = category.rawValue
        return raw.replacingOccurrences(of: "MKPOICategory", with: "")
    }
}
