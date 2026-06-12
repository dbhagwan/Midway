@testable import App
import XCTVapor

final class ServerTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = Application(.testing)
        try await configure(app)
    }

    override func tearDown() async throws {
        app.shutdown()
        app = nil
    }

    // MARK: helpers

    @discardableResult
    private func login(_ name: String) throws -> LoginResponse {
        var result: LoginResponse?
        try app.test(.POST, "v1/auth/login", beforeRequest: { req in
            try req.content.encode(LoginRequest(
                provider: "mock", providerUserID: "id-\(name)",
                displayName: name, avatarURL: nil, username: name.lowercased()))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            result = try res.content.decode(LoginResponse.self)
        })
        return result!
    }

    private func befriend(_ a: LoginResponse, _ b: LoginResponse) throws {
        var edgeID: UUID?
        try app.test(.POST, "v1/friends/requests", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: a.token)
            try req.content.encode(FriendRequestBody(username: b.user.username))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            edgeID = try res.content.decode(FriendDTO.self).edgeID
        })
        try app.test(.POST, "v1/friends/requests/\(edgeID!)", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: b.token)
            try req.content.encode(FriendRespondBody(accept: true))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
        })
    }

    // MARK: tests

    func testLoginIsIdempotentPerProviderIdentity() throws {
        let first = try login("Ava")
        let second = try login("Ava")
        XCTAssertEqual(first.user.id, second.user.id)
        XCTAssertNotEqual(first.token, second.token, "each login issues a fresh token")
    }

    func testMeRequiresAuth() throws {
        try app.test(.GET, "v1/me") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testProfileUpdateRoundTrips() throws {
        let session = try login("Leo")
        try app.test(.PUT, "v1/me", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: session.token)
            try req.content.encode(ProfileUpdateRequest(
                displayName: nil, username: nil, homeAreaName: "Outer Sunset",
                transportMode: "driving", maxTravelMinutes: 25, budget: 1,
                interests: ["Bars", "Sports"], defaultSharing: "exact"))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let user = try res.content.decode(UserDTO.self)
            XCTAssertEqual(user.homeAreaName, "Outer Sunset")
            XCTAssertEqual(user.transportMode, "driving")
            XCTAssertEqual(user.interests, ["Bars", "Sports"])
        })
    }

    func testFriendRequestFlow() throws {
        let ava = try login("Ava")
        let leo = try login("Leo")

        try befriend(ava, leo)

        try app.test(.GET, "v1/friends", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: ava.token)
        }, afterResponse: { res in
            let list = try res.content.decode(FriendListResponse.self)
            XCTAssertEqual(list.friends.count, 1)
            XCTAssertEqual(list.friends.first?.status, "accepted")
            XCTAssertEqual(list.friends.first?.user.username, "leo")
        })

        // Duplicate requests are rejected.
        try app.test(.POST, "v1/friends/requests", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: ava.token)
            try req.content.encode(FriendRequestBody(username: "leo"))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .conflict)
        })
    }

    func testMeetupWorkflowEndToEnd() throws {
        let ava = try login("Ava")
        let leo = try login("Leo")
        try befriend(ava, leo)

        // 1. Ava creates a plan, answering with her own approximate location.
        var sessionID: UUID?
        try app.test(.POST, "v1/meetups", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: ava.token)
            try req.content.encode(CreateMeetupBody(
                participantUserIDs: [leo.user.id],
                type: "coffee", windowKind: "tonight", customStart: nil,
                maxBudget: 2, indoorOutdoor: "either", dietary: [], vibe: "lowkey",
                maxTravelMinutes: nil,
                organizerResponse: ParticipantResponseBody(
                    isAvailable: true, sharing: "approximate",
                    lat: 37.76, lon: -122.42, manualPlaceName: nil)))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let dto = try res.content.decode(SessionDTO.self)
            XCTAssertEqual(dto.status, "collecting")
            XCTAssertEqual(dto.participants.count, 2)
            sessionID = dto.id
        })

        // 2. Leo sees the invite.
        try app.test(.GET, "v1/meetups/invites", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: leo.token)
        }, afterResponse: { res in
            let invites = try res.content.decode([InviteDTO].self)
            XCTAssertEqual(invites.count, 1)
            XCTAssertEqual(invites.first?.organizerName, "Ava")
        })

        // 3. Leo responds — the session flips to ready.
        try app.test(.POST, "v1/meetups/\(sessionID!)/respond", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: leo.token)
            try req.content.encode(ParticipantResponseBody(
                isAvailable: true, sharing: "approximate",
                lat: 37.74, lon: -122.48, manualPlaceName: nil))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
        })
        try app.test(.GET, "v1/meetups/\(sessionID!)", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: ava.token)
        }, afterResponse: { res in
            let dto = try res.content.decode(SessionDTO.self)
            XCTAssertEqual(dto.status, "ready")
            XCTAssertTrue(dto.participants.allSatisfy(\.hasResponded))
        })

        // 4. Only the organizer can confirm.
        try app.test(.POST, "v1/meetups/\(sessionID!)/confirm", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: leo.token)
            try req.content.encode(Self.confirmBody)
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .forbidden)
        })
        try app.test(.POST, "v1/meetups/\(sessionID!)/confirm", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: ava.token)
            try req.content.encode(Self.confirmBody)
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let meetup = try res.content.decode(MeetupDTO.self)
            XCTAssertEqual(Set(meetup.attendeeNames), ["Ava", "Leo"])
        })

        // 5. Both see the confirmed meetup, and session locations are erased.
        for session in [ava, leo] {
            try app.test(.GET, "v1/meetups/confirmed", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: session.token)
            }, afterResponse: { res in
                let meetups = try res.content.decode([MeetupDTO].self)
                XCTAssertEqual(meetups.count, 1)
                XCTAssertEqual(meetups.first?.venueName, "Ritual Coffee Roasters")
            })
        }
        try app.test(.GET, "v1/meetups/\(sessionID!)", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: ava.token)
        }, afterResponse: { res in
            let dto = try res.content.decode(SessionDTO.self)
            XCTAssertEqual(dto.status, "confirmed")
            XCTAssertTrue(dto.participants.allSatisfy { $0.lat == nil && $0.lon == nil },
                          "locations must be erased after confirmation")
        })
    }

    func testStrangersCannotBeInvited() throws {
        let ava = try login("Ava")
        let stranger = try login("Zed")

        try app.test(.POST, "v1/meetups", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: ava.token)
            try req.content.encode(CreateMeetupBody(
                participantUserIDs: [stranger.user.id],
                type: "coffee", windowKind: "now", customStart: nil,
                maxBudget: nil, indoorOutdoor: "either", dietary: [], vibe: "",
                maxTravelMinutes: nil,
                organizerResponse: ParticipantResponseBody(
                    isAvailable: true, sharing: "approximate",
                    lat: 37.76, lon: -122.42, manualPlaceName: nil)))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .forbidden)
        })
    }

    private static let confirmBody = ConfirmMeetupBody(
        title: "Coffee at Ritual", venueName: "Ritual Coffee Roasters",
        areaName: "Hayes Valley", lat: 37.776, lon: -122.423,
        time: Date().addingTimeInterval(3600),
        explanation: "Fair for both of you.")
}
