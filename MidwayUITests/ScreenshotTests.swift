import XCTest

/// Drives the full Midway flow in `-uiTestMode` (mock auth, fresh store,
/// instant demo backend, canned venues, fixed locations) and captures a
/// screenshot of every key screen. PNGs are written to $SCREENSHOT_DIR
/// (passed by CI via TEST_RUNNER_SCREENSHOT_DIR) and also attached to the
/// test results.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var screenshotDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
            ?? NSTemporaryDirectory().appending("/midway-screenshots")
        screenshotDirectory = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory,
                                                withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode"]
        app.launch()
    }

    func testCaptureFullFlow() throws {
        // 1. Sign-in
        let snapButton = app.buttons["Continue with Snapchat"]
        XCTAssertTrue(snapButton.waitForExistence(timeout: 15))
        capture("01-sign-in")
        snapButton.tap()

        // 2. Onboarding — basics
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 15))
        pause(1)
        capture("02-onboarding-basics")

        // 3. Onboarding — interests
        continueButton.tap()
        pause(1)
        for tag in ["Coffee", "Live music", "Outdoors"] {
            let chip = app.buttons[tag]
            if chip.waitForExistence(timeout: 3) { chip.tap() }
        }
        capture("03-onboarding-interests")

        // 4. Onboarding — privacy defaults
        continueButton.tap()
        pause(1)
        capture("04-onboarding-privacy")

        let startButton = app.buttons["Start meeting up"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        // 5. Home with a pending invite from Ava
        let inviteRow = app.buttons["invite-row"].firstMatch
        XCTAssertTrue(inviteRow.waitForExistence(timeout: 15))
        capture("05-home-invite")

        // 6. Respond to the invite (availability + location consent)
        inviteRow.tap()
        let sendResponse = app.buttons["Send response"]
        XCTAssertTrue(sendResponse.waitForExistence(timeout: 10))
        capture("06-invite-respond")
        sendResponse.tap()

        // Ava confirms instantly in demo mode — the meetup lands on home.
        // Generous timeout: sheet dismissal + list update can crawl on
        // loaded CI simulators.
        if !app.staticTexts["Upcoming"].waitForExistence(timeout: 45) {
            // Diagnostic: capture whatever the screen actually shows so the
            // failure is debuggable from the committed artifacts.
            capture("99-debug-after-send")
            XCTFail("'Upcoming' never appeared after sending the invite response")
        }

        // 7. Friends tab (seeded demo friends + a pending request)
        app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["Ava Chen"].waitForExistence(timeout: 10))
        capture("07-friends")

        // 8. Planner wizard
        app.tabBars.buttons["Meetups"].tap()
        let planButton = app.buttons["Plan a meetup"].firstMatch
        XCTAssertTrue(planButton.waitForExistence(timeout: 10))
        planButton.tap()
        let findPlaces = app.buttons["Find places"]
        XCTAssertTrue(findPlaces.waitForExistence(timeout: 10))
        tapRow(containing: "Ava Chen")
        tapRow(containing: "Leo Park")
        capture("08-planner")

        // 9. Session collects responses, then AI-ranked suggestions on the map
        findPlaces.tap()
        let meetHere = app.buttons["Meet here"].firstMatch
        XCTAssertTrue(meetHere.waitForExistence(timeout: 60))
        pause(4) // let map tiles render
        capture("09-suggestions")

        // 10. Confirmed meetup card
        meetHere.tap()
        if !app.navigationBars["It's a plan!"].waitForExistence(timeout: 30) {
            capture("98-debug-after-meet-here")
            XCTFail("'It's a plan!' sheet never appeared after Meet here")
        }
        pause(3)
        capture("10-meetup-card")

        // 11. Home with the upcoming meetups
        app.navigationBars["It's a plan!"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Upcoming"].waitForExistence(timeout: 15))
        pause(1)
        capture("11-home-upcoming")
    }

    // MARK: - Helpers

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = screenshotDirectory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            // Attachment above still preserves the image in the result bundle.
            print("Could not write \(url.path): \(error)")
        }
    }

    private func tapRow(containing label: String) {
        let text = app.staticTexts[label]
        if text.waitForExistence(timeout: 5) {
            text.tap()
        }
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
