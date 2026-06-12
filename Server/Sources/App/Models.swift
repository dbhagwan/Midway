import Fluent
import Vapor

// MARK: - Users & tokens

final class User: Model, Authenticatable, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @Field(key: "provider") var provider: String
    @Field(key: "provider_user_id") var providerUserID: String
    @Field(key: "display_name") var displayName: String
    @Field(key: "username") var username: String
    @OptionalField(key: "avatar_url") var avatarURL: String?
    @Field(key: "home_area") var homeAreaName: String
    @Field(key: "transport") var transportMode: String
    @Field(key: "max_travel_minutes") var maxTravelMinutes: Int
    @Field(key: "budget") var budget: Int
    @Field(key: "interests") var interests: [String]
    @Field(key: "default_sharing") var defaultSharing: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
}

final class UserToken: Model, @unchecked Sendable {
    static let schema = "user_tokens"

    @ID(key: .id) var id: UUID?
    @Field(key: "value") var value: String
    @Parent(key: "user_id") var user: User

    init() {}

    init(value: String, userID: UUID) {
        self.value = value
        self.$user.id = userID
    }
}

// MARK: - Friend graph (Midway-owned; Snap exposes no friends list)

enum FriendEdgeStatus: String, Codable {
    case pending, accepted
}

final class FriendEdge: Model, @unchecked Sendable {
    static let schema = "friend_edges"

    @ID(key: .id) var id: UUID?
    @Parent(key: "requester_id") var requester: User
    @Parent(key: "recipient_id") var recipient: User
    @Field(key: "status") var status: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(requesterID: UUID, recipientID: UUID) {
        self.$requester.id = requesterID
        self.$recipient.id = recipientID
        self.status = FriendEdgeStatus.pending.rawValue
    }
}

// MARK: - Meetup workflow

enum SessionStatus: String, Codable {
    case collecting   // waiting for participant responses
    case ready        // everyone responded; organizer can rank & confirm
    case confirmed
    case cancelled
}

final class MeetupSession: Model, @unchecked Sendable {
    static let schema = "meetup_sessions"

    @ID(key: .id) var id: UUID?
    @Parent(key: "organizer_id") var organizer: User
    @Field(key: "type") var type: String
    @Field(key: "window_kind") var windowKind: String
    @OptionalField(key: "custom_start") var customStart: Date?
    @OptionalField(key: "max_budget") var maxBudget: Int?
    @Field(key: "indoor_outdoor") var indoorOutdoor: String
    @Field(key: "dietary") var dietary: [String]
    @Field(key: "vibe") var vibe: String
    @OptionalField(key: "max_travel_minutes") var maxTravelMinutes: Int?
    @Field(key: "status") var status: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
}

/// One row per person in a session. Location is stored only at the precision
/// the participant chose, and is erased once the meetup is confirmed.
final class SessionParticipant: Model, @unchecked Sendable {
    static let schema = "session_participants"

    @ID(key: .id) var id: UUID?
    @Parent(key: "session_id") var session: MeetupSession
    @Parent(key: "user_id") var user: User
    @OptionalField(key: "is_available") var isAvailable: Bool?
    @OptionalField(key: "sharing") var sharing: String?
    @OptionalField(key: "lat") var lat: Double?
    @OptionalField(key: "lon") var lon: Double?
    @OptionalField(key: "manual_place") var manualPlaceName: String?
    @OptionalField(key: "responded_at") var respondedAt: Date?

    init() {}

    init(sessionID: UUID, userID: UUID) {
        self.$session.id = sessionID
        self.$user.id = userID
    }

    var hasResponded: Bool { respondedAt != nil }
}

final class ConfirmedMeetup: Model, @unchecked Sendable {
    static let schema = "confirmed_meetups"

    @ID(key: .id) var id: UUID?
    @Field(key: "session_id") var sessionID: UUID
    @Field(key: "title") var title: String
    @Field(key: "venue_name") var venueName: String
    @Field(key: "area_name") var areaName: String
    @Field(key: "lat") var lat: Double
    @Field(key: "lon") var lon: Double
    @Field(key: "time") var time: Date
    @Field(key: "explanation") var explanation: String
    @Field(key: "attendee_names") var attendeeNames: [String]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
}
