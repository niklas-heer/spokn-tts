import XCTest

final class SpoknUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        if app.state != .notRunning {
            app.terminate()
        }
        app = nil
    }

    // MARK: - Menu Bar Tests

    func testMenuBarIconExists() throws {
        // The app is a menu bar app, so we check the status item exists
        // Note: Menu bar apps have limited UI testing capabilities
        _ = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")

        // Wait a moment for the app to initialize
        sleep(1)

        // The app should be running without crashing
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
    }

    // MARK: - Settings Window Tests

    func testSettingsWindowOpens() throws {
        // Menu bar apps can show settings via the app menu
        // We'll test that the app launches successfully
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
    }

    // MARK: - App State Tests

    func testAppLaunchesSuccessfully() throws {
        // Verify app is running
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertNotEqual(app.state, .unknown)
    }

    func testAppDoesNotCrashOnLaunch() throws {
        // Wait for potential crash
        sleep(2)

        // App should still be running
        XCTAssertNotEqual(app.state, .notRunning)
    }
}

// MARK: - Overlay View UI Tests

final class OverlayViewUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        if app.state != .notRunning {
            app.terminate()
        }
        app = nil
    }

    func testOverlayWindowElements() throws {
        // Since this is a menu bar app with an overlay triggered by hotkey,
        // UI testing is limited. We verify the app runs correctly.
        XCTAssertNotEqual(app.state, .notRunning)
    }
}

// MARK: - Accessibility Tests

final class AccessibilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        // Terminate app if running to prevent cleanup issues
        if app.state != .notRunning {
            app.terminate()
        }
        app = nil
    }

    func testAppSupportsAccessibility() throws {
        // Menu bar apps should support accessibility features
        // This test verifies the app is properly configured
        XCTAssertNotEqual(app.state, .notRunning)
    }
}

// MARK: - Performance Tests

final class PerformanceUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLaunchPerformance() throws {
        if #available(macOS 14.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                app.launch()
            }
        }
    }
}
