import XCTest

// Explicitly prepared, dedicated synthetic freelancer session only. This test
// opens share destinations and cancels before saving or sending anything.
@MainActor
final class HostedShareUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "macaulay.alpha")
    private enum Failure: Error { case element }
    private func require(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 15) else { throw Failure.element }
    }
    private func reveal(_ element: XCUIElement) throws {
        // List rows enter the accessibility tree only as they scroll into view.
        for _ in 0..<8 {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            app.swipeUp()
        }
        guard element.isHittable else { throw Failure.element }
    }
    private func inspectFilesDestination() throws {
        let files = app.cells["Save to Files"].firstMatch
        try reveal(files); files.tap()
        try require(app.buttons["Save"].firstMatch)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Synthetic export Files destination"; screen.lifetime = .keepAlways; add(screen)
        // Files can restore a folder and show Browse instead of Cancel.
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() }
        let cancel = app.buttons["Cancel"].firstMatch
        try require(cancel); cancel.tap()
        let close = app.buttons["header.closeButton"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
    }
    func testHostedReceiptAndAccountantZIPSharing() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AMOUNTLY_SYNTHETIC_SHARE_TESTING"] == "1", "Dedicated hosted synthetic session must be prepared explicitly.")
        app.launchEnvironment = ["AMOUNTLY_XCTEST": "0"]
        app.launch()
        try require(app.buttons["Quick Actions"])
        let receipt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic Native Shop · ")).firstMatch
        try reveal(receipt); receipt.tap()
        let open = app.buttons["Open Receipt"]
        try reveal(open); open.tap()
        try inspectFilesDestination()
        let done = app.buttons["Done"].firstMatch
        try require(done); done.tap()
        let report = app.buttons["Review income and expenses for export"]
        try reveal(report); report.tap()
        let export = app.buttons["Export accountant packet"]
        try reveal(export); XCTAssertTrue(export.isEnabled); export.tap()
        let download = app.buttons["Download ZIP"]
        try require(download); XCTAssertTrue(download.isEnabled); download.tap()
        try inspectFilesDestination()
        app.terminate()
    }
}
