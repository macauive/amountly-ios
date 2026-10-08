import XCTest
import UIKit

// Opt-in UI verification against disposable loopback accounts. No hosted login,
// model call, payment, message or production permission change is performed.
@MainActor
final class ReceiptWorkflowUITests: XCTestCase {
    private var fixture: [String: Any] = [:]
    private var actor: [String: String] = [:]
    private var token = ""
    private let app = XCUIApplication(bundleIdentifier: "macaulay.alpha")

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_LOCAL_UI_TESTING"] == "1", "Explicit local UI-test opt-in required.")
        let raw = try XCTUnwrap(env["AMOUNTLY_TEST_FIXTURES"])
        fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        guard fixture["url"] as? String == "http://127.0.0.1:54321" else { throw TestFailure.configuration }
        let actors = try XCTUnwrap(fixture["actors"] as? [String: [String: Any]])
        let profile = try XCTUnwrap(actors["freelancer"])
        for key in ["id", "email", "password"] { actor[key] = try XCTUnwrap(profile[key] as? String) }
    }

    private enum TestFailure: Error { case configuration, response, element }
    private func request(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard path.hasPrefix("/auth/v1/") || path.hasPrefix("/rest/v1/") else { throw TestFailure.configuration }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:54321" + path)!)
        request.setValue(try XCTUnwrap(fixture["anonKey"] as? String), forHTTPHeaderField: "apikey")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw TestFailure.response }
        return data
    }
    private func saved(_ description: String) async throws -> [String: Any] {
        var query = URLComponents(); query.path = "/rest/v1/expenses"
        query.queryItems = [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "user_id", value: "eq." + (try XCTUnwrap(actor["id"]))), URLQueryItem(name: "description", value: "eq." + description)]
        let data = try await request(try XCTUnwrap(query.string))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rows.count, 1, "The real form must persist one expense, without duplicate writes.")
        return try XCTUnwrap(rows.first)
    }
    private func require(_ element: XCUIElement, timeout: TimeInterval = 10) throws {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Expected UI element: " + element.identifier)
            throw TestFailure.element
        }
    }
    private func replace(_ field: XCUIElement, with value: String) throws {
        try require(field, timeout: 5); field.tap()
        if let old = field.value as? String, old != field.placeholderValue {
            if !old.isEmpty { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "Replacing a right-aligned amount must replace its whole value.")
    }
    private func waitForFormToClose() throws {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["expense.save"])
        guard XCTWaiter.wait(for: [closed], timeout: 15) == .completed else {
            let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Synthetic form save failure"; screen.lifetime = .keepAlways; add(screen)
            XCTFail("The real expense form did not finish saving.")
            throw TestFailure.element
        }
    }
    private func openSavedReceipt(reviewed: Bool = false) throws {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI Receipt Shop")).firstMatch
        try require(row)
        let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", reviewed ? "Draft, Reviewed" : "Draft, Needs review"), object: row)
        guard XCTWaiter.wait(for: [fresh], timeout: 10) == .completed else { throw TestFailure.element }
        row.tap()
    }

    func testReceiptPickerPreviewSaveReviewAndEdit() async throws {
        let login = try await request("/auth/v1/token?grant_type=password", body: ["email": try XCTUnwrap(actor["email"]), "password": try XCTUnwrap(actor["password"])])
        token = try XCTUnwrap((JSONSerialization.jsonObject(with: login) as? [String: Any])?["access_token"] as? String)
        app.launchEnvironment = ["AMOUNTLY_LOCAL_TESTING": "1", "AMOUNTLY_LOCAL_URL": "http://127.0.0.1:54331", "AMOUNTLY_LOCAL_ANON_KEY": try XCTUnwrap(fixture["anonKey"] as? String), "AMOUNTLY_XCTEST": "0"]
        app.launch()
        try require(app.buttons["Quick Actions"])
        app.buttons["Quick Actions"].tap(); app.buttons["Upload a receipt"].tap()

        let browse = app.buttons["Browse"].firstMatch
        try require(browse); browse.tap()
        let location = app.cells.matching(NSPredicate(format: "label == %@", "On My iPhone")).firstMatch
        if location.waitForExistence(timeout: 3) { location.tap() }
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "qa-synthetic-receipt")).firstMatch
        try require(file); file.tap()
        let preview = app.buttons["expense.receipt.preview"]
        try require(preview); preview.tap()
        let canvas = app.otherElements["Image canvas"].firstMatch
        try require(canvas)
        let original = XCTAttachment(screenshot: app.screenshot()); original.name = "Synthetic receipt in Quick Look"; original.lifetime = .keepAlways; add(original)
        canvas.tap()
        let done = app.buttons["close"].firstMatch
        try require(done); done.tap()
        try require(preview, timeout: 5)

        let description = "Synthetic UI receipt " + UUID().uuidString
        app.swipeUp()
        try replace(app.textFields["expense.description"], with: description)
        try replace(app.textFields["expense.amount"], with: "10.80")
        try replace(app.textFields["expense.merchant"], with: "UI Receipt Shop")
        app.buttons["expense.save"].tap()
        try waitForFormToClose()
        try require(app.buttons["Quick Actions"])
        var record = try await saved(description)
        XCTAssertEqual(record["amount"] as? Double, 10.80)
        XCTAssertEqual(record["status"] as? String, "DRAFT")
        XCTAssertNotNil(record["receipt_path"] as? String)

        try openSavedReceipt(); app.buttons["Mark reviewed"].tap(); app.buttons["Confirm"].tap()
        try require(app.buttons["Quick Actions"])
        record = try await saved(description); XCTAssertTrue(record["reviewed_at"] is String)
        try openSavedReceipt(reviewed: true); app.buttons["Clear review"].tap(); app.buttons["Confirm"].tap()
        try require(app.buttons["Quick Actions"])
        record = try await saved(description); XCTAssertTrue(record["reviewed_at"] is NSNull)
        try openSavedReceipt(); app.buttons["Mark reviewed"].tap(); app.buttons["Confirm"].tap()
        try require(app.buttons["Quick Actions"])
        try openSavedReceipt(reviewed: true); app.buttons["Edit expense"].tap(); app.swipeUp()
        try replace(app.textFields["expense.amount"], with: "12.80"); app.buttons["expense.save"].tap()
        try waitForFormToClose()
        try require(app.buttons["Quick Actions"])
        record = try await saved(description)
        XCTAssertEqual(record["amount"] as? Double, 12.80)
        XCTAssertTrue(record["reviewed_at"] is NSNull, "Editing through the real form must clear the saved review marker.")
        app.terminate()
        _ = try await request("/auth/v1/logout?scope=local", body: [:])
    }
}
