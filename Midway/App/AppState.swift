import Foundation
import SwiftUI

/// Central observable state. Backed by local JSON persistence for the MVP;
/// the friend graph and meetup workflow are designed to move behind a
/// Midway backend without changing the views.
@MainActor
final class AppState: ObservableObject {
    // Identity & profile
    @Published var profile: UserProfile?
    @Published var hasCompletedOnboarding = false

    // Midway-owned friend graph (Snap Kit exposes no friends list).
    @Published var friends: [Friend] = []

    // Confirmed meetups.
    @Published var meetups: [Meetup] = []

    // Deep-link routing (App Intents, invite links).
    @Published var pendingPlannerRequest = false

    let auth: AuthService
    let locationService = LocationService()
    private let store = PersistenceStore()

    init() {
        if TestEnvironment.isUITest {
            store.reset()
            self.auth = MockAuthService()
        } else {
            // Use real Snapchat login when configured, otherwise the mock so
            // the app is fully runnable without Snap credentials.
            let snap = SnapchatAuthService()
            self.auth = snap.isAvailable ? snap : MockAuthService()
        }
        load()
    }

    // MARK: - Lifecycle

    func load() {
        let snapshot = store.load()
        profile = snapshot.profile
        friends = snapshot.friends
        meetups = snapshot.meetups
        hasCompletedOnboarding = snapshot.profile.map { !$0.firstName.isEmpty } ?? false
    }

    func save() {
        store.save(.init(profile: profile, friends: friends, meetups: meetups))
    }

    // MARK: - Auth

    func signIn() async throws {
        let user = try await auth.signIn()
        if profile == nil || profile?.auth.providerUserID != user.providerUserID {
            profile = UserProfile(auth: user, firstName: user.displayName)
            hasCompletedOnboarding = false
        } else {
            profile?.auth = user
        }
        save()
    }

    func signOut() {
        auth.signOut()
        profile = nil
        friends = []
        meetups = []
        hasCompletedOnboarding = false
        store.reset()
    }

    func completeOnboarding(with profile: UserProfile) {
        self.profile = profile
        hasCompletedOnboarding = true
        if friends.isEmpty {
            friends = DemoData.seedFriends()
        }
        save()
    }

    // MARK: - Friends

    var acceptedFriends: [Friend] {
        friends.filter { $0.status == .accepted }
    }

    var incomingRequests: [Friend] {
        friends.filter { $0.status == .incomingRequest }
    }

    func respondToFriendRequest(_ friend: Friend, accept: Bool) {
        guard let index = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        if accept {
            friends[index].status = .accepted
        } else {
            friends.remove(at: index)
        }
        save()
    }

    func addFriend(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !friends.contains(where: { $0.username.lowercased() == trimmed.lowercased() }) else { return }
        friends.append(Friend(displayName: trimmed.capitalized,
                              username: trimmed.lowercased(),
                              status: .outgoingRequest))
        save()
    }

    /// Invite link a friend can open to connect on Midway.
    var inviteURL: URL? {
        guard let username = profile?.username, !username.isEmpty else { return nil }
        return URL(string: "midway://invite?from=\(username)")
    }

    // MARK: - Meetups

    func confirm(suggestion: MeetupSuggestion, request: MeetupRequest, attendeeNames: [String]) -> Meetup {
        let meetup = Meetup(suggestion: suggestion, type: request.type, attendeeNames: attendeeNames)
        meetups.insert(meetup, at: 0)
        save()
        return meetup
    }

    func delete(meetup: Meetup) {
        meetups.removeAll { $0.id == meetup.id }
        save()
    }

    // MARK: - Planning helpers

    /// Builds the organizer's planning participant from their profile and
    /// the location consent they chose for this session.
    func organizerParticipant(sharing: LocationSharingLevel,
                              manualPlace: String) async throws -> PlanningParticipant {
        guard let profile else { throw SuggestionError.noParticipants }
        if TestEnvironment.isUITest {
            // Fixed organizer location (Hayes Valley, SF): no permission
            // dialogs or geocoding on CI.
            return PlanningParticipant(
                id: profile.id,
                name: profile.firstName.isEmpty ? "You" : profile.firstName,
                transportMode: profile.transportMode,
                maxTravelMinutes: profile.maxTravelMinutes,
                budget: profile.budget,
                interests: profile.interests,
                coordinate: Coordinate(latitude: 37.7790, longitude: -122.4170)
            )
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
        return PlanningParticipant(
            id: profile.id,
            name: profile.firstName.isEmpty ? "You" : profile.firstName,
            transportMode: profile.transportMode,
            maxTravelMinutes: profile.maxTravelMinutes,
            budget: profile.budget,
            interests: profile.interests,
            coordinate: coordinate
        )
    }

    /// MVP stand-in for the real availability/consent round-trip: until the
    /// backend exists, friends "respond" using their shared defaults and an
    /// approximate home location.
    func simulatedResponses(for request: MeetupRequest) -> [PlanningParticipant] {
        request.participantFriendIDs.compactMap { id in
            guard let friend = friends.first(where: { $0.id == id }),
                  let home = friend.homeCoordinate else { return nil }
            return PlanningParticipant(
                id: friend.id,
                name: friend.displayName.components(separatedBy: " ").first ?? friend.displayName,
                transportMode: friend.transportMode,
                maxTravelMinutes: friend.maxTravelMinutes,
                budget: .medium,
                interests: friend.interests,
                coordinate: home.approximate
            )
        }
    }
}
