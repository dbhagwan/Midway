import Foundation
import CoreLocation

/// One-shot location fetches with per-session consent. Midway never tracks
/// location in the background; it asks at planning time and applies the
/// sharing level the user chose (exact / approximate / manual / none).
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinate, Error>?

    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: return "Location access was denied. You can type a place instead."
            case .unavailable: return "Couldn't determine your location."
            }
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Returns the current coordinate, already reduced to the requested
    /// sharing level. `manual`/`none` callers should not invoke this.
    func currentCoordinate(sharing level: LocationSharingLevel) async throws -> Coordinate {
        let exact = try await requestOnce()
        switch level {
        case .exact: return exact
        case .approximate: return exact.approximate
        case .manual, .none: throw LocationError.unavailable
        }
    }

    private func requestOnce() async throws -> Coordinate {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: Coordinate(location.coordinate))
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: LocationError.unavailable)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(throwing: LocationError.denied)
            continuation = nil
        }
    }

    /// Geocode a typed place name ("Dolores Park") into a coordinate,
    /// for the `manual` sharing level.
    func coordinate(forPlaceNamed name: String) async throws -> Coordinate {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(name)
        guard let location = placemarks.first?.location else {
            throw LocationError.unavailable
        }
        return Coordinate(location.coordinate)
    }
}
