import Foundation
import CoreLocation

// MARK: - Coordinate

/// A Codable, Hashable wrapper around a geographic coordinate.
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Straight-line distance in meters.
    func distance(to other: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// Rounded to ~1 km precision, used for "approximate" location sharing.
    var approximate: Coordinate {
        Coordinate(latitude: (latitude * 100).rounded() / 100,
                   longitude: (longitude * 100).rounded() / 100)
    }
}

// MARK: - Meetup vocabulary

enum MeetupType: String, Codable, CaseIterable, Identifiable {
    case coffee, drinks, dinner, activity, study, quickCatchUp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coffee: return "Coffee"
        case .drinks: return "Drinks"
        case .dinner: return "Dinner"
        case .activity: return "Activity"
        case .study: return "Study"
        case .quickCatchUp: return "Quick catch-up"
        }
    }

    var symbolName: String {
        switch self {
        case .coffee: return "cup.and.saucer.fill"
        case .drinks: return "wineglass.fill"
        case .dinner: return "fork.knife"
        case .activity: return "figure.run"
        case .study: return "book.fill"
        case .quickCatchUp: return "bubble.left.and.bubble.right.fill"
        }
    }

    /// Query used when searching for candidate venues.
    var searchQuery: String {
        switch self {
        case .coffee: return "coffee shop"
        case .drinks: return "bar"
        case .dinner: return "restaurant"
        case .activity: return "things to do"
        case .study: return "cafe with wifi"
        case .quickCatchUp: return "park cafe"
        }
    }
}

enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case driving, transit, biking, walking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driving: return "Driving"
        case .transit: return "Transit"
        case .biking: return "Biking"
        case .walking: return "Walking"
        }
    }

    var symbolName: String {
        switch self {
        case .driving: return "car.fill"
        case .transit: return "tram.fill"
        case .biking: return "bicycle"
        case .walking: return "figure.walk"
        }
    }

    /// Rough average speed in km/h, used when live routing is unavailable.
    var estimatedKmPerHour: Double {
        switch self {
        case .driving: return 32
        case .transit: return 22
        case .biking: return 14
        case .walking: return 4.8
        }
    }
}

enum BudgetRange: Int, Codable, CaseIterable, Identifiable, Comparable {
    case free = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .low: return "$"
        case .medium: return "$$"
        case .high: return "$$$"
        }
    }

    static func < (lhs: BudgetRange, rhs: BudgetRange) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum LocationSharingLevel: String, Codable, CaseIterable, Identifiable {
    /// Share precise GPS location for this planning session.
    case exact
    /// Share location rounded to about a kilometer.
    case approximate
    /// Type a neighborhood or landmark instead of sharing GPS.
    case manual
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .exact: return "Exact location"
        case .approximate: return "Approximate (~1 km)"
        case .manual: return "Type a place"
        case .none: return "Don't share"
        }
    }
}

// MARK: - Time windows

enum TimeWindowKind: String, Codable, CaseIterable, Identifiable {
    case now, tonight, tomorrow, thisWeekend, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .now: return "Now"
        case .tonight: return "Tonight"
        case .tomorrow: return "Tomorrow"
        case .thisWeekend: return "This weekend"
        case .custom: return "Custom"
        }
    }
}

struct TimeWindow: Codable, Hashable {
    var kind: TimeWindowKind
    var customStart: Date?
    var customEnd: Date?

    static let now = TimeWindow(kind: .now)

    /// The concrete time Midway proposes for a meetup inside this window.
    /// Never returns a time in the past: "tonight" at 9 PM means soon,
    /// not the 7 PM that already went by.
    func suggestedTime(calendar: Calendar = .current, from reference: Date = Date()) -> Date {
        // Leave enough time for everyone to travel.
        let earliest = reference.addingTimeInterval(45 * 60)
        switch kind {
        case .now:
            return earliest
        case .tonight:
            let sevenPM = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: reference) ?? reference
            return max(sevenPM, earliest)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference) ?? reference
            return calendar.date(bySettingHour: 18, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        case .thisWeekend:
            // First weekend day whose 2 PM is still reachable; late on a
            // weekend afternoon this rolls to the next weekend day (or
            // next weekend entirely).
            var day = reference
            for _ in 0..<8 {
                if calendar.isDateInWeekend(day),
                   let twoPM = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day),
                   twoPM >= earliest {
                    return twoPM
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            return earliest
        case .custom:
            return customStart ?? reference
        }
    }
}

// MARK: - Interests

/// Interest tags are free-form strings with a curated starter set.
enum InterestTag {
    static let presets: [String] = [
        "Bars", "Coffee", "Vegetarian food", "Vegan food", "Outdoors",
        "Sports", "Rooftops", "Live music", "Art", "Board games",
        "Hiking", "Bookstores", "Dessert", "Brunch", "Karaoke",
        "Quiet spots", "Dancing", "Movies", "Tea", "Street food",
    ]
}
