import Foundation

// MARK: - Workflow types

/// A meetup request waiting for the current user's answer.
struct MeetupInvite: Codable, Identifiable, Hashable {
    var id: UUID                 // session ID
    var organizerName: String
    var type: MeetupType
    var timeWindow: TimeWindow
    var createdAt: Date
}

enum MeetupSessionStatus: String, Codable {
    case collecting, ready, confirmed, cancelled
}

/// Aggregated state of a planning session, polled by the organizer while
/// responses come in. `participants` contains everyone who responded as
/// available with a usable location — exactly what the engine needs.
struct MeetupSessionState: Codable, Hashable {
    var id: UUID
    var status: MeetupSessionStatus
    var participants: [PlanningParticipant]
    var awaitingNames: [String]
    var declinedNames: [String]
}

/// Identifies a planning session being driven through the suggestions UI.
struct PlannerSession: Hashable, Identifiable {
    var id: UUID
    var request: MeetupRequest
}

/// A published option the group can vote on (server-assigned ID).
struct VotableSuggestion: Codable, Identifiable, Hashable {
    var id: UUID
    var rank: Int
    var venueName: String
    var areaName: String
    var category: String
    var coordinate: Coordinate
    var time: Date
    var explanation: String
    var fairnessScore: Double
    var interestScore: Double
    var budgetFitScore: Double
    var voterNames: [String]
    var myVote: Bool
}

/// A session waiting for the current user's vote.
struct VotePending: Codable, Identifiable, Hashable {
    var id: UUID            // session ID
    var organizerName: String
    var type: MeetupType
    var createdAt: Date
}

enum BackendError: LocalizedError {
    case notSignedIn
    case server(String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You're not signed in."
        case .server(let reason): return reason
        case .transport(let error): return error.localizedDescription
        }
    }
}

// MARK: - Backend contract

/// Everything Midway needs from a backend. `RemoteBackend` talks to the
/// Vapor server in Server/; `LocalDemoBackend` runs the same workflow
/// entirely on-device so the app works with zero setup.
protocol MidwayBackend {
    /// Restore a previous session, if any (token on disk / local snapshot).
    func restoreSession() async throws -> UserProfile?
    func signIn(as identity: AuthenticatedUser) async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws
    func signOut() async

    func friends() async throws -> [Friend]
    func sendFriendRequest(username: String) async throws
    func respondToFriendRequest(_ friend: Friend, accept: Bool) async throws

    /// Creates the session and registers the organizer's own response.
    /// Returns the session ID to poll.
    func createMeetup(_ request: MeetupRequest,
                      organizerResponse: ParticipantResponse) async throws -> UUID
    func pendingInvites() async throws -> [MeetupInvite]
    func respondToInvite(_ inviteID: UUID, response: ParticipantResponse) async throws
    func sessionState(_ id: UUID) async throws -> MeetupSessionState
    func confirmMeetup(sessionID: UUID, meetup: Meetup) async throws
    func meetups() async throws -> [Meetup]
    func deleteMeetup(_ id: UUID) async

    // Voting on published options
    func publishSuggestions(sessionID: UUID, _ suggestions: [MeetupSuggestion]) async throws
    func votableSuggestions(sessionID: UUID) async throws -> [VotableSuggestion]
    func castVote(sessionID: UUID, suggestionID: UUID) async throws
    func pendingVotes() async throws -> [VotePending]

    // Lifecycle & presence
    func cancelSession(_ id: UUID) async
    func sendOnMyWay(meetupID: UUID) async

    // Devices & safety
    func registerDeviceToken(_ token: String) async
    func blockUser(_ userID: UUID, report: Bool) async throws
    func deleteAccount() async throws
}
