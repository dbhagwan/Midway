import Foundation

/// Simple JSON-on-disk persistence for the MVP. The shape of this type is
/// the contract a real Midway backend will implement later: profile,
/// friend graph, and meetups are Midway-owned data, never stored in Snap.
struct PersistenceStore {
    struct Snapshot: Codable {
        var profile: UserProfile?
        var friends: [Friend] = []
        var meetups: [Meetup] = []
        /// Demo mode: whether the seeded invite from Ava has been answered.
        var demoInviteResolved: Bool?
    }

    private let fileURL: URL

    init(filename: String = "midway-store.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
    }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot()
        }
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Demo data

/// Seed friends so the planner is demoable before the real backend exists.
/// Coordinates are San Francisco neighborhoods.
enum DemoData {
    static func seedFriends() -> [Friend] {
        [
            Friend(displayName: "Ava Chen", username: "ava",
                   transportMode: .transit, maxTravelMinutes: 35,
                   interests: ["Coffee", "Live music", "Vegetarian food"],
                   homeCoordinate: Coordinate(latitude: 37.7599, longitude: -122.4148),
                   homeAreaName: "Mission District"),
            Friend(displayName: "Leo Park", username: "leo",
                   transportMode: .driving, maxTravelMinutes: 25,
                   interests: ["Bars", "Sports", "Street food"],
                   homeCoordinate: Coordinate(latitude: 37.7431, longitude: -122.4860),
                   homeAreaName: "Outer Sunset"),
            Friend(displayName: "Maya Singh", username: "maya",
                   transportMode: .biking, maxTravelMinutes: 30,
                   interests: ["Outdoors", "Brunch", "Bookstores"],
                   homeCoordinate: Coordinate(latitude: 37.7793, longitude: -122.4193),
                   homeAreaName: "Hayes Valley"),
            Friend(displayName: "Sam Rivera", username: "sam",
                   status: .incomingRequest,
                   transportMode: .walking, maxTravelMinutes: 20,
                   interests: ["Rooftops", "Dancing"],
                   homeCoordinate: Coordinate(latitude: 37.7989, longitude: -122.4078),
                   homeAreaName: "North Beach"),
        ]
    }
}
