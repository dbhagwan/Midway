import Vapor

// MARK: - Auth

struct LoginRequest: Content {
    var provider: String
    var providerUserID: String
    var displayName: String
    var avatarURL: String?
    var username: String?
    /// Apple identity token (JWT) or Snap access token; verified
    /// server-side before the identity is trusted.
    var credential: String?
}

struct LoginResponse: Content {
    var token: String
    var user: UserDTO
}

// MARK: - Users

/// Full profile, returned only for the authenticated user themself.
struct UserDTO: Content {
    var id: UUID
    var displayName: String
    var username: String
    var avatarURL: String?
    var homeAreaName: String
    var transportMode: String
    var maxTravelMinutes: Int
    var budget: Int
    var interests: [String]
    var defaultSharing: String

    init(_ user: User) throws {
        self.id = try user.requireID()
        self.displayName = user.displayName
        self.username = user.username
        self.avatarURL = user.avatarURL
        self.homeAreaName = user.homeAreaName
        self.transportMode = user.transportMode
        self.maxTravelMinutes = user.maxTravelMinutes
        self.budget = user.budget
        self.interests = user.interests
        self.defaultSharing = user.defaultSharing
    }
}

/// What other Midway users can see: identity plus the travel preferences
/// the ranking engine needs. Never includes location or provider details.
struct PublicUserDTO: Content {
    var id: UUID
    var displayName: String
    var username: String
    var avatarURL: String?
    var homeAreaName: String
    var transportMode: String
    var maxTravelMinutes: Int
    var budget: Int
    var interests: [String]

    init(_ user: User) throws {
        self.id = try user.requireID()
        self.displayName = user.displayName
        self.username = user.username
        self.avatarURL = user.avatarURL
        self.homeAreaName = user.homeAreaName
        self.transportMode = user.transportMode
        self.maxTravelMinutes = user.maxTravelMinutes
        self.budget = user.budget
        self.interests = user.interests
    }
}

struct ProfileUpdateRequest: Content {
    var displayName: String?
    var username: String?
    var homeAreaName: String?
    var transportMode: String?
    var maxTravelMinutes: Int?
    var budget: Int?
    var interests: [String]?
    var defaultSharing: String?
}

// MARK: - Friends

struct FriendDTO: Content {
    var edgeID: UUID
    var user: PublicUserDTO
    /// "accepted", "incoming", or "outgoing" from the caller's perspective.
    var status: String
}

struct FriendListResponse: Content {
    var friends: [FriendDTO]
}

struct FriendRequestBody: Content {
    var username: String
}

struct FriendRespondBody: Content {
    var accept: Bool
}

// MARK: - Meetups

struct ParticipantResponseBody: Content {
    var isAvailable: Bool
    var sharing: String
    var lat: Double?
    var lon: Double?
    var manualPlaceName: String?
}

struct CreateMeetupBody: Content {
    var participantUserIDs: [UUID]
    var type: String
    var windowKind: String
    var customStart: Date?
    var maxBudget: Int?
    var indoorOutdoor: String
    var dietary: [String]
    var vibe: String
    var maxTravelMinutes: Int?
    /// The organizer responds at creation time with their own consented location.
    var organizerResponse: ParticipantResponseBody
}

struct ParticipantDTO: Content {
    var user: PublicUserDTO
    var hasResponded: Bool
    var isAvailable: Bool?
    var sharing: String?
    var lat: Double?
    var lon: Double?
    var manualPlaceName: String?
}

struct SessionDTO: Content {
    var id: UUID
    var organizer: PublicUserDTO
    var status: String
    var type: String
    var windowKind: String
    var customStart: Date?
    var maxBudget: Int?
    var indoorOutdoor: String
    var dietary: [String]
    var vibe: String
    var maxTravelMinutes: Int?
    var createdAt: Date?
    var participants: [ParticipantDTO]
}

struct InviteDTO: Content {
    var sessionID: UUID
    var organizerName: String
    var type: String
    var windowKind: String
    var customStart: Date?
    var createdAt: Date?
}

struct DeviceBody: Content {
    var token: String
}

struct BlockBody: Content {
    var report: Bool
    var reason: String?
}

// MARK: - Voting

struct SuggestionUpload: Content {
    var rank: Int
    var venueName: String
    var areaName: String
    var category: String
    var lat: Double
    var lon: Double
    var time: Date
    var explanation: String
    var fairness: Double
    var interest: Double
    var budgetFit: Double
}

struct SuggestionOptionDTO: Content {
    var id: UUID
    var rank: Int
    var venueName: String
    var areaName: String
    var category: String
    var lat: Double
    var lon: Double
    var time: Date
    var explanation: String
    var fairness: Double
    var interest: Double
    var budgetFit: Double
    var voterNames: [String]
    var myVote: Bool
}

struct VoteBody: Content {
    var suggestionID: UUID
}

struct VotePendingDTO: Content {
    var sessionID: UUID
    var organizerName: String
    var type: String
    var createdAt: Date?
}

struct ConfirmMeetupBody: Content {
    var title: String
    var venueName: String
    var areaName: String
    var lat: Double
    var lon: Double
    var time: Date
    var explanation: String
}

struct MeetupDTO: Content {
    var id: UUID
    var sessionID: UUID
    var title: String
    var venueName: String
    var areaName: String
    var lat: Double
    var lon: Double
    var time: Date
    var explanation: String
    var attendeeNames: [String]
    var createdAt: Date?

    init(_ meetup: ConfirmedMeetup) throws {
        self.id = try meetup.requireID()
        self.sessionID = meetup.sessionID
        self.title = meetup.title
        self.venueName = meetup.venueName
        self.areaName = meetup.areaName
        self.lat = meetup.lat
        self.lon = meetup.lon
        self.time = meetup.time
        self.explanation = meetup.explanation
        self.attendeeNames = meetup.attendeeNames
        self.createdAt = meetup.createdAt
    }
}
