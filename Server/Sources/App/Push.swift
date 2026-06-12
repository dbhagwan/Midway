import Vapor
import VaporAPNS
import APNS
import APNSCore
import Fluent

/// Abstraction over push delivery so business logic can notify users
/// without caring whether APNs is configured (it isn't in tests/dev).
protocol PushSender: Sendable {
    func send(title: String, body: String, payload: [String: String],
              to userIDs: [UUID], on db: Database) async
}

/// Used when APNS_KEY_P8 isn't configured: logs instead of sending.
struct LoggingPushSender: PushSender {
    let logger: Logger

    func send(title: String, body: String, payload: [String: String],
              to userIDs: [UUID], on db: Database) async {
        logger.info("push (not configured) → \(userIDs.count) user(s): \(title) — \(body)")
    }
}

/// Real APNs delivery via token-based (p8) authentication.
struct APNSPushSender: PushSender {
    let app: Application

    struct Payload: Codable, Sendable {
        var info: [String: String]
    }

    func send(title: String, body: String, payload: [String: String],
              to userIDs: [UUID], on db: Database) async {
        guard !userIDs.isEmpty else { return }
        let tokens = (try? await DeviceToken.query(on: db)
            .filter(\.$user.$id ~~ userIDs)
            .all()) ?? []

        for device in tokens {
            let notification = APNSAlertNotification(
                alert: .init(title: .raw(title), body: .raw(body)),
                expiration: .immediately,
                priority: .immediately,
                topic: Environment.get("APNS_TOPIC") ?? "com.midway.app",
                payload: Payload(info: payload)
            )
            do {
                try await app.apns.client.sendAlertNotification(notification,
                                                                deviceToken: device.token)
            } catch {
                app.logger.report(error: error)
                // Invalid/expired tokens shouldn't accumulate.
                if "\(error)".contains("BadDeviceToken") {
                    try? await device.delete(on: db)
                }
            }
        }
    }
}

extension Application {
    private struct PushSenderKey: StorageKey {
        typealias Value = PushSender
    }

    var push: PushSender {
        get { storage[PushSenderKey.self] ?? LoggingPushSender(logger: logger) }
        set { storage[PushSenderKey.self] = newValue }
    }
}

/// Configure APNs from the environment when credentials are present:
/// APNS_KEY_P8 (PEM contents), APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC,
/// APNS_ENVIRONMENT ("production" for the App Store build).
func configurePush(_ app: Application) throws {
    guard let p8 = Environment.get("APNS_KEY_P8"),
          let keyID = Environment.get("APNS_KEY_ID"),
          let teamID = Environment.get("APNS_TEAM_ID") else {
        app.push = LoggingPushSender(logger: app.logger)
        return
    }

    let environment: APNSEnvironment =
        Environment.get("APNS_ENVIRONMENT") == "production" ? .production : .development

    app.apns.containers.use(
        APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: p8),
                keyIdentifier: keyID,
                teamIdentifier: teamID
            ),
            environment: environment
        ),
        eventLoopGroupProvider: .shared(app.eventLoopGroup),
        responseDecoder: JSONDecoder(),
        requestEncoder: JSONEncoder(),
        as: .default
    )
    app.push = APNSPushSender(app: app)
}
