import Foundation
import MapKit

/// Finds candidate venues near a coordinate using MapKit local search.
struct PlacesService {
    /// Search for venues of the given kind near `center`.
    func searchVenues(near center: Coordinate,
                      query: String,
                      radiusMeters: CLLocationDistance = 3000,
                      limit: Int = 12) async throws -> [Venue] {
        if TestEnvironment.isUITest {
            return Self.cannedVenues(near: center)
        }
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

    /// Offline-safe candidates for UI tests/CI screenshots, placed around the
    /// group midpoint with varied categories and prices so scores differ.
    static func cannedVenues(near center: Coordinate) -> [Venue] {
        let specs: [(name: String, category: String, area: String,
                     dLat: Double, dLon: Double, price: BudgetRange?)] = [
            ("Ritual Coffee Roasters", "Cafe", "Hayes Valley", 0.0030, -0.0015, .low),
            ("Sightglass Coffee", "Cafe", "SoMa", -0.0040, 0.0050, .low),
            ("Mr. Tipple's Jazz Bar", "Bar, Live Music", "Civic Center", 0.0012, 0.0025, .medium),
            ("Greens Restaurant", "Vegetarian Restaurant", "Marina", 0.0060, -0.0040, .high),
            ("The Page", "Bar", "Lower Haight", -0.0025, -0.0055, .low),
            ("Souvla", "Restaurant", "Hayes Valley", 0.0018, -0.0008, .medium),
            ("Patricia's Green", "Park", "Hayes Valley", 0.0008, 0.0010, BudgetRange.free),
        ]
        return specs.map { spec in
            Venue(name: spec.name,
                  category: spec.category,
                  areaName: spec.area,
                  coordinate: Coordinate(latitude: center.latitude + spec.dLat,
                                         longitude: center.longitude + spec.dLon),
                  priceLevel: spec.price)
        }
    }
}
