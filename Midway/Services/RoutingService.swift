import Foundation
import MapKit

/// Estimates one-way travel time per participant. Uses live MapKit ETAs
/// where the transport mode is supported and falls back to a distance/speed
/// estimate (biking, or when routing fails offline).
struct RoutingService {
    func travelMinutes(from origin: Coordinate,
                       to destination: Coordinate,
                       mode: TransportMode) async -> Double {
        if TestEnvironment.isUITest {
            return estimatedMinutes(from: origin, to: destination, mode: mode)
        }
        if let transportType = mkTransportType(for: mode) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.clCoordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.clCoordinate))
            request.transportType = transportType
            if let eta = try? await MKDirections(request: request).calculateETA() {
                return eta.expectedTravelTime / 60
            }
        }
        return estimatedMinutes(from: origin, to: destination, mode: mode)
    }

    /// Haversine-distance estimate with a 1.3x detour factor for street routing.
    func estimatedMinutes(from origin: Coordinate,
                          to destination: Coordinate,
                          mode: TransportMode) -> Double {
        let km = origin.distance(to: destination) / 1000 * 1.3
        return km / mode.estimatedKmPerHour * 60
    }

    private func mkTransportType(for mode: TransportMode) -> MKDirectionsTransportType? {
        switch mode {
        case .driving: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        case .biking: return nil // MKDirections has no cycling ETA; use the estimate.
        }
    }
}
