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
        var config = try SQLPostgresConfiguration(url: databaseURL)
        config.coreConfiguration.tls = .require(
            try NIOSSLContext(configuration: .makeClientConfiguration()))
        app.databases.use(.postgres(configuration: config), as: .psql)
    } else {
        let path = Environment.get("MIDWAY_DB_PATH") ?? "midway.sqlite"
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    app.migrations.add(CreateSchema())
    try await app.autoMigrate()

    try configurePush(app)
    try routes(app)
}
