import XCTest
@testable import AmountlyAI
import Foundation

final class MockAIProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class AIContractTests: XCTestCase {
    let expense: [String: Any] = ["amount": "1234.56", "merchant": "Demo Shop", "description": "Paper", "expense_date": "2026-09-30", "category": "OFFICE_SUPPLIES", "confidence": "high", "reason": "Receipt total"]
    let line: [String: Any] = ["description": "Design", "quantity": 2, "rate": 75, "amount": 150, "reason": "Two hours"]
    let contact: [String: Any] = ["name": "Demo Studio", "contact_name": "Alex Example", "email": "alex@example.invalid", "phone": "", "address": "", "city": "", "state": "", "zip_code": "", "notes": "", "reason": "Labeled contact"]
    func envelope(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: ["result": value, "safety": ["redacted": false]]) }
    func decode<R: AIResult>(_ type: R.Type, _ object: [String: Any]) throws -> R { try AIValidation.decode(type, data: envelope(object)) }
    func client(identity: (() async throws -> AISession)? = nil) -> AIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockAIProtocol.self]
        return AIClient(configuration: config, identity: identity ?? { AISession(userID: "synthetic", token: "synthetic_token_000000000000") })
    }
    func testAllSevenTaskResponses() throws {
        XCTAssertEqual(try decode(AIExpense.self, expense).amount, "1234.56")
        var receipt = expense; receipt["notes"] = "Tax included"; receipt["summary"] = "Paper receipt"
        XCTAssertEqual(try decode(AIReceipt.self, receipt).expense.merchant, "Demo Shop")
        XCTAssertEqual(try decode(AILine.self, line).amount, 150)
        XCTAssertEqual(try decode(AIContact.self, contact).contact_name, "Alex Example")
        XCTAssertEqual(try decode(AITime.self, ["date": "2026-09-30", "start_time": "13:00", "end_time": "15:00", "duration_minutes": 120, "notes": "Design", "reason": "Explicit time range"]).minutes, 120)
        XCTAssertEqual(try decode(AIReminder.self, ["tone": "friendly", "subject": "Reminder", "body": "Invoice is due.", "reason": "Unpaid"]).subject, "Reminder")
        XCTAssertEqual(try decode(AIDashboard.self, ["nextSteps": [], "monthlySummary": ["headline": "Review", "body": "No records", "highlights": []], "searchResults": []]).nextSteps.count, 0)
    }
    func testCaptureRejectsInvalidFinancialDataAndUnknownFields() throws {
        for invalid in ["$42.50", "-1", "1,234.56", "NaN", "9999999999999999999999999"] {
            var value = expense; value["amount"] = invalid; XCTAssertThrowsError(try decode(AIExpense.self, value))
        }
        for invalid in ["2026-02-31", "2026-13-01", "tomorrow"] {
            var value = expense; value["expense_date"] = invalid; XCTAssertThrowsError(try decode(AIExpense.self, value))
        }
        var value = expense; value["category"] = "INVENTED"; XCTAssertThrowsError(try decode(AIExpense.self, value))
        value = expense; value["script"] = "unexpected"; XCTAssertThrowsError(try decode(AIExpense.self, value))
        value = expense; value["reason"] = String(repeating: "x", count: 2001); XCTAssertThrowsError(try decode(AIExpense.self, value))
        var badLine = line; badLine["amount"] = 1; XCTAssertThrowsError(try decode(AILine.self, badLine))
        badLine = line; badLine["quantity"] = -1; XCTAssertThrowsError(try decode(AILine.self, badLine))
    }
    func testDurationIsExactBoundedAndNeverInvented() throws {
        func time(_ duration: Any, start: String = "", end: String = "") throws -> AITime {
            try decode(AITime.self, ["date": "2026-09-30", "start_time": start, "end_time": end, "duration_minutes": duration, "notes": "Design", "reason": "Extracted"])
        }
        XCTAssertEqual(try time(90).minutes, 90)
        XCTAssertEqual(try time(47).minutes, 47)
        XCTAssertNil(try time(0).interval(referenceDate: Date()))
        XCTAssertEqual(try time(0, start: "13:00", end: "15:00").minutes, 120)
        for invalid: Any in [-1, 1441, 90.5, "9999999999999999999999999999999999", 1e100] { XCTAssertThrowsError(try time(invalid)) }
        XCTAssertThrowsError(try time(60, start: "13:00", end: "15:00"))
        XCTAssertThrowsError(try time(120, start: "25:00", end: "27:00"))
        let interval = try XCTUnwrap(time(1440).interval(referenceDate: Date()))
        XCTAssertEqual(interval.1.timeIntervalSince(interval.0), 86400)
    }
    func testExplicitTimePreservesLocalClockAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let value = AITime(date: "2026-03-08", start_time: "13:00", end_time: "15:00", notes: "Design", duration_minutes: 120, reason: "Range")
        let result = try XCTUnwrap(value.interval(referenceDate: Date(), calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: result.0), 13)
        XCTAssertEqual(calendar.component(.hour, from: result.1), 15)
    }
    func testRequestPolicyRejectsUnexpectedFieldsAndUnboundedRecords() throws {
        XCTAssertThrowsError(try AIRequestPolicy.validate(.line, payload: ["text": "Design"]))
        XCTAssertThrowsError(try AIRequestPolicy.validate(.reminder, payload: ["invoice_number": "QA", "total": -1, "currency": "USD", "due_date": "2026-09-30", "status": "SENT", "client": [:]]))
        XCTAssertThrowsError(try AIRequestPolicy.validate(.dashboard, payload: ["accountType": "business", "searchQuery": "", "bills": [], "expenses": [], "candidateHrefs": ["https://evil.invalid"], "workData": ["invoices": [], "expenses": [], "timeEntries": [], "vendorBills": []]]))
        let summary: [String: Any] = ["id": "00000000-0000-4000-8000-000000000001", "label": "Paper", "date": "2026-09-30", "status": "DRAFT", "receipt_url": "private"]
        XCTAssertThrowsError(try AIRequestPolicy.validate(.dashboard, payload: ["accountType": "business", "searchQuery": "", "bills": [], "expenses": [summary], "candidateHrefs": ["/expenses"], "workData": ["invoices": [], "expenses": [], "timeEntries": [], "vendorBills": []]]))
    }
    func testDashboardRejectsExternalNavigationAndLargeArrays() throws {
        var result: [String: Any] = ["nextSteps": [["id": "1", "title": "Review", "detail": "Details", "href": "https://evil.invalid", "priority": "high"]], "monthlySummary": ["headline": "Review", "body": "Body", "highlights": []], "searchResults": []]
        XCTAssertThrowsError(try decode(AIDashboard.self, result))
        result["nextSteps"] = Array(repeating: ["id": "1", "title": "Review", "detail": "Details", "href": "/invoices", "priority": "high"], count: 13)
        XCTAssertThrowsError(try decode(AIDashboard.self, result))
    }
    func testAuthenticatedWireRequestAndResponse() async throws {
        let response = try envelope(expense)
        MockAIProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://amountly.app/api/ai")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic_token_000000000000")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (200, response)
        }
        let value: AIExpense = try await client().run(.expense, payload: "Demo Shop total $1,234.56")
        XCTAssertEqual(value.amount, "1234.56")
    }
    func testServerErrorsAreSafeAndNeverAutoRetried() async throws {
        for (status, expected): (Int, AIError) in [(400,.input),(401,.signIn),(403,.denied),(413,.input),(429,.limit),(502,.unavailable),(503,.unavailable)] {
            var calls = 0
            MockAIProtocol.handler = { _ in calls += 1; return (status, Data("private provider error".utf8)) }
            do { let _: AILine = try await client().run(.line, payload: "two hours"); XCTFail() }
            catch { XCTAssertEqual(error as? AIError, expected); XCTAssertFalse(error.localizedDescription.contains("private")) }
            XCTAssertEqual(calls, 1)
        }
    }
    func testInvalidInputAndMissingSessionNeverReachNetwork() async throws {
        var calls = 0
        MockAIProtocol.handler = { _ in calls += 1; return (500, Data()) }
        for text in [" ", String(repeating: "x", count: 12001), String(repeating: "😀", count: 6001)] {
            do { let _: AILine = try await client().run(.line, payload: text); XCTFail() }
            catch { XCTAssertEqual(error as? AIError, .input) }
        }
        do { let _: AILine = try await client(identity: { throw AIError.signIn }).run(.line, payload: "Design"); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .signIn) }
        XCTAssertEqual(calls, 0)
    }
    func testResponseAfterAccountChangeIsDiscarded() async throws {
        let response = try envelope(expense)
        MockAIProtocol.handler = { _ in (200, response) }
        var identities = 0
        let api = client { identities += 1; return AISession(userID: identities == 1 ? "first" : "second", token: "synthetic_token_000000000000") }
        do { let _: AIExpense = try await api.run(.expense, payload: "Paper $10"); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .signIn) }
    }
    func testOversizedResponseAndMalformedJSONAreRejected() async throws {
        for data in [Data(repeating: 32, count: 256001), Data("not JSON".utf8)] {
            MockAIProtocol.handler = { _ in (200, data) }
            do { let _: AIExpense = try await client().run(.expense, payload: "Paper $10"); XCTFail() }
            catch { XCTAssertEqual(error as? AIError, .response) }
        }
    }
    func testCancelledRequestCannotApply() async throws {
        MockAIProtocol.handler = { _ in XCTFail("Cancelled work reached network"); return (200, Data()) }
        let api = client()
        let task = Task { let _: AILine = try await api.run(.line, payload: "Design") }
        task.cancel()
        do { try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testRedirectDelegateNeverForwardsCredentials() {
        let delegate = AIRedirectGuard()
        let session = URLSession(configuration: .ephemeral)
        let request = URLRequest(url: URL(string: "https://evil.invalid")!)
        delegate.urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: HTTPURLResponse(url: AIClient.endpoint, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: request) { redirected in XCTAssertNil(redirected) }
        session.invalidateAndCancel()
    }
}
