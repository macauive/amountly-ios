import XCTest

@MainActor
final class ReleaseReadinessUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "macdigital.amountly")
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchEnvironment = ["AMOUNTLY_XCTEST": "1", "AMOUNTLY_RELEASE_UI_TESTING": "1"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
    }
    override func tearDown() { app.terminate() }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSettingsHavePrivacySupportAndNoPlaceholderDestinations() {
        let privacy = app.buttons["Privacy Policy"]
        reveal(privacy)
        XCTAssertTrue(app.buttons["Terms of Use"].exists)
        XCTAssertTrue(app.buttons["Help and Support"].exists)
        reveal(app.buttons["settings.deleteAccount"])
        XCTAssertTrue(app.buttons["settings.deleteAccount"].exists)
        for label in ["Tax Estimates", "Tax Documents", "Connected Accounts", "API Settings", "Offline Data", "Notifications"] {
            XCTAssertFalse(app.buttons[label].exists)
        }
        capture("Amountly release settings")
    }
    func testAIConsentRequiresExplicitAllowAndCanBeWithdrawn() {
        let privacy = app.buttons["AI Privacy"]
        reveal(privacy); privacy.tap()
        let allow = app.buttons["ai.consent.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ai.consent.revoke"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "OpenAI")).firstMatch.exists)
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "OpenAI")).firstMatch.tap()
        XCTAssertTrue(allow.exists)
        XCTAssertFalse(app.buttons["ai.consent.revoke"].exists, "Reading the disclosure must not grant permission")
        capture("Optional AI before consent")
        allow.tap()
        let revoke = app.buttons["ai.consent.revoke"]
        XCTAssertTrue(revoke.waitForExistence(timeout: 5))
        revoke.tap()
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        let settings = app.buttons["AI Privacy"]
        reveal(settings); settings.tap()
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "Consent must not persist across app launches")
    }
    func testDeletionCanCancelAndThenSubmitWithThirtyDayWindow() {
        let deletion = app.buttons["settings.deleteAccount"]
        reveal(deletion); deletion.tap()
        let request = app.buttons["account.deletion.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "within 30 days")).firstMatch.exists)
        capture("Account deletion disclosure")
        request.tap(); app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["account.deletion.success"].exists)
        request.tap(); app.buttons["Request deletion"].tap()
        XCTAssertTrue(app.staticTexts["account.deletion.success"].waitForExistence(timeout: 10))
        capture("Synthetic account deletion confirmation")
    }
}
