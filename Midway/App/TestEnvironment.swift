import Foundation

/// Deterministic mode for UI tests and CI screenshot runs, activated by the
/// `-uiTestMode` launch argument: fresh store, mock auth, a fixed organizer
/// location, canned venues, and estimate-only routing — so the full flow
/// runs offline-safe with no permission dialogs.
enum TestEnvironment {
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uiTestMode")

    /// True only under XCTest (not for plain `-uiTestMode` launches like
    /// the CI video recording, which must keep the logo animation).
    static let isXCTestRun =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
