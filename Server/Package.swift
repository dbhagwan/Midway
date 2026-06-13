// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "midway-server",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        .package(url: "https://github.com/vapor/apns.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.2.0"),
        // Pinned: 1.1+ uses Swift 6 typed-throws syntax that 5.10 can't parse.
        .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.0.4"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "JWT", package: "jwt"),
            ],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            path: "Tests/AppTests"
        ),
    ]
)
