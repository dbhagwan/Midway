import Fluent
import JWT
import Vapor

/// Bearer-token auth: tokens are opaque strings issued at login.
struct UserTokenAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        guard let token = try await UserToken.query(on: request.db)
            .filter(\.$value == bearer.token)
            .with(\.$user)
            .first() else { return }
        request.auth.login(token.user)
    }
}

func routes(_ app: Application) throws {
    app.get("healthz") { _ in ["status": "ok"] }

    // Universal links (https://midway.app/add/<username> etc.). Replace
    // TEAMID with the real Apple Team ID before going live.
    app.get(".well-known", "apple-app-site-association") { _ -> Response in
        let aasa = """
        {"applinks":{"apps":[],"details":[{"appID":"TEAMID.com.midway.app","paths":["/add/*","/invite/*"]}]}}
        """
        return Response(status: .ok,
                        headers: ["Content-Type": "application/json"],
                        body: .init(string: aasa))
    }

    let v1 = app.grouped("v1")
    try v1.register(collection: AuthController())

    let protected = v1.grouped(UserTokenAuthenticator(), User.guardMiddleware())
    try protected.register(collection: ProfileController())
    try protected.register(collection: FriendsController())
    try protected.register(collection: MeetupsController())
    try protected.register(collection: DevicesController())
}

// MARK: - Safety helpers

/// True if either user has blocked the other.
func isBlocked(between a: UUID, and b: UUID, on db: Database) async throws -> Bool {
    try await BlockedUser.query(on: db)
        .group(.or) { or in
            or.group(.and) { and in
                and.filter(\.$blocker.$id == a)
                and.filter(\.$blocked.$id == b)
            }
            or.group(.and) { and in
                and.filter(\.$blocker.$id == b)
                and.filter(\.$blocked.$id == a)
            }
        }
        .count() > 0
}

// MARK: - Devices

struct DevicesController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("devices", use: register)
    }

    func register(req: Request) async throws -> HTTPStatus {
        let myID = try req.auth.require(User.self).requireID()
        let body = try req.content.decode(DeviceBody.self)
        // Re-registration moves the token to the latest account.
        if let existing = try await DeviceToken.query(on: req.db)
            .filter(\.$token == body.token)
            .first() {
            existing.$user.id = myID
            try await existing.save(on: req.db)
        } else {
            try await DeviceToken(userID: myID, token: body.token).create(on: req.db)
        }
        return .ok
    }
}

// MARK: - Auth

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("auth", "login", use: login)
    }

    /// Exchange a provider identity for a Midway token, creating the user on
    /// first login. The provider credential is verified server-side — Apple
    /// identity tokens against Apple's public keys, Snap access tokens
    /// against Snap's /me endpoint — and the verified subject (not the
    /// client's claim) becomes the canonical provider user ID.
    func login(req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)
        let verifiedID = try await Self.verifyIdentity(body, on: req)

        let user: User
        if let existing = try await User.query(on: req.db)
            .filter(\.$provider == body.provider)
            .filter(\.$providerUserID == verifiedID)
            .first() {
            user = existing
        } else {
            user = User()
            user.provider = body.provider
            user.providerUserID = verifiedID
            user.displayName = body.displayName
            user.avatarURL = body.avatarURL
            user.username = try await Self.availableUsername(
                preferred: body.username ?? body.displayName, on: req.db)
            user.homeAreaName = ""
            user.transportMode = "transit"
            user.maxTravelMinutes = 30
            user.budget = 2
            user.interests = []
            user.defaultSharing = "approximate"
            try await user.create(on: req.db)
        }

        let token = UserToken(value: [UInt8].random(count: 32).base64,
                              userID: try user.requireID())
        try await token.create(on: req.db)
        return LoginResponse(token: token.value, user: try UserDTO(user))
    }

    /// Returns the provider-verified user ID, or throws .unauthorized.
    private static func verifyIdentity(_ body: LoginRequest,
                                       on req: Request) async throws -> String {
        switch body.provider {
        case "apple":
            guard let credential = body.credential else {
                throw Abort(.unauthorized, reason: "Missing Apple identity token.")
            }
            let bundleID = Environment.get("APPLE_BUNDLE_ID") ?? "com.midway.app"
            do {
                let identity = try await req.jwt.apple.verify(
                    credential, applicationIdentifier: bundleID)
                return identity.subject.value
            } catch {
                req.logger.info("Apple token verification failed: \(error)")
                throw Abort(.unauthorized, reason: "Apple rejected the identity token.")
            }

        case "snapchat":
            guard let credential = body.credential else {
                throw Abort(.unauthorized, reason: "Missing Snapchat access token.")
            }
            struct SnapMe: Decodable {
                struct DataBox: Decodable {
                    struct Me: Decodable { var externalId: String }
                    var me: Me
                }
                var data: DataBox
            }
            let response = try await req.client.post("https://kit.snapchat.com/v1/me") { creq in
                creq.headers.bearerAuthorization = .init(token: credential)
                try creq.content.encode(["query": "{me{externalId}}"])
            }
            guard response.status == .ok,
                  let payload = try? response.content.decode(SnapMe.self) else {
                throw Abort(.unauthorized, reason: "Snapchat rejected the access token.")
            }
            return payload.data.me.externalId

        case "mock":
            // Development identity. In production it must be explicitly
            // enabled (useful until Snap/Apple credentials are configured);
            // remove MIDWAY_ALLOW_MOCK_AUTH before a public launch.
            let allowed = req.application.environment != .production
                || Environment.get("MIDWAY_ALLOW_MOCK_AUTH") == "true"
            guard allowed else {
                throw Abort(.unauthorized, reason: "Mock sign-in is disabled in production.")
            }
            return body.providerUserID

        default:
            throw Abort(.unauthorized, reason: "Unknown identity provider.")
        }
    }

    static func availableUsername(preferred: String, on db: Database) async throws -> String {
        let base = preferred.lowercased().filter { $0.isLetter || $0.isNumber }
        let candidate = base.isEmpty ? "midway" : String(base.prefix(20))
        var name = candidate
        var attempt = 0
        while try await User.query(on: db).filter(\.$username == name).first() != nil {
            attempt += 1
            name = "\(candidate)\(Int.random(in: 100...9999))"
            if attempt > 10 { name = "\(candidate)\(UUID().uuidString.prefix(8).lowercased())" }
        }
        return name
    }
}

// MARK: - Profile

struct ProfileController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("me", use: me)
        routes.put("me", use: update)
        routes.delete("me", use: deleteAccount)
    }

    /// App Store-required account deletion: removes the user and all
    /// Midway-owned data. Confirmed meetup cards keep only the display-name
    /// snapshot other attendees already had.
    func deleteAccount(req: Request) async throws -> HTTPStatus {
        let me = try req.auth.require(User.self)
        let myID = try me.requireID()

        try await UserToken.query(on: req.db).filter(\.$user.$id == myID).delete()
        try await DeviceToken.query(on: req.db).filter(\.$user.$id == myID).delete()
        try await Vote.query(on: req.db).filter(\.$user.$id == myID).delete()
        try await FriendEdge.query(on: req.db)
            .group(.or) { or in
                or.filter(\.$requester.$id == myID)
                or.filter(\.$recipient.$id == myID)
            }
            .delete()
        try await BlockedUser.query(on: req.db)
            .group(.or) { or in
                or.filter(\.$blocker.$id == myID)
                or.filter(\.$blocked.$id == myID)
            }
            .delete()
        try await SessionParticipant.query(on: req.db).filter(\.$user.$id == myID).delete()

        // Remove sessions this user organized (cards in confirmed_meetups
        // have no FK and survive for the other attendees).
        let organized = try await MeetupSession.query(on: req.db)
            .filter(\.$organizer.$id == myID)
            .all()
        for session in organized {
            let sessionID = try session.requireID()
            try await Vote.query(on: req.db).filter(\.$sessionID == sessionID).delete()
            try await SuggestionOption.query(on: req.db).filter(\.$sessionID == sessionID).delete()
            try await SessionParticipant.query(on: req.db)
                .filter(\.$session.$id == sessionID).delete()
            try await session.delete(on: req.db)
        }

        try await me.delete(on: req.db)
        return .ok
    }

    func me(req: Request) async throws -> UserDTO {
        try UserDTO(req.auth.require(User.self))
    }

    func update(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(ProfileUpdateRequest.self)

        if let value = body.displayName { user.displayName = value }
        if let value = body.username {
            let normalized = value.lowercased().filter { $0.isLetter || $0.isNumber }
            if !normalized.isEmpty, normalized != user.username {
                guard try await User.query(on: req.db)
                    .filter(\.$username == normalized)
                    .first() == nil else {
                    throw Abort(.conflict, reason: "Username is taken.")
                }
                user.username = normalized
            }
        }
        if let value = body.homeAreaName { user.homeAreaName = value }
        if let value = body.transportMode { user.transportMode = value }
        if let value = body.maxTravelMinutes { user.maxTravelMinutes = value }
        if let value = body.budget { user.budget = value }
        if let value = body.interests { user.interests = value }
        if let value = body.defaultSharing { user.defaultSharing = value }

        try await user.save(on: req.db)
        return try UserDTO(user)
    }
}

// MARK: - Friends

struct FriendsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("friends", use: list)
        routes.post("friends", "requests", use: send)
        routes.post("friends", "requests", ":edgeID", use: respond)
        routes.post("users", ":userID", "block", use: block)
    }

    /// Block (and optionally report) a user: severs the friend edge and
    /// prevents requests/invites in either direction.
    func block(req: Request) async throws -> HTTPStatus {
        let myID = try req.auth.require(User.self).requireID()
        guard let targetID = req.parameters.get("userID", as: UUID.self),
              targetID != myID,
              try await User.find(targetID, on: req.db) != nil else {
            throw Abort(.notFound)
        }
        let body = (try? req.content.decode(BlockBody.self)) ?? BlockBody(report: false, reason: nil)

        try await FriendEdge.query(on: req.db)
            .group(.or) { or in
                or.group(.and) { and in
                    and.filter(\.$requester.$id == myID)
                    and.filter(\.$recipient.$id == targetID)
                }
                or.group(.and) { and in
                    and.filter(\.$requester.$id == targetID)
                    and.filter(\.$recipient.$id == myID)
                }
            }
            .delete()

        if try await !isBlocked(between: myID, and: targetID, on: req.db) || body.report {
            try await BlockedUser(blockerID: myID, blockedID: targetID,
                                  isReport: body.report, reason: body.reason)
                .create(on: req.db)
        }
        return .ok
    }

    func list(req: Request) async throws -> FriendListResponse {
        let me = try req.auth.require(User.self)
        let myID = try me.requireID()

        let edges = try await FriendEdge.query(on: req.db)
            .group(.or) { or in
                or.filter(\.$requester.$id == myID)
                or.filter(\.$recipient.$id == myID)
            }
            .with(\.$requester)
            .with(\.$recipient)
            .all()

        let friends = try edges.map { edge -> FriendDTO in
            let iAmRequester = edge.$requester.id == myID
            let other = iAmRequester ? edge.recipient : edge.requester
            let status: String
            if edge.status == FriendEdgeStatus.accepted.rawValue {
                status = "accepted"
            } else {
                status = iAmRequester ? "outgoing" : "incoming"
            }
            return FriendDTO(edgeID: try edge.requireID(),
                             user: try PublicUserDTO(other),
                             status: status)
        }
        return FriendListResponse(friends: friends)
    }

    func send(req: Request) async throws -> FriendDTO {
        let me = try req.auth.require(User.self)
        let myID = try me.requireID()
        let body = try req.content.decode(FriendRequestBody.self)
        let username = body.username.lowercased()

        guard username != me.username else {
            throw Abort(.badRequest, reason: "That's you.")
        }
        guard let other = try await User.query(on: req.db)
            .filter(\.$username == username)
            .first() else {
            throw Abort(.notFound, reason: "No Midway user named @\(username).")
        }
        let otherID = try other.requireID()

        // Blocked pairs look like "not found" — don't leak block state.
        if try await isBlocked(between: myID, and: otherID, on: req.db) {
            throw Abort(.notFound, reason: "No Midway user named @\(username).")
        }

        let existing = try await FriendEdge.query(on: req.db)
            .group(.or) { or in
                or.group(.and) { and in
                    and.filter(\.$requester.$id == myID)
                    and.filter(\.$recipient.$id == otherID)
                }
                or.group(.and) { and in
                    and.filter(\.$requester.$id == otherID)
                    and.filter(\.$recipient.$id == myID)
                }
            }
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "Already connected or pending.")
        }

        let edge = FriendEdge(requesterID: myID, recipientID: otherID)
        try await edge.create(on: req.db)
        return FriendDTO(edgeID: try edge.requireID(),
                         user: try PublicUserDTO(other),
                         status: "outgoing")
    }

    func respond(req: Request) async throws -> HTTPStatus {
        let me = try req.auth.require(User.self)
        let myID = try me.requireID()
        guard let edgeID = req.parameters.get("edgeID", as: UUID.self),
              let edge = try await FriendEdge.find(edgeID, on: req.db) else {
            throw Abort(.notFound)
        }
        // Only the recipient of a pending request may respond.
        guard edge.$recipient.id == myID,
              edge.status == FriendEdgeStatus.pending.rawValue else {
            throw Abort(.forbidden)
        }
        let body = try req.content.decode(FriendRespondBody.self)
        if body.accept {
            edge.status = FriendEdgeStatus.accepted.rawValue
            try await edge.save(on: req.db)
        } else {
            try await edge.delete(on: req.db)
        }
        return .ok
    }
}

// MARK: - Meetups

struct MeetupsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("meetups", use: create)
        routes.get("meetups", "invites", use: invites)
        routes.get("meetups", "confirmed", use: confirmedList)
        routes.delete("meetups", "confirmed", ":meetupID", use: deleteConfirmed)
        routes.post("meetups", "confirmed", ":meetupID", "onmyway", use: onMyWay)
        routes.get("meetups", "votes", "pending", use: pendingVotes)
        routes.get("meetups", ":sessionID", use: state)
        routes.post("meetups", ":sessionID", "respond", use: respond)
        routes.post("meetups", ":sessionID", "suggestions", use: publishSuggestions)
        routes.get("meetups", ":sessionID", "suggestions", use: listSuggestions)
        routes.post("meetups", ":sessionID", "vote", use: vote)
        routes.post("meetups", ":sessionID", "cancel", use: cancel)
        routes.post("meetups", ":sessionID", "confirm", use: confirm)
    }

    func create(req: Request) async throws -> SessionDTO {
        let me = try req.auth.require(User.self)
        let myID = try me.requireID()
        let body = try req.content.decode(CreateMeetupBody.self)

        guard !body.participantUserIDs.isEmpty else {
            throw Abort(.badRequest, reason: "Invite at least one friend.")
        }

        // Only accepted friends can be invited.
        let friendIDs = try await acceptedFriendIDs(of: myID, on: req.db)
        for participant in body.participantUserIDs where !friendIDs.contains(participant) {
            throw Abort(.forbidden, reason: "You can only invite accepted friends.")
        }

        let session = MeetupSession()
        session.$organizer.id = myID
        session.type = body.type
        session.windowKind = body.windowKind
        session.customStart = body.customStart
        session.maxBudget = body.maxBudget
        session.indoorOutdoor = body.indoorOutdoor
        session.dietary = body.dietary
        session.vibe = body.vibe
        session.maxTravelMinutes = body.maxTravelMinutes
        session.status = SessionStatus.collecting.rawValue
        try await session.create(on: req.db)
        let sessionID = try session.requireID()

        // Organizer's row, answered immediately with their consented location.
        let mine = SessionParticipant(sessionID: sessionID, userID: myID)
        apply(body.organizerResponse, to: mine)
        try await mine.create(on: req.db)

        for userID in Set(body.participantUserIDs) {
            // Blocked users silently don't receive invites.
            if try await isBlocked(between: myID, and: userID, on: req.db) { continue }
            try await SessionParticipant(sessionID: sessionID, userID: userID)
                .create(on: req.db)
        }

        await req.application.push.send(
            title: "\(me.displayName) wants to meet up",
            body: "\(body.type.capitalized) · \(body.windowKind). Share your availability.",
            payload: ["kind": "invite", "sessionID": sessionID.uuidString],
            to: body.participantUserIDs, on: req.db)

        return try await dto(for: session, on: req.db)
    }

    func invites(req: Request) async throws -> [InviteDTO] {
        let myID = try req.auth.require(User.self).requireID()
        let rows = try await SessionParticipant.query(on: req.db)
            .filter(\.$user.$id == myID)
            .filter(\.$respondedAt == nil)
            .with(\.$session) { $0.with(\.$organizer) }
            .all()

        return rows.compactMap { row in
            let session = row.session
            guard session.status == SessionStatus.collecting.rawValue,
                  session.$organizer.id != myID,
                  let id = session.id else { return nil }
            return InviteDTO(sessionID: id,
                             organizerName: session.organizer.displayName,
                             type: session.type,
                             windowKind: session.windowKind,
                             customStart: session.customStart,
                             createdAt: session.createdAt)
        }
    }

    func respond(req: Request) async throws -> HTTPStatus {
        let myID = try req.auth.require(User.self).requireID()
        let session = try await find(req)
        let body = try req.content.decode(ParticipantResponseBody.self)

        guard session.status == SessionStatus.collecting.rawValue else {
            throw Abort(.conflict, reason: "This plan is no longer collecting responses.")
        }
        guard let row = try await SessionParticipant.query(on: req.db)
            .filter(\.$session.$id == session.requireID())
            .filter(\.$user.$id == myID)
            .first() else {
            throw Abort(.forbidden, reason: "You're not part of this plan.")
        }

        apply(body, to: row)
        try await row.save(on: req.db)

        // When everyone has answered, the organizer can rank and confirm.
        let pending = try await SessionParticipant.query(on: req.db)
            .filter(\.$session.$id == session.requireID())
            .filter(\.$respondedAt == nil)
            .count()
        if pending == 0 {
            session.status = SessionStatus.ready.rawValue
            try await session.save(on: req.db)
            let sessionID = try session.requireID()
            await req.application.push.send(
                title: "Everyone's in",
                body: "All responses are in — Midway is ready to rank spots.",
                payload: ["kind": "ready", "sessionID": sessionID.uuidString],
                to: [session.$organizer.id], on: req.db)
        }
        return .ok
    }

    // MARK: Voting

    /// Organizer publishes the device-ranked options so the group can vote.
    func publishSuggestions(req: Request) async throws -> HTTPStatus {
        let myID = try req.auth.require(User.self).requireID()
        let session = try await find(req)
        guard session.$organizer.id == myID else { throw Abort(.forbidden) }
        guard session.status == SessionStatus.ready.rawValue
                || session.status == SessionStatus.voting.rawValue else {
            throw Abort(.conflict, reason: "Not ready for suggestions yet.")
        }
        let uploads = try req.content.decode([SuggestionUpload].self)
        let sessionID = try session.requireID()

        try await Vote.query(on: req.db).filter(\.$sessionID == sessionID).delete()
        try await SuggestionOption.query(on: req.db).filter(\.$sessionID == sessionID).delete()
        for upload in uploads {
            let option = SuggestionOption()
            option.sessionID = sessionID
            option.rank = upload.rank
            option.venueName = upload.venueName
            option.areaName = upload.areaName
            option.category = upload.category
            option.lat = upload.lat
            option.lon = upload.lon
            option.time = upload.time
            option.explanation = upload.explanation
            option.fairness = upload.fairness
            option.interest = upload.interest
            option.budgetFit = upload.budgetFit
            try await option.create(on: req.db)
        }

        session.status = SessionStatus.voting.rawValue
        try await session.save(on: req.db)

        let others = try await participantIDs(of: sessionID, on: req.db, excluding: myID)
        await req.application.push.send(
            title: "Vote on where to meet",
            body: "Midway found \(uploads.count) fair options — pick your favorite.",
            payload: ["kind": "vote", "sessionID": sessionID.uuidString],
            to: others, on: req.db)
        return .ok
    }

    func listSuggestions(req: Request) async throws -> [SuggestionOptionDTO] {
        let myID = try req.auth.require(User.self).requireID()
        let session = try await find(req)
        let sessionID = try session.requireID()
        guard try await isMember(myID, of: sessionID, on: req.db) else {
            throw Abort(.forbidden)
        }

        let options = try await SuggestionOption.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .sort(\.$rank)
            .all()
        let votes = try await Vote.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .with(\.$user)
            .all()

        return try options.map { option in
            let optionID = try option.requireID()
            let voters = votes.filter { $0.suggestionID == optionID }
            return SuggestionOptionDTO(
                id: optionID, rank: option.rank,
                venueName: option.venueName, areaName: option.areaName,
                category: option.category, lat: option.lat, lon: option.lon,
                time: option.time, explanation: option.explanation,
                fairness: option.fairness, interest: option.interest,
                budgetFit: option.budgetFit,
                voterNames: voters.map {
                    $0.user.displayName.components(separatedBy: " ").first ?? $0.user.displayName
                },
                myVote: voters.contains { $0.$user.id == myID }
            )
        }
    }

    func vote(req: Request) async throws -> HTTPStatus {
        let me = try req.auth.require(User.self)
        let myID = try me.requireID()
        let session = try await find(req)
        let sessionID = try session.requireID()
        guard session.status == SessionStatus.voting.rawValue else {
            throw Abort(.conflict, reason: "Voting isn't open on this plan.")
        }
        guard try await isMember(myID, of: sessionID, on: req.db) else {
            throw Abort(.forbidden)
        }
        let body = try req.content.decode(VoteBody.self)
        guard let option = try await SuggestionOption.find(body.suggestionID, on: req.db),
              option.sessionID == sessionID else {
            throw Abort(.notFound)
        }

        // One vote per person; re-voting replaces it.
        try await Vote.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$user.$id == myID)
            .delete()
        try await Vote(sessionID: sessionID, suggestionID: body.suggestionID, userID: myID)
            .create(on: req.db)

        if session.$organizer.id != myID {
            await req.application.push.send(
                title: "\(me.displayName) voted",
                body: "\(option.venueName) got a vote.",
                payload: ["kind": "voted", "sessionID": sessionID.uuidString],
                to: [session.$organizer.id], on: req.db)
        }
        return .ok
    }

    /// Sessions where I can vote but haven't yet.
    func pendingVotes(req: Request) async throws -> [VotePendingDTO] {
        let myID = try req.auth.require(User.self).requireID()
        let rows = try await SessionParticipant.query(on: req.db)
            .filter(\.$user.$id == myID)
            .with(\.$session) { $0.with(\.$organizer) }
            .all()
        var result: [VotePendingDTO] = []
        for row in rows {
            let session = row.session
            guard session.status == SessionStatus.voting.rawValue,
                  session.$organizer.id != myID,
                  row.isAvailable == true,
                  let sessionID = session.id else { continue }
            let voted = try await Vote.query(on: req.db)
                .filter(\.$sessionID == sessionID)
                .filter(\.$user.$id == myID)
                .count() > 0
            if !voted {
                result.append(VotePendingDTO(sessionID: sessionID,
                                             organizerName: session.organizer.displayName,
                                             type: session.type,
                                             createdAt: session.createdAt))
            }
        }
        return result
    }

    // MARK: Lifecycle

    func cancel(req: Request) async throws -> HTTPStatus {
        let myID = try req.auth.require(User.self).requireID()
        let session = try await find(req)
        guard session.$organizer.id == myID else { throw Abort(.forbidden) }
        guard session.status != SessionStatus.confirmed.rawValue else {
            throw Abort(.conflict, reason: "Already confirmed — delete the meetup instead.")
        }
        session.status = SessionStatus.cancelled.rawValue
        try await session.save(on: req.db)

        let sessionID = try session.requireID()
        let others = try await participantIDs(of: sessionID, on: req.db, excluding: myID)
        await req.application.push.send(
            title: "Plan cancelled",
            body: "The \(session.type) plan was called off.",
            payload: ["kind": "cancelled", "sessionID": sessionID.uuidString],
            to: others, on: req.db)
        return .ok
    }

    func deleteConfirmed(req: Request) async throws -> HTTPStatus {
        let myID = try req.auth.require(User.self).requireID()
        guard let meetupID = req.parameters.get("meetupID", as: UUID.self),
              let meetup = try await ConfirmedMeetup.find(meetupID, on: req.db),
              let session = try await MeetupSession.find(meetup.sessionID, on: req.db) else {
            throw Abort(.notFound)
        }
        guard session.$organizer.id == myID else { throw Abort(.forbidden) }

        let others = try await participantIDs(of: meetup.sessionID, on: req.db, excluding: myID)
        try await meetup.delete(on: req.db)
        await req.application.push.send(
            title: "Meetup cancelled",
            body: "\(meetup.title) was cancelled.",
            payload: ["kind": "meetupCancelled", "meetupID": meetupID.uuidString],
            to: others, on: req.db)
        return .ok
    }

    /// Lightweight presence signal: tells the other attendees you've left.
    func onMyWay(req: Request) async throws -> HTTPStatus {
        let me = try req.auth.require(User.self)
        let myID = try me.requireID()
        guard let meetupID = req.parameters.get("meetupID", as: UUID.self),
              let meetup = try await ConfirmedMeetup.find(meetupID, on: req.db) else {
            throw Abort(.notFound)
        }
        guard try await isMember(myID, of: meetup.sessionID, on: req.db) else {
            throw Abort(.forbidden)
        }
        let others = try await participantIDs(of: meetup.sessionID, on: req.db, excluding: myID)
        await req.application.push.send(
            title: "\(me.displayName) is on the way",
            body: "Heading to \(meetup.venueName) 🏃",
            payload: ["kind": "onMyWay", "meetupID": meetupID.uuidString],
            to: others, on: req.db)
        return .ok
    }

    func state(req: Request) async throws -> SessionDTO {
        let myID = try req.auth.require(User.self).requireID()
        let session = try await find(req)
        let isMember = try await SessionParticipant.query(on: req.db)
            .filter(\.$session.$id == session.requireID())
            .filter(\.$user.$id == myID)
            .count() > 0
        guard isMember else { throw Abort(.forbidden) }
        return try await dto(for: session, on: req.db)
    }

    func confirm(req: Request) async throws -> MeetupDTO {
        let myID = try req.auth.require(User.self).requireID()
        let session = try await find(req)
        guard session.$organizer.id == myID else {
            throw Abort(.forbidden, reason: "Only the organizer can confirm.")
        }
        guard session.status != SessionStatus.confirmed.rawValue else {
            throw Abort(.conflict, reason: "Already confirmed.")
        }
        let body = try req.content.decode(ConfirmMeetupBody.self)

        let rows = try await SessionParticipant.query(on: req.db)
            .filter(\.$session.$id == session.requireID())
            .with(\.$user)
            .all()
        let attendees = rows
            .filter { $0.$user.id == myID || $0.isAvailable == true }
            .map { $0.user.displayName }

        let meetup = ConfirmedMeetup()
        meetup.sessionID = try session.requireID()
        meetup.title = body.title
        meetup.venueName = body.venueName
        meetup.areaName = body.areaName
        meetup.lat = body.lat
        meetup.lon = body.lon
        meetup.time = body.time
        meetup.explanation = body.explanation
        meetup.attendeeNames = attendees
        try await meetup.create(on: req.db)

        // Session locations were only ever needed for ranking — erase them.
        for row in rows {
            row.lat = nil
            row.lon = nil
            row.manualPlaceName = nil
            try await row.save(on: req.db)
        }

        session.status = SessionStatus.confirmed.rawValue
        try await session.save(on: req.db)

        let sessionID = try session.requireID()
        let others = try await participantIDs(of: sessionID, on: req.db, excluding: myID)
        await req.application.push.send(
            title: "It's a plan!",
            body: "\(body.title) — see you there.",
            payload: ["kind": "confirmed", "sessionID": sessionID.uuidString],
            to: others, on: req.db)
        return try MeetupDTO(meetup)
    }

    func confirmedList(req: Request) async throws -> [MeetupDTO] {
        let myID = try req.auth.require(User.self).requireID()
        let sessionIDs = try await SessionParticipant.query(on: req.db)
            .filter(\.$user.$id == myID)
            .all()
            .map { $0.$session.id }
        guard !sessionIDs.isEmpty else { return [] }
        let meetups = try await ConfirmedMeetup.query(on: req.db)
            .filter(\.$sessionID ~~ sessionIDs)
            .sort(\.$time, .descending)
            .all()
        return try meetups.map { try MeetupDTO($0) }
    }

    // MARK: helpers

    private func find(_ req: Request) async throws -> MeetupSession {
        guard let id = req.parameters.get("sessionID", as: UUID.self),
              let session = try await MeetupSession.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return session
    }

    private func isMember(_ userID: UUID, of sessionID: UUID, on db: Database) async throws -> Bool {
        try await SessionParticipant.query(on: db)
            .filter(\.$session.$id == sessionID)
            .filter(\.$user.$id == userID)
            .count() > 0
    }

    private func participantIDs(of sessionID: UUID, on db: Database,
                                excluding userID: UUID) async throws -> [UUID] {
        try await SessionParticipant.query(on: db)
            .filter(\.$session.$id == sessionID)
            .all()
            .map { $0.$user.id }
            .filter { $0 != userID }
    }

    private func apply(_ body: ParticipantResponseBody, to row: SessionParticipant) {
        row.isAvailable = body.isAvailable
        row.sharing = body.sharing
        row.lat = body.lat
        row.lon = body.lon
        row.manualPlaceName = body.manualPlaceName
        row.respondedAt = Date()
    }

    private func acceptedFriendIDs(of userID: UUID, on db: Database) async throws -> Set<UUID> {
        let edges = try await FriendEdge.query(on: db)
            .filter(\.$status == FriendEdgeStatus.accepted.rawValue)
            .group(.or) { or in
                or.filter(\.$requester.$id == userID)
                or.filter(\.$recipient.$id == userID)
            }
            .all()
        return Set(edges.map { edge in
            edge.$requester.id == userID ? edge.$recipient.id : edge.$requester.id
        })
    }

    private func dto(for session: MeetupSession, on db: Database) async throws -> SessionDTO {
        let organizer = try await session.$organizer.get(on: db)
        let rows = try await SessionParticipant.query(on: db)
            .filter(\.$session.$id == session.requireID())
            .with(\.$user)
            .all()
        return SessionDTO(
            id: try session.requireID(),
            organizer: try PublicUserDTO(organizer),
            status: session.status,
            type: session.type,
            windowKind: session.windowKind,
            customStart: session.customStart,
            maxBudget: session.maxBudget,
            indoorOutdoor: session.indoorOutdoor,
            dietary: session.dietary,
            vibe: session.vibe,
            maxTravelMinutes: session.maxTravelMinutes,
            createdAt: session.createdAt,
            participants: try rows.map { row in
                ParticipantDTO(user: try PublicUserDTO(row.user),
                               hasResponded: row.hasResponded,
                               isAvailable: row.isAvailable,
                               sharing: row.sharing,
                               lat: row.lat,
                               lon: row.lon,
                               manualPlaceName: row.manualPlaceName)
            }
        )
    }
}
