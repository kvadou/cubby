import XCTest

/// Signs in as the local demo parent (api/db/seeds/demo_users.rb) against the API on localhost:3000,
/// walks the tabs, and attaches a screenshot of each. Needs `docker compose up` with seeded data.
final class ParentFlowTests: XCTestCase {
    private let email = "parent@littleoaks.test"
    private let password = "littleoaks-demo" // the public, fictional local demo value

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testParentSignsInAndSeesEachTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSession"]
        if let size = ProcessInfo.processInfo.environment["CUBBY_UI_TEXT_SIZE"] {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()

        let field = app.textFields["email"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        snap(app, "1-sign-in")
        field.tap()
        field.typeText(email)
        let secure = app.secureTextFields["password"]
        secure.tap()
        secure.typeText(password)
        app.buttons["signIn"].tap()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        dismissSavePasswordPrompt(app)
        XCTAssertTrue(app.staticTexts["Meryl"].waitForExistence(timeout: 10) || app.staticTexts["MERYL"].exists)
        snap(app, "2-today")

        app.tabBars.buttons["Messages"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Cubby"].waitForExistence(timeout: 10))
        snap(app, "3-messages")
        app.staticTexts["Welcome to Cubby"].tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        snap(app, "4-message")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Billing"].tap()
        XCTAssertTrue(app.staticTexts["Due"].waitForExistence(timeout: 10) || app.staticTexts["DUE"].exists)
        snap(app, "5-billing")

        app.tabBars.buttons["Today"].tap()
        let signOut = app.buttons["signOut"]
        for _ in 0..<8 where !signOut.isHittable { app.swipeUp() }
        signOut.tap()
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 10))
    }

    /// iOS offers to save the password after a sign-in; that sheet belongs to the system, not Cubby.
    @MainActor
    private func dismissSavePasswordPrompt(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for owner in [app, springboard] where owner.buttons["Not Now"].waitForExistence(timeout: 4) {
            owner.buttons["Not Now"].tap()
            return
        }
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
