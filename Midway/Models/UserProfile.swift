import Foundation

/// Identity returned by an auth provider (Snapchat Login Kit or a mock).
struct AuthenticatedUser: Codable, Hashable {
    /// Stable provider-scoped user ID (Snap's external ID where available).
    var providerUserID: String
    var provider: AuthProvider
    var displayName: String
    /// Bitmoji or other avatar URL, if the provider exposes one.
    var avatarURL: URL?
}

enum AuthProvider: String, Codable {
    case snapchat
    case apple
    case mock
}

/// The Midway-owned profile. Snapchat is identity flavor only —
/// preferences, interests, and the friend graph all live here.
struct UserProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var auth: AuthenticatedUser
    var firstName: String
    var username: String
    /// Human-readable default neighborhood, e.g. "Mission District".
    var homeAreaName: String
    var homeCoordinate: Coordinate?
    var transportMode: TransportMode
    var maxTravelMinutes: Int
    var favoriteMeetupTypes: Set<MeetupType>
    var budget: BudgetRange
    var interests: [String]
    var defaultLocationSharing: LocationSharingLevel

    init(id: UUID = UUID(),
         auth: AuthenticatedUser,
         firstName: String = "",
         username: String = "",
         homeAreaName: String = "",
         homeCoordinate: Coordinate? = nil,
         transportMode: TransportMode = .transit,
         maxTravelMinutes: Int = 30,
         favoriteMeetupTypes: Set<MeetupType> = [.coffee, .drinks],
         budget: BudgetRange = .medium,
         interests: [String] = [],
         defaultLocationSharing: LocationSharingLevel = .approximate) {
        self.id = id
        self.auth = auth
        self.firstName = firstName
        self.username = username
        self.homeAreaName = homeAreaName
        self.homeCoordinate = homeCoordinate
        self.transportMode = transportMode
        self.maxTravelMinutes = maxTravelMinutes
        self.favoriteMeetupTypes = favoriteMeetupTypes
        self.budget = budget
        self.interests = interests
        self.defaultLocationSharing = defaultLocationSharing
    }
}
