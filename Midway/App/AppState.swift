import Foundation
import SwiftUI

/// Central observable state. All data flows through a `MidwayBackend`:
/// the Vapor server when MIDWAY_API_URL is configured, otherwise the
/// on-device demo backend — the views never know the difference.
@MainActor
final class AppState: ObservableObject {
    @Published var profile: UserProfile?
    @Published var friends: [Friend] = []
    @Published var meetups: [Meetup] = []
    @Published var invites: [MeetupInvite] = []
    @Published var hasCompletedOnboarding = false
    @Published var isRestoring = true

    // Deep-link routing (App Intents, invite links).
    @Published var pendingPlannerRequest = false

    let auth: AuthService
    let backend: MidwayBackend
    let locationService = LocationService()

    init() {
        if TestEnvironment.isUITest {
            auth = MockAuthService()
            backend = LocalDemoBackend(resetOnLaunch: true)
        } else {
            // Real Snapchat login when configured, mock otherwise.
            let snap = SnapchatAuthService()
            auth = snap.isAvailable ? snap : MockAuthService()
            if let url = RemoteBackend.configuredURL {
                backend = RemoteBackend(baseURL: url)
            } else {
                backend = LocalDemoBackend(resetOnLaunch: false)
            }
        }
        Task { await restore() }
    }

    // MARK: - Session lifecycle

    private func onboardingKey(for profile: UserProfile) -> String {
        "midway.onboarded.\(profile.auth.providerUserID)"
    }

    private func restore() async {
        defer { isRestoring = false }
        guard let restored = try? await backend.restoreSession() else { return }
        profile = restored
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey(for: restored))
        await refresh()
    }

    func signIn() async throws {
        let identity = try await auth.signIn()
        let profile = try await backend.signIn(as: identity)
        self.profile = profile
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey(for: profile))
        await refresh()
    }

    func signOut() {
        if let profile {
            UserDefaults.standard.removeObject(forKey: onboardingKey(for: profile))
        }
        Task { await backend.signOut() }
        auth.signOut()
        profile = nil
        friends = []
        meetups = []
        invites = []
        hasCompletedOnboarding = false
    }

    func completeOnboarding(with profile: UserProfile) {
        self.profile = profile
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey(for: profile))
        Task {
            try? await backend.updateProfile(profile)
            await refresh()
        }
    }

    /// Push profile edits (Profile tab bindings) to the backend.
    func saveProfile() {
        guard let profile else { return }
        Task { try? await backend.updateProfile(profile) }
    }

    /// Re-pull friends, meetups, and pending invites.
    func refresh() async {
        guard profile != nil else { return }
        if let updated = try? await backend.friends() { friends = updated }
        if let updated = try? await backend.meetups() { meetups = updated }
        if let updated = try? await backend.pendingInvites() { invites = updated }
    }

    // MARK: - Friends

    var acceptedFriends: [Friend] {
        friends.filter { $0.status == .accepted }
    }

    var incomingRequests: [Friend] {
        friends.filter { $0.status == .incomingRequest }
    }

    func respondToFriendRequest(_ friend: Friend, accept: Bool) {
        Task {
            try? await backend.respondToFriendRequest(friend, accept: accept)
            await refresh()
        }
    }

    func addFriend(username: String) {
        Task {
            try? await backend.sendFriendRequest(username: username)
            await refresh()
        }
    }

    /// Invite link a friend can open to connect on Midway.
    var inviteURL: URL? {
        guard let username = profile?.username, !username.isEmpty else { return nil }
        return URL(string: "midway://invite?from=\(username)")
    }

    // MARK: - Meetup workflow

    /// Builds this user's response with the location consent they chose
    /// for this session only. Used by both the planner (organizer) and the
    /// invite responder.
    func myResponse(sharing: LocationSharingLevel,
                    manualPlace: String,
                    isAvailable: Bool = true) async throws -> ParticipantResponse {
        guard let profile else { throw BackendError.notSignedIn }
        if !isAvailable {
            return ParticipantResponse(participantID: profile.id,
                                       isAvailable: false,
                                       sharingLevel: .none)
        }
        if TestEnvironment.isUITest {
            // Fixed location (Hayes Valley, SF): no permission dialogs on CI.
            return ParticipantResponse(participantID: profile.id,
                                       isAvailable: true,
                                       sharingLevel: sharing,
                                       coordinate: Coordinate(latitude: 37.7790, longitude: -122.4170))
        }
        let coordinate: Coordinate
        switch sharing {
        case .exact, .approximate:
            coordinate = try await locationService.currentCoordinate(sharing: sharing)
        case .manual:
            coordinate = try await locationService.coordinate(forPlaceNamed: manualPlace)
        case .none:
            guard let home = profile.homeCoordinate else {
                throw LocationService.LocationError.unavailable
            }
            coordinate = home.approximate
        }
        return ParticipantResponse(participantID: profile.id,
                                   isAvailable: true,
                                   sharingLevel: sharing,
                                   coordinate: coordinate,
                                   manualPlaceName: sharing == .manual ? manualPlace : nil)
    }

    func startMeetup(_ request: MeetupRequest,
                     organizerResponse: ParticipantResponse) async throws -> PlannerSession {
        let sessionID = try await backend.createMeetup(request, organizerResponse: organizerResponse)
        return PlannerSession(id: sessionID, request: request)
    }

    func respondToInvite(_ invite: MeetupInvite, response: ParticipantResponse) async throws {
        try await backend.respondToInvite(invite.id, response: response)
        await refresh()
    }

    func confirm(suggestion: MeetupSuggestion,
                 session: PlannerSession,
                 attendeeNames: [String]) async throws -> Meetup {
        let meetup = Meetup(suggestion: suggestion,
                            type: session.request.type,
                            attendeeNames: attendeeNames)
        try await backend.confirmMeetup(sessionID: session.id, meetup: meetup)
        await refresh()
        return meetup
    }

    func delete(meetup: Meetup) {
        meetups.removeAll { $0.id == meetup.id }
        Task { await backend.deleteMeetup(meetup.id) }
    }
}
