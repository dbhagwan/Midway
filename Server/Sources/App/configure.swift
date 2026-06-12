import Fluent
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let path = Environment.get("MIDWAY_DB_PATH") ?? "midway.sqlite"
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    app.migrations.add(CreateSchema())
    try await app.autoMigrate()

    try routes(app)
}
