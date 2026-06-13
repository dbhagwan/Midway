import Fluent
import FluentSQLiteDriver
import FluentPostgresDriver
import NIOSSL
import Vapor

public func configure(_ app: Application) async throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if let databaseURL = Environment.get("DATABASE_URL") {
        // Production: managed Postgres (Neon, Render, Fly, …). These all
        // require TLS, so force it rather than rely on ?sslmode parsing.
        // Free-tier Neon scales to zero and can take >10s to wake, so give
        // the first connection plenty of room.
        var config = try SQLPostgresConfiguration(url: databaseURL)
        config.coreConfiguration.tls = .require(
            try NIOSSLContext(configuration: .makeClientConfiguration()))
        config.coreConfiguration.options.connectTimeout = .seconds(30)
        app.databases.use(.postgres(configuration: config), as: .psql)
    } else {
        let path = Environment.get("MIDWAY_DB_PATH") ?? "midway.sqlite"
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    app.migrations.add(CreateSchema())
    // A crash here takes the whole service down (exit 132 on the host), so
    // ride out database cold starts instead of trapping at top level.
    var migrationError: Error?
    for attempt in 1...6 {
        do {
            try await app.autoMigrate()
            migrationError = nil
            break
        } catch {
            migrationError = error
            app.logger.warning("Migration attempt \(attempt)/6 failed (database waking up?): \(error)")
            try? await Task.sleep(for: .seconds(5))
        }
    }
    if let migrationError {
        throw migrationError
    }

    try configurePush(app)
    try routes(app)
}
