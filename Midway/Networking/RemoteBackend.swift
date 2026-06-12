import Foundation

/// URLSession client for the Midway Vapor server (Server/ in this repo).
/// Activated when `MIDWAY_API_URL` is set in Info.plist.
final class RemoteBackend: MidwayBackend {
    private let baseURL: URL
    private let session = URLSession.shared
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let tokenKey = "midway.apiToken"
    private static let identityKey = "midway.identity"

    static var configuredURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MIDWAY_API_URL") as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private var token: String? {
        get { KeychainStore.string(for: Self.tokenKey) }
        set { KeychainStore.set(newValue, for: Self.tokenKey) }
    }

    private var storedIdentity: AuthenticatedUser? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.identityKey) else { return nil }
            return try? JSONDecoder().decode(AuthenticatedUser.self, from: data)
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) },
                                      forKey: Self.identityKey)
        }
    }

    // MARK: - Session

    func restoreSession() async throws -> UserProfile? {
        guard token != nil, let identity = storedIdentity else { return nil }
        let user: UserDTO = try await get("v1/me")
        return user.profile(auth: identity)
    }

    func signIn(as identity: AuthenticatedUser) async throws -> UserProfile {
        struct Body: Encodable {
            var provider: String
            var providerUserID: String
            var displayName: String
            var avatarURL: String?
        }
        struct Response: Decodable {
            var token: String
            var user: UserDTO
        }
        let response: Response = try await post("v1/auth/login", body: Body(
            provider: identity.provider.rawValue,
            providerUserID: identity.providerUserID,
            displayName: identity.displayName,
            avatarURL: identity.avatarURL?.absoluteString
        ), authorized: false)
        token = response.token
        storedIdentity = identity
        return response.user.profile(auth: identity)
    }

    func updateProfile(_ profile: UserProfile) async throws {
        struct Body: Encodable {
            var displayName: String
            var username: String
            var homeAreaName: String
            var transportMode: String
            var maxTravelMinutes: Int
            var budget: Int
            var interests: [String]
            var defaultSharing: String
        }
        let _: UserDTO = try await send("PUT", "v1/me", body: Body(
            displayName: profile.firstName,
            username: profile.username,
            homeAreaName: profile.homeAreaName,
            transportMode: profile.transportMode.rawValue,
            maxTravelMinutes: profile.maxTravelMinutes,
            budget: profile.budget.rawValue,
            interests: profile.interests,
            defaultSharing: profile.defaultLocationSharing.rawValue
        ))
    }

    func signOut() async {
        token = nil
        storedIdentity = nil
    }

    // MARK: - Friends

    func friends() async throws -> [Friend] {
        struct Response: Decodable { var friends: [FriendDTO] }
        let response: Response = try await get("v1/friends")
        return response.friends.map { $0.friend }
    }

    func sendFriendRequest(username: String) async throws {
        struct Body: Encodable { var username: String }
        let _: FriendDTO = try await post("v1/friends/requests", body: Body(username: username))
    }

    func respondToFriendRequest(_ friend: Friend, accept: Bool) async throws {
        guard let edgeID = friend.edgeID else { throw BackendError.server("Missing request ID.") }
        struct Body: Encodable { var accept: Bool }
        try await postNoReply("v1/friends/requests/\(edgeID)", body: Body(accept: accept))
    }

    // MARK: - Meetups

    func createMeetup(_ request: MeetupRequest,
                      organizerResponse: ParticipantResponse) async throws -> UUID {
        struct Body: Encodable {
            var participantUserIDs: [UUID]
            var type: String
            var windowKind: String
            var customStart: Date?
            var maxBudget: Int?
            var indoorOutdoor: String
            var dietary: [String]
            var vibe: String
            var maxTravelMinutes: Int?
            var organizerResponse: ResponseBody
        }
        let session: SessionDTO = try await post("v1/meetups", body: Body(
            participantUserIDs: request.participantFriendIDs,
            type: request.type.rawValue,
            windowKind: request.timeWindow.kind.rawValue,
            customStart: request.timeWindow.customStart,
            maxBudget: request.constraints.maxBudget?.rawValue,
            indoorOutdoor: request.constraints.indoorOutdoor.rawValue,
            dietary: request.constraints.dietaryNeeds,
            vibe: request.constraints.vibe,
            maxTravelMinutes: request.constraints.maxTravelMinutes,
            organizerResponse: ResponseBody(organizerResponse)
        ))
        return session.id
    }

    func pendingInvites() async throws -> [MeetupInvite] {
        let invites: [InviteDTO] = try await get("v1/meetups/invites")
        return invites.map { $0.invite }
    }

    func respondToInvite(_ inviteID: UUID, response: ParticipantResponse) async throws {
        try await postNoReply("v1/meetups/\(inviteID)/respond", body: ResponseBody(response))
    }

    func sessionState(_ id: UUID) async throws -> MeetupSessionState {
        let dto: SessionDTO = try await get("v1/meetups/\(id)")
        return dto.state
    }

    func confirmMeetup(sessionID: UUID, meetup: Meetup) async throws {
        struct Body: Encodable {
            var title: String
            var venueName: String
            var areaName: String
            var lat: Double
            var lon: Double
            var time: Date
            var explanation: String
        }
        let _: MeetupDTO = try await post("v1/meetups/\(sessionID)/confirm", body: Body(
            title: meetup.title, venueName: meetup.venueName, areaName: meetup.areaName,
            lat: meetup.coordinate.latitude, lon: meetup.coordinate.longitude,
            time: meetup.time, explanation: meetup.explanation
        ))
    }

    func meetups() async throws -> [Meetup] {
        let dtos: [MeetupDTO] = try await get("v1/meetups/confirmed")
        return dtos.map { $0.meetup }
    }

    func deleteMeetup(_ id: UUID) async {
        let _: EmptyReply? = try? await send("DELETE", "v1/meetups/confirmed/\(id)",
                                             body: Optional<Int>.none)
    }

    // MARK: - Voting

    func publishSuggestions(sessionID: UUID, _ suggestions: [MeetupSuggestion]) async throws {
        let uploads = suggestions.enumerated().map { index, s in
            SuggestionUploadDTO(
                rank: index + 1, venueName: s.venueName, areaName: s.areaName,
                category: s.category, lat: s.coordinate.latitude, lon: s.coordinate.longitude,
                time: s.suggestedTime, explanation: s.explanation,
                fairness: s.fairnessScore, interest: s.interestScore,
                budgetFit: s.budgetFitScore)
        }
        try await postNoReply("v1/meetups/\(sessionID)/suggestions", body: uploads)
    }

    func votableSuggestions(sessionID: UUID) async throws -> [VotableSuggestion] {
        let dtos: [SuggestionOptionDTO] = try await get("v1/meetups/\(sessionID)/suggestions")
        return dtos.map { $0.votable }
    }

    func castVote(sessionID: UUID, suggestionID: UUID) async throws {
        struct Body: Encodable { var suggestionID: UUID }
        try await postNoReply("v1/meetups/\(sessionID)/vote",
                              body: Body(suggestionID: suggestionID))
    }

    func pendingVotes() async throws -> [VotePending] {
        struct DTO: Decodable {
            var sessionID: UUID
            var organizerName: String
            var type: String
            var createdAt: Date?
        }
        let dtos: [DTO] = try await get("v1/meetups/votes/pending")
        return dtos.map {
            VotePending(id: $0.sessionID, organizerName: $0.organizerName,
                        type: MeetupType(rawValue: $0.type) ?? .coffee,
                        createdAt: $0.createdAt ?? Date())
        }
    }

    // MARK: - Lifecycle & presence

    func cancelSession(_ id: UUID) async {
        struct Empty: Encodable {}
        try? await postNoReply("v1/meetups/\(id)/cancel", body: Empty())
    }

    func sendOnMyWay(meetupID: UUID) async {
        struct Empty: Encodable {}
        try? await postNoReply("v1/meetups/confirmed/\(meetupID)/onmyway", body: Empty())
    }

    // MARK: - Devices & safety

    func registerDeviceToken(_ token: String) async {
        struct Body: Encodable { var token: String }
        try? await postNoReply("v1/devices", body: Body(token: token))
    }

    func blockUser(_ userID: UUID, report: Bool) async throws {
        struct Body: Encodable { var report: Bool }
        try await postNoReply("v1/users/\(userID)/block", body: Body(report: report))
    }

    func deleteAccount() async throws {
        let _: EmptyReply = try await send("DELETE", "v1/me", body: Optional<Int>.none)
        await signOut()
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: Optional<Int>.none)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B,
                                                  authorized: Bool = true) async throws -> T {
        try await send("POST", path, body: body, authorized: authorized)
    }

    private func postNoReply<B: Encodable>(_ path: String, body: B) async throws {
        // Vapor returns a bare status with an empty body for these endpoints.
        let _: EmptyReply = try await send("POST", path, body: body)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String,
                                                  body: B?,
                                                  authorized: Bool = true) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            guard let token else { throw BackendError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reason = (try? decoder.decode(VaporErrorBody.self, from: data))?.reason
            throw BackendError.server(reason ?? "Server error (\(status)).")
        }
        if T.self == EmptyReply.self, data.isEmpty {
            return EmptyReply() as! T
        }
        return try decoder.decode(T.self, from: data)
    }

    struct EmptyReply: Decodable {}

    // Types can't be declared inside generic functions, so the error
    // envelope lives at type scope.
    private struct VaporErrorBody: Decodable { var reason: String? }
}

// MARK: - Wire DTOs (mirror Server/Sources/App/DTOs.swift)

private struct UserDTO: Decodable {
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

    func profile(auth: AuthenticatedUser) -> UserProfile {
        UserProfile(
            id: id,
            auth: auth,
            firstName: displayName,
            username: username,
            homeAreaName: homeAreaName,
            transportMode: TransportMode(rawValue: transportMode) ?? .transit,
            maxTravelMinutes: maxTravelMinutes,
            budget: BudgetRange(rawValue: budget) ?? .medium,
            interests: interests,
            defaultLocationSharing: LocationSharingLevel(rawValue: defaultSharing) ?? .approximate
        )
    }
}

private struct PublicUserDTO: Decodable {
    var id: UUID
    var displayName: String
    var username: String
    var avatarURL: String?
    var homeAreaName: String
    var transportMode: String
    var maxTravelMinutes: Int
    var budget: Int
    var interests: [String]
}

private struct FriendDTO: Decodable {
    var edgeID: UUID
    var user: PublicUserDTO
    var status: String

    var friend: Friend {
        let friendStatus: FriendStatus
        switch status {
        case "incoming": friendStatus = .incomingRequest
        case "outgoing": friendStatus = .outgoingRequest
        default: friendStatus = .accepted
        }
        return Friend(
            id: user.id,
            displayName: user.displayName,
            username: user.username,
            avatarURL: user.avatarURL.flatMap(URL.init(string:)),
            status: friendStatus,
            transportMode: TransportMode(rawValue: user.transportMode) ?? .transit,
            maxTravelMinutes: user.maxTravelMinutes,
            interests: user.interests,
            homeCoordinate: nil,
            homeAreaName: user.homeAreaName,
            edgeID: edgeID
        )
    }
}

private struct ResponseBody: Encodable {
    var isAvailable: Bool
    var sharing: String
    var lat: Double?
    var lon: Double?
    var manualPlaceName: String?

    init(_ response: ParticipantResponse) {
        isAvailable = response.isAvailable
        sharing = response.sharingLevel.rawValue
        lat = response.coordinate?.latitude
        lon = response.coordinate?.longitude
        manualPlaceName = response.manualPlaceName
    }
}

private struct ParticipantDTO: Decodable {
    var user: PublicUserDTO
    var hasResponded: Bool
    var isAvailable: Bool?
    var lat: Double?
    var lon: Double?
}

private struct SessionDTO: Decodable {
    var id: UUID
    var organizer: PublicUserDTO
    var status: String
    var type: String
    var windowKind: String
    var customStart: Date?
    var participants: [ParticipantDTO]

    var state: MeetupSessionState {
        var planning: [PlanningParticipant] = []
        var awaiting: [String] = []
        var declined: [String] = []
        for p in participants {
            if !p.hasResponded {
                awaiting.append(p.user.displayName)
            } else if p.isAvailable != true {
                declined.append(p.user.displayName)
            } else if let lat = p.lat, let lon = p.lon {
                planning.append(PlanningParticipant(
                    id: p.user.id,
                    name: p.user.displayName.components(separatedBy: " ").first ?? p.user.displayName,
                    transportMode: TransportMode(rawValue: p.user.transportMode) ?? .transit,
                    maxTravelMinutes: p.user.maxTravelMinutes,
                    budget: BudgetRange(rawValue: p.user.budget) ?? .medium,
                    interests: p.user.interests,
                    coordinate: Coordinate(latitude: lat, longitude: lon)
                ))
            }
        }
        return MeetupSessionState(
            id: id,
            status: MeetupSessionStatus(rawValue: status) ?? .collecting,
            participants: planning,
            awaitingNames: awaiting,
            declinedNames: declined
        )
    }
}

private struct SuggestionUploadDTO: Encodable {
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

private struct SuggestionOptionDTO: Decodable {
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

    var votable: VotableSuggestion {
        VotableSuggestion(id: id, rank: rank, venueName: venueName, areaName: areaName,
                          category: category,
                          coordinate: Coordinate(latitude: lat, longitude: lon),
                          time: time, explanation: explanation,
                          fairnessScore: fairness, interestScore: interest,
                          budgetFitScore: budgetFit,
                          voterNames: voterNames, myVote: myVote)
    }
}

private struct InviteDTO: Decodable {
    var sessionID: UUID
    var organizerName: String
    var type: String
    var windowKind: String
    var customStart: Date?
    var createdAt: Date?

    var invite: MeetupInvite {
        MeetupInvite(
            id: sessionID,
            organizerName: organizerName,
            type: MeetupType(rawValue: type) ?? .coffee,
            timeWindow: TimeWindow(kind: TimeWindowKind(rawValue: windowKind) ?? .now,
                                   customStart: customStart),
            createdAt: createdAt ?? Date()
        )
    }
}

private struct MeetupDTO: Decodable {
    var id: UUID
    var title: String
    var venueName: String
    var areaName: String
    var lat: Double
    var lon: Double
    var time: Date
    var explanation: String
    var attendeeNames: [String]
    var createdAt: Date?

    var meetup: Meetup {
        Meetup(id: id, title: title, venueName: venueName, areaName: areaName,
               coordinate: Coordinate(latitude: lat, longitude: lon),
               time: time, attendeeNames: attendeeNames,
               explanation: explanation, createdAt: createdAt ?? Date())
    }
}
