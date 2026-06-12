import Fluent
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

    let v1 = app.grouped("v1")
    try v1.register(collection: AuthController())

    let protected = v1.grouped(UserTokenAuthenticator(), User.guardMiddleware())
    try protected.register(collection: ProfileController())
    try protected.register(collection: FriendsController())
    try protected.register(collection: MeetupsController())
}

// MARK: - Auth

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("auth", "login", use: login)
    }

    /// Exchange a provider identity (Snapchat Login Kit on device, or the
    /// mock in demo builds) for a Midway token, creating the user on first
    /// login. NOTE: production must verify the Snap access token server-side
    /// against Snap's /me endpoint before trusting providerUserID.
    func login(req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)

        let user: User
        if let existing = try await User.query(on: req.db)
            .filter(\.$provider == body.provider)
            .filter(\.$providerUserID == body.providerUserID)
            .first() {
            user = existing
        } else {
            user = User()
            user.provider = body.provider
            user.providerUserID = body.providerUserID
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
        routes.get("meetups", ":sessionID", use: state)
        routes.post("meetups", ":sessionID", "respond", use: respond)
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
            try await SessionParticipant(sessionID: sessionID, userID: userID)
                .create(on: req.db)
        }

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
        }
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
