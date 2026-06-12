import Foundation

/// On-device implementation of the backend contract: same workflow, no
/// server. Friends are seeded, invited friends "respond" after a short
/// delay using their shared defaults, and one incoming invite from Ava
/// demonstrates the responder side. Used when MIDWAY_API_URL is unset,
/// and (with instant timing) by UI tests.
actor LocalDemoBackend: MidwayBackend {
    private let store = PersistenceStore()
    private let instantResponses: Bool

    private var snapshot: PersistenceStore.Snapshot
    private var sessions: [UUID: DemoSession] = [:]

    private struct DemoSession {
        var request: MeetupRequest
        var organizer: PlanningParticipant
        var arrived: [PlanningParticipant] = []
        var pendingFriendIDs: [UUID]
        var options: [VotableSuggestion] = []
    }

    private static let demoInviteID = UUID(uuidString: "00000000-0000-0000-0000-00000000A0A0")!

    init(resetOnLaunch: Bool) {
        if resetOnLaunch {
            store.reset()
        }
        self.instantResponses = resetOnLaunch
        self.snapshot = store.load()
    }

    private func persist() {
        store.save(snapshot)
    }

    // MARK: - Session

    func restoreSession() async throws -> UserProfile? {
        snapshot.profile
    }

    func signIn(as identity: AuthenticatedUser) async throws -> UserProfile {
        if let existing = snapshot.profile,
           existing.auth.providerUserID == identity.providerUserID {
            return existing
        }
        let profile = UserProfile(auth: identity, firstName: identity.displayName)
        snapshot = .init(profile: profile)
        persist()
        return profile
    }

    func updateProfile(_ profile: UserProfile) async throws {
        snapshot.profile = profile
        if snapshot.friends.isEmpty {
            snapshot.friends = DemoData.seedFriends()
        }
        persist()
    }

    func signOut() async {
        snapshot = .init()
        sessions = [:]
        store.reset()
    }

    // MARK: - Friends

    func friends() async throws -> [Friend] {
        snapshot.friends
    }

    func sendFriendRequest(username: String) async throws {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty,
              !snapshot.friends.contains(where: { $0.username == trimmed }) else { return }
        snapshot.friends.append(Friend(displayName: trimmed.capitalized,
                                       username: trimmed,
                                       status: .outgoingRequest))
        persist()
    }

    func respondToFriendRequest(_ friend: Friend, accept: Bool) async throws {
        guard let index = snapshot.friends.firstIndex(where: { $0.id == friend.id }) else { return }
        if accept {
            snapshot.friends[index].status = .accepted
        } else {
            snapshot.friends.remove(at: index)
        }
        persist()
    }

    // MARK: - Meetups

    func createMeetup(_ request: MeetupRequest,
                      organizerResponse: ParticipantResponse) async throws -> UUID {
        guard let profile = snapshot.profile,
              let coordinate = organizerResponse.coordinate else {
            throw BackendError.notSignedIn
        }
        let organizer = PlanningParticipant(
            id: profile.id,
            name: profile.firstName.isEmpty ? "You" : profile.firstName,
            transportMode: profile.transportMode,
            maxTravelMinutes: profile.maxTravelMinutes,
            budget: profile.budget,
            interests: profile.interests,
            coordinate: coordinate
        )
        let sessionID = UUID()
        sessions[sessionID] = DemoSession(request: request,
                                          organizer: organizer,
                                          pendingFriendIDs: request.participantFriendIDs)

        // Friends "respond" with their shared defaults after a moment.
        let delay: Duration = instantResponses ? .zero : .seconds(1.5)
        Task {
            try? await Task.sleep(for: delay)
            await self.deliverDemoResponses(sessionID: sessionID)
        }
        return sessionID
    }

    private func deliverDemoResponses(sessionID: UUID) {
        guard var session = sessions[sessionID] else { return }
        for friendID in session.pendingFriendIDs {
            guard let friend = snapshot.friends.first(where: { $0.id == friendID }),
                  let home = friend.homeCoordinate else { continue }
            session.arrived.append(PlanningParticipant(
                id: friend.id,
                name: friend.displayName.components(separatedBy: " ").first ?? friend.displayName,
                transportMode: friend.transportMode,
                maxTravelMinutes: friend.maxTravelMinutes,
                budget: .medium,
                interests: friend.interests,
                coordinate: home.approximate
            ))
        }
        session.pendingFriendIDs = []
        sessions[sessionID] = session
    }

    func pendingInvites() async throws -> [MeetupInvite] {
        guard snapshot.profile != nil,
              !snapshot.friends.isEmpty,
              snapshot.demoInviteResolved != true else { return [] }
        return [MeetupInvite(id: Self.demoInviteID,
                             organizerName: "Ava Chen",
                             type: .coffee,
                             timeWindow: TimeWindow(kind: .tonight),
                             createdAt: Date())]
    }

    func respondToInvite(_ inviteID: UUID, response: ParticipantResponse) async throws {
        guard inviteID == Self.demoInviteID else { return }
        snapshot.demoInviteResolved = true
        if response.isAvailable {
            // Ava "confirms" her plan, so the responder sees the full loop.
            let attendees = ["Ava Chen", snapshot.profile?.firstName ?? "You"]
            snapshot.meetups.insert(Meetup(
                title: "Coffee at Ritual Coffee Roasters",
                venueName: "Ritual Coffee Roasters",
                areaName: "Hayes Valley",
                coordinate: Coordinate(latitude: 37.7764, longitude: -122.4242),
                time: TimeWindow(kind: .tonight).suggestedTime(),
                attendeeNames: attendees,
                explanation: "Nearly equal travel for both of you, and it matches the group's interest in coffee."
            ), at: 0)
        }
        persist()
    }

    func sessionState(_ id: UUID) async throws -> MeetupSessionState {
        guard let session = sessions[id] else {
            throw BackendError.server("Unknown planning session.")
        }
        let awaiting = session.pendingFriendIDs.compactMap { friendID in
            snapshot.friends.first(where: { $0.id == friendID })?.displayName
        }
        return MeetupSessionState(
            id: id,
            status: awaiting.isEmpty ? .ready : .collecting,
            participants: [session.organizer] + session.arrived,
            awaitingNames: awaiting,
            declinedNames: []
        )
    }

    func confirmMeetup(sessionID: UUID, meetup: Meetup) async throws {
        snapshot.meetups.insert(meetup, at: 0)
        sessions[sessionID] = nil
        persist()
    }

    func meetups() async throws -> [Meetup] {
        snapshot.meetups
    }

    func deleteMeetup(_ id: UUID) async {
        snapshot.meetups.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Voting (demo: friends vote for the top picks after a beat)

    func publishSuggestions(sessionID: UUID, _ suggestions: [MeetupSuggestion]) async throws {
        guard var session = sessions[sessionID] else { return }
        session.options = suggestions.enumerated().map { index, s in
            VotableSuggestion(id: UUID(), rank: index + 1,
                              venueName: s.venueName, areaName: s.areaName,
                              category: s.category, coordinate: s.coordinate,
                              time: s.suggestedTime, explanation: s.explanation,
                              fairnessScore: s.fairnessScore,
                              interestScore: s.interestScore,
                              budgetFitScore: s.budgetFitScore,
                              voterNames: [], myVote: false)
        }
        sessions[sessionID] = session

        let delay: Duration = instantResponses ? .milliseconds(300) : .seconds(2)
        Task {
            try? await Task.sleep(for: delay)
            await self.deliverDemoVotes(sessionID: sessionID)
        }
    }

    private func deliverDemoVotes(sessionID: UUID) {
        guard var session = sessions[sessionID], !session.options.isEmpty else { return }
        let voters = session.arrived.map(\.name)
        for (index, voter) in voters.enumerated() {
            // Most friends back the top pick; someone always likes #2.
            let choice = (index == voters.count - 1 && session.options.count > 1) ? 1 : 0
            session.options[choice].voterNames.append(voter)
        }
        sessions[sessionID] = session
    }

    func votableSuggestions(sessionID: UUID) async throws -> [VotableSuggestion] {
        sessions[sessionID]?.options ?? []
    }

    func castVote(sessionID: UUID, suggestionID: UUID) async throws {
        guard var session = sessions[sessionID],
              let index = session.options.firstIndex(where: { $0.id == suggestionID }) else { return }
        for i in session.options.indices {
            session.options[i].voterNames.removeAll { $0 == "You" }
            session.options[i].myVote = false
        }
        session.options[index].voterNames.append("You")
        session.options[index].myVote = true
        sessions[sessionID] = session
    }

    func pendingVotes() async throws -> [VotePending] {
        []
    }

    // MARK: - Lifecycle & presence

    func cancelSession(_ id: UUID) async {
        sessions[id] = nil
    }

    func sendOnMyWay(meetupID: UUID) async {
        // Push-only feature; nothing to do on-device in demo mode.
    }

    // MARK: - Devices & safety

    func registerDeviceToken(_ token: String) async {}

    func blockUser(_ userID: UUID, report: Bool) async throws {
        snapshot.friends.removeAll { $0.id == userID }
        persist()
    }

    func deleteAccount() async throws {
        await signOut()
    }
}
