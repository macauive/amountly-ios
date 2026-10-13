import XCTest

@MainActor
final class WebParityUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "macdigital.amountly")
    override func setUpWithError() throws { continueAfterFailure = false }
    private enum Failure: Error { case element }
    private func require(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 20) else { throw Failure.element }
    }
    private func reveal(_ element: XCUIElement, towardTop: Bool = false) throws {
        func scroll(up: Bool) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.65 : 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        for _ in 0..<10 {
            if element.waitForExistence(timeout: 1) {
                let frame = element.frame
                if element.isHittable, frame.minY > 150, frame.maxY < app.frame.maxY - 90 { return }
                if frame.height > 0, frame.minY < 150 { scroll(up: false); continue }
            }
            scroll(up: !towardTop)
        }
        throw Failure.element
    }
    func testKeepEditedCaptureCancelDiscardAndConfirmDiscard() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_CAPTURE_UI_TESTING"] == "1", "Explicit dedicated synthetic session required.")
        let id = try XCTUnwrap(env["AMOUNTLY_CAPTURE_QA_ID"])
        guard UUID(uuidString: id) != nil else { throw Failure.element }
        app.launchEnvironment = ["AMOUNTLY_XCTEST":"0"]
        app.launch()
        defer { app.terminate() }
        try reveal(app.buttons["Open Review Inbox"]); app.buttons["Open Review Inbox"].tap()
        let resume = app.buttons["capture.resume." + id.lowercased()]
        try reveal(resume); resume.tap()
        let amount = app.textFields["expense.amount"]
        try reveal(amount)
        expectation(for: NSPredicate(format: "value == %@", "12.50"), evaluatedWith: amount)
        waitForExpectations(timeout: 20)
        amount.tap()
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "13.50")
        XCTAssertEqual(amount.value as? String, "13.50", "Replace the entire right-aligned amount before keeping.")
        let keep = app.buttons["Keep for later"]
        try reveal(keep, towardTop: true); keep.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["expense.save"])
        waitForExpectations(timeout: 20)
        try reveal(resume); resume.tap()
        try reveal(amount)
        expectation(for: NSPredicate(format: "value == %@", "13.50"), evaluatedWith: amount)
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.buttons["expense.save"].isEnabled, "Keeping a proposal must not grant review acknowledgment.")
        app.buttons["Cancel"].tap()
        let discard = app.buttons["capture.discard." + id.lowercased()]
        try reveal(discard); discard.tap()
        try require(app.buttons["Discard capture"])
        app.buttons["Cancel"].tap()
        XCTAssertTrue(resume.exists, "Cancelling discard must preserve the capture.")
        discard.tap(); app.buttons["Discard capture"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: resume)
        waitForExpectations(timeout: 20)
    }
    func testResumeReviewedCaptureSaveAndFindExactOriginal() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_CAPTURE_UI_TESTING"] == "1", "Explicit dedicated synthetic session required.")
        let id = try XCTUnwrap(env["AMOUNTLY_CAPTURE_QA_ID"])
        guard UUID(uuidString: id) != nil else { throw Failure.element }
        app.launchEnvironment = ["AMOUNTLY_XCTEST":"0"]
        app.launch()
        try reveal(app.buttons["Open Review Inbox"]); app.buttons["Open Review Inbox"].tap()
        let resume = app.buttons["capture.resume." + id.lowercased()]
        try reveal(resume); resume.tap()
        let amount = app.textFields["expense.amount"]
        try reveal(amount)
        let restored = NSPredicate(format: "value == %@", "12.50")
        expectation(for: restored, evaluatedWith: amount)
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.buttons["expense.save"].isEnabled, "Restored extraction must require fresh acknowledgment.")
        let preview = app.buttons["expense.receipt.preview"]
        try reveal(preview); preview.tap()
        try require(app.otherElements["Image canvas"])
        app.otherElements["Image canvas"].tap()
        try require(app.buttons["close"]); app.buttons["close"].tap()
        let confirm = app.switches["I checked this draft and attachment against my receipt"]
        try reveal(confirm)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: confirm)
        waitForExpectations(timeout: 20)
        confirm.switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["expense.save"])
        waitForExpectations(timeout: 10)
        app.buttons["expense.save"].tap()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: app.buttons["expense.save"])
        waitForExpectations(timeout: 20)
        app.buttons["records.open"].tap()
        let search = app.textFields["Name, number or amount"]
        try require(search); search.tap(); search.typeText("Native synthetic resumable\n")
        let result = app.buttons["records.result.expenses." + id.lowercased()]
        try reveal(result); result.tap()
        try reveal(app.buttons["expense.original.view"]); app.buttons["expense.original.view"].tap()
        try require(app.descendants(matching: .any).matching(identifier: "receipt.original.page").firstMatch)
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Synthetic saved original review"; screen.lifetime = .keepAlways; add(screen)
        app.terminate()
    }
}
