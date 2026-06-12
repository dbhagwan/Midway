import Foundation

enum FriendStatus: String, Codable {
    case incomingRequest
    case outgoingRequest
    case accepted
}

/// A Midway connection. Snap Kit does not expose the Snapchat friends list,
/// so Midway owns its own friend graph and only shows people who are on Midway.
struct Friend: Codable, Identifiable, Hashable {
    var id: UUID
    var displayName: String
    var username: String
    var avatarURL: URL?
    var status: FriendStatus
    /// Default travel preferences a friend has shared with their connections.
    var transportMode: TransportMode
    var maxTravelMinutes: Int
    var interests: [String]
    /// Rough home coordinate, only present if the friend opted in.
    var homeCoordinate: Coordinate?
    var homeAreaName: String
    /// Server-side friend-request ID, set in remote mode.
    var edgeID: UUID?

    init(id: UUID = UUID(),
         displayName: String,
         username: String,
         avatarURL: URL? = nil,
         status: FriendStatus = .accepted,
         transportMode: TransportMode = .transit,
         maxTravelMinutes: Int = 30,
         interests: [String] = [],
         homeCoordinate: Coordinate? = nil,
         homeAreaName: String = "",
         edgeID: UUID? = nil) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.avatarURL = avatarURL
        self.status = status
        self.transportMode = transportMode
        self.maxTravelMinutes = maxTravelMinutes
        self.interests = interests
        self.homeCoordinate = homeCoordinate
        self.homeAreaName = homeAreaName
        self.edgeID = edgeID
    }
}
