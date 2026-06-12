import Fluent
import FluentSQLiteDriver
import FluentPostgresDriver
import Vapor

public func configure(_ app: Application) async throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if let databaseURL = Environment.get("DATABASE_URL") {
        // Production: Postgres (e.g. fly.io / Railway managed database).
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
    } else {
        let path = Environment.get("MIDWAY_DB_PATH") ?? "midway.sqlite"
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    app.migrations.add(CreateSchema())
    try await app.autoMigrate()

    try configurePush(app)
    try routes(app)
}
