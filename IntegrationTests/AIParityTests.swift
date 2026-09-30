import XCTest
import Supabase
import SwiftUI
@testable import alpha

@MainActor
final class AIParityTests: XCTestCase {
    func testTimeFormsKeepExactMinutesAndExplicitRange() throws {
        let value = AITime(date: "2026-09-30", start_time: "13:00", end_time: "14:47", notes: "Design", duration_minutes: 107, reason: "Explicit range")
        try value.validate()
        let quick = QuickEntryViewModel(); quick.applySmartTime(value)
        XCTAssertEqual(quick.totalDurationMinutes, 107)
        XCTAssertEqual(try XCTUnwrap(quick.suggestedInterval).end.timeIntervalSince(try XCTUnwrap(quick.suggestedInterval).start), 107 * 60)
        quick.durationMinutes = 0; XCTAssertNil(quick.suggestedInterval)
        let form = TimeEntryFormViewModel(); form.applySmartTime(value)
        XCTAssertEqual(form.durationMinutes, 107)
        XCTAssertFalse(form.endsNextDay)
        form.applySmartTime(AITime(date: "2026-09-30", start_time: "", end_time: "", notes: "", duration_minutes: 1440, reason: "Full day"))
        XCTAssertEqual(form.durationMinutes, 1440); XCTAssertTrue(form.endsNextDay)
        form.applySmartTime(AITime(date: "", start_time: "", end_time: "", notes: "", duration_minutes: 0, reason: "No duration"))
        XCTAssertEqual(form.durationMinutes, 0); XCTAssertFalse(form.canSave)
    }
    func testDashboardUsesBoundedAllowlistedSummaryWithoutReceiptLinks() throws {
        let input = AIDashboardInput.summary(account: .business, query: "What needs review?", currency: "USD", invoices: [.preview], expenses: [.preview], bills: [], vendorBills: [], time: [], routes: [.dashboard, .expenses])
        let data = try JSONEncoder().encode(input)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertLessThanOrEqual(text.utf16.count, 11000)
        XCTAssertFalse(text.contains("receiptUrl")); XCTAssertFalse(text.contains("receipt.pdf")); XCTAssertFalse(text.contains("userId"))
        XCTAssertEqual(input.candidateHrefs, [.dashboard, .expenses])
    }
    func testReceiptOCRProvidesSourceTextWithoutGuessingAmounts() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 240)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 240))
            let lines = "Demo Shop\nTOTAL $1,234.56\n2026-09-30"
            (lines as NSString).draw(in: CGRect(x: 25, y: 25, width: 750, height: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
        }
        let text = try await ReceiptScanner.recognize(XCTUnwrap(image.cgImage))
        XCTAssertTrue(text.contains("Demo Shop"))
        XCTAssertTrue(text.contains("1,234.56"))
    }
    func testLiveSharedAIService() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_AI_LIVE_TESTING"] == "1", "Live synthetic requests require explicit opt-in and a QA login.")
        let email = try XCTUnwrap(env["AMOUNTLY_AI_QA_EMAIL"])
        let password = try XCTUnwrap(env["AMOUNTLY_AI_QA_PASSWORD"])
        // Separate SDK storage prevents overwriting the user's native app session.
        let config = SupabaseConfig.shared
        let supabase = SupabaseClient(supabaseURL: config.projectURL, supabaseKey: config.anonKey,
            options: .init(auth: .init(storageKey: "amountly-ai-qa-verification", autoRefreshToken: false)))
        do { try await supabase.auth.signIn(email: email, password: password) }
        catch { XCTFail("QA sign-in failed; no AI request was sent."); return }
        let api = AIClient { let session = try await supabase.auth.session; return AISession(userID: session.user.id.uuidString, token: session.accessToken) }
        var failures: [String] = []
        func verify<R: AIResult, P: Encodable>(_ task: AITask, _ payload: P, _ type: R.Type, check: (R) -> Bool = { _ in true }) async {
            do {
                let value: R = try await api.run(task, payload: payload)
                if !check(value) { failures.append(task.rawValue + ": unexpected synthetic result") }
                else { print("AI LIVE PASS: " + task.rawValue) }
            } catch { failures.append(task.rawValue + ": " + AIError.message(error)) }
        }
        await verify(.expense, "Merchant: Demo Shop. Office paper. Total: $1,234.56. Date: 2026-09-30.", AIExpense.self) { $0.amount == "1234.56" }
        await verify(.receipt, "Demo Shop\nPaper $10.00\nTax $0.80\nTOTAL $10.80\nTOTAL SAVINGS $2.00\n2026-09-30", AIReceipt.self) { $0.amount == "10.80" }
        await verify(.line, "Design work: 2 hours at $75 per hour. Total $150.", AILine.self) { $0.amount == 150 && $0.quantity == 2 }
        await verify(.time, "Design work for 1 hour 30 minutes on 2026-09-30.", AITime.self) { $0.minutes == 90 }
        await verify(.time, "Design work from 1 to 3 pm on 2026-09-30.", AITime.self) { $0.minutes == 120 }
        await verify(.contact, "Contact: Alex Example\nCompany: Demo Studio\nEmail: alex@example.invalid", AIContact.self) { $0.name == "Demo Studio" && $0.contact_name == "Alex Example" && $0.email == "alex@example.invalid" }
        await verify(.reminder, AIReminderInput(invoice_number: "QA-SYNTHETIC-1", total: 150, currency: "USD", due_date: "2026-09-29", status: "SENT", client: .init(name: "Demo Studio", contact_name: nil)), AIReminder.self) { !$0.subject.isEmpty && !$0.body.isEmpty }
        await verify(.dashboard, AIDashboardInput(accountType: "freelancer", searchQuery: "Which invoice needs review?", bills: [], expenses: [], workData: .init(invoices: [.init(id: "00000000-0000-4000-8000-000000000001", label: "QA-SYNTHETIC-1", amount: 150, date: "2026-09-29", status: "OVERDUE")], expenses: [], timeEntries: [], vendorBills: []), candidateHrefs: [.dashboard, .invoices]), AIDashboard.self) { !$0.monthlySummary.headline.isEmpty }
        try? await supabase.auth.signOut(scope: .local)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
