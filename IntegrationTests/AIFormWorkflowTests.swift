import XCTest
import SwiftUI
@testable import alpha

// Test-only responses. The real forms and local repositories remain in use.
final class AIFormProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var kind = "expense"
    nonisolated(unsafe) private static var mode = "Success"
    nonisolated(unsafe) private static var failures = 0
    nonisolated(unsafe) private static var cancellations = 0
    private let stateLock = NSLock()
    private var pending: DispatchWorkItem?
    private var completed = false

    static func configure(kind: String, mode: String) {
        lock.lock(); defer { lock.unlock() }
        self.kind = kind; self.mode = mode
    }
    static var evidence: (Int, Int) {
        lock.lock(); defer { lock.unlock() }
        return (failures, cancellations)
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.absoluteString == "https://amountly.app/api/ai" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let kind = Self.kind, mode = Self.mode
        if mode == "Fail once" { Self.mode = "Success"; Self.failures += 1 }
        Self.lock.unlock()
        let json: String
        switch kind {
        case "expense":
            json = #"{"amount":"37.45","merchant":"Synthetic Stationery","description":"AI form verification supplies","expense_date":"2026-09-30","category":"OFFICE_SUPPLIES","confidence":"high","reason":"Synthetic test response"}"#
        case "contact":
            json = #"{"name":"AI Form Verification Studio","contact_name":"Demo Person","email":"demo@example.com","phone":"","address":"","city":"","state":"","zip_code":"","notes":"Synthetic form verification","reason":"Synthetic test response"}"#
        default:
            json = #"{"description":"AI form verification design","quantity":2,"rate":75,"amount":150,"reason":"Synthetic test response"}"#
        }
        let body = Data(("{\"result\":" + json + ",\"safety\":{\"redacted\":false}}").utf8)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            guard self.pending != nil else { self.stateLock.unlock(); return }
            self.completed = true
            self.stateLock.unlock()
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: mode == "Fail once" ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        stateLock.lock(); pending = work; stateLock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + (mode == "Slow" ? 30 : 0.2), execute: work)
    }
    override func stopLoading() {
        stateLock.lock()
        let cancelled = !completed && pending != nil
        pending?.cancel(); pending = nil
        stateLock.unlock()
        if cancelled { Self.lock.lock(); Self.cancellations += 1; Self.lock.unlock() }
    }
}

@MainActor
private struct AIFormInspection: View {
    let client: AIClient
    let finish: () -> Void
    @State private var mode = "Fail once"
    @State private var expense = false
    @State private var contact = false
    @State private var invoice = false
    @State private var saves = 0
    var body: some View {
        NavigationStack {
            Form {
                Picker("AI response", selection: $mode) {
                    ForEach(["Fail once", "Slow", "Success"], id: \.self) { Text($0) }
                }
                Button("Open expense form") { AIFormProtocol.configure(kind: "expense", mode: mode); expense = true }
                Button("Open contact form") { AIFormProtocol.configure(kind: "contact", mode: mode); contact = true }
                Button("Open invoice form") { AIFormProtocol.configure(kind: "line", mode: mode); invoice = true }
                Text("Saved forms: \(saves)")
                Button("Finish verification", action: finish)
            }.navigationTitle("Local AI form checks")
        }
        .sheet(isPresented: $expense) { ExpenseFormSheet(isPresented: $expense) { saves += 1 } }
        .sheet(isPresented: $contact) { ContactFormSheet(isPresented: $contact) { saves += 1 } }
        .sheet(isPresented: $invoice) { CreateInvoiceSheet(isPresented: $invoice) }
        .environment(\.aiCaptureClient, client)
    }
}

@MainActor
final class AIFormWorkflowTests: XCTestCase {
    func testInspectActualFormsWithLocalPersistence() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_AI_FORM_INSPECTION"] == "1", "Opt-in computer-use inspection.")
        guard env["AMOUNTLY_LOCAL_TESTING"] == "1", env["AMOUNTLY_LOCAL_URL"] == "http://127.0.0.1:54331",
              let raw = env["AMOUNTLY_TEST_FIXTURES"] else { throw RecordError.invalid }
        let fixtures = try JSONDecoder().decode(WorkflowIntegrationTests.Fixtures.self, from: Data(raw.utf8))
        let actor = try XCTUnwrap(fixtures.actors["owner"])
        let (user, organization) = try await AuthService.shared.login(email: actor.email, password: actor.password)
        let state = AppState(); state.login(user: user, organization: organization)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AIFormProtocol.self]
        let client = AIClient(configuration: config) { AISession(userID: "synthetic", token: "synthetic_token_000000000000") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let previous = window.rootViewController
        let finished = expectation(description: "Computer-use form verification finished")
        window.rootViewController = UIHostingController(rootView: AIFormInspection(client: client, finish: { finished.fulfill() }).environmentObject(state))
        window.makeKeyAndVisible()
        defer { window.rootViewController = previous }
        await fulfillment(of: [finished], timeout: 900)
        let expenses = try await ExpenseRepository().fetchExpenses()
        let expense = try XCTUnwrap(expenses.first { $0.description == "AI form verification supplies" })
        XCTAssertEqual(expense.amount, 37.45)
        XCTAssertEqual(expense.merchant, "Synthetic Stationery")
        XCTAssertEqual(expense.category.rawValue, "OFFICE_SUPPLIES")
        let contacts = try await ClientRepository().fetchClients()
        let contact = try XCTUnwrap(contacts.first { $0.name == "AI Form Verification Studio" })
        XCTAssertEqual(contact.contactName, "Demo Person")
        XCTAssertEqual(contact.email, "demo@example.com")
        let invoices = try await InvoiceRepository().fetchInvoices()
        let invoice = try XCTUnwrap(invoices.first { $0.total == 150 && $0.clientId == contact.id })
        XCTAssertEqual(invoice.status, .draft)
        XCTAssertEqual(AIFormProtocol.evidence.0, 1)
        XCTAssertGreaterThanOrEqual(AIFormProtocol.evidence.1, 1)
    }
}
