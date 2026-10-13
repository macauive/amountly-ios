import XCTest
import UIKit
@testable import alpha

@MainActor
final class CaptureLiveTests: XCTestCase {
    private func credentials() throws -> (String,String) {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_CAPTURE_LIVE_TESTING"] == "1", "Explicit synthetic capture opt-in required.")
        let email = try XCTUnwrap(env["AMOUNTLY_AI_QA_EMAIL"]), password = try XCTUnwrap(env["AMOUNTLY_AI_QA_PASSWORD"])
        guard email.hasPrefix("ios-freelancer-qa-"), email.hasSuffix("@amountly.app") else { throw PlatformError.input }
        guard UUID(uuidString: env["AMOUNTLY_FREELANCER_QA_ID"] ?? "") != nil else { throw PlatformError.input }
        return (email,password)
    }
    private func original() throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 400)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0,y: 0,width: 700,height: 400))
            ("SYNTHETIC RESUMABLE QA\n2026-10-13\nPaper USD 12.50" as NSString).draw(in: CGRect(x: 20,y: 20,width: 660,height: 360), withAttributes: [.font:UIFont.systemFont(ofSize: 35),.foregroundColor:UIColor.black])
        }
        return try PrivateDocument.write(try XCTUnwrap(image.pngData()), extension: "png", prefix: "receipt")
    }
    private func payload() -> CapturePayload {
        var fields = CaptureFields(); fields.amount = "12.50"; fields.currency = "USD"; fields.description = "Native synthetic resumable capture"; fields.merchant = "Native synthetic resumable"; fields.expense_date = "2026-10-13"
        return CapturePayload(method: .text, fields: fields, text: "Synthetic paper 12.50 USD", extraction: nil, extracted: true)
    }
    func testLiveCrossClientCaptureResumptionAndConflict() async throws {
        let (email,password) = try credentials()
        let a = AmountlyTransport(), b = AmountlyTransport()
        let authA = AmountlyAuthClient(transport: a), authB = AmountlyAuthClient(transport: b)
        let identity = try await authA.signIn(email: email, password: password)
        XCTAssertEqual(identity.user.id.uuidString.lowercased(), ProcessInfo.processInfo.environment["AMOUNTLY_FREELANCER_QA_ID"]?.lowercased())
        _ = try await authB.signIn(email: email, password: password)
        let first = CaptureDraftService(transport: a, authenticate: { _ = try await authA.session })
        let second = CaptureDraftService(transport: b, authenticate: { _ = try await authB.session })
        var saved: CaptureDraft?
        let file = try original()
        do {
            let id = UUID()
            saved = try await first.keep(id: id, revision: 0, payload: payload(), file: file, originalName: "synthetic-receipt.png")
            // Repeat the identical request to recover a lost success response.
            let repeated = try await first.keep(id: id, revision: 0, payload: payload(), file: file, originalName: "synthetic-receipt.png")
            XCTAssertEqual(repeated.revision, 1)
            let rows = try await second.list(), restored = try XCTUnwrap(rows.first { $0.id == id })
            XCTAssertEqual(restored.payload.fields.amount, "12.50")
            let download = try await second.original(restored)
            let url = try XCTUnwrap(download)
            XCTAssertEqual(try Data(contentsOf: file), try Data(contentsOf: url))
            try? FileManager.default.removeItem(at: url)
            var next = payload(); next.fields.amount = "13.50"
            saved = try await second.keep(id: id, revision: 1, payload: next, file: file, originalName: "synthetic-receipt.png")
            do { try await first.discard(restored); XCTFail("Stale revision discarded a changed capture") } catch { XCTAssertTrue(error is CaptureError) }
            if let saved { try await second.discard(saved) }
            let after = try await first.list(); XCTAssertFalse(after.contains { $0.id == id })
            try await authA.signOut(); try await authB.signOut()
        } catch {
            if let saved { try? await second.discard(saved) }
            try? await authA.signOut(); try? await authB.signOut()
            XCTFail("Synthetic cross-client capture failed. Check private diagnostics.")
        }
        try? FileManager.default.removeItem(at: file)
    }
    func testPrepareCaptureUI() async throws {
        let (email,password) = try credentials()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AMOUNTLY_CAPTURE_QA_UI"] == "prepare", "Explicit UI preparation only.")
        try await AuthService.shared.signInWithPassword(email: email, password: password)
        let identity = try await SupabaseClientManager.shared.client.auth.session
        guard identity.user.id.uuidString.lowercased() == ProcessInfo.processInfo.environment["AMOUNTLY_FREELANCER_QA_ID"]?.lowercased() else { throw PlatformError.denied }
        let file = try original(), draft = try await CaptureDraftService().keep(id: UUID(), revision: 0, payload: payload(), file: file, originalName: "synthetic-receipt.png")
        try? FileManager.default.removeItem(at: file)
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try JSONEncoder().encode(draft).write(to: documents.appendingPathComponent("qa-capture-ui.json"), options: [.atomic,.completeFileProtection])
    }
    func testCleanupCaptureUI() async throws {
        _ = try credentials()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AMOUNTLY_CAPTURE_QA_UI"] == "cleanup", "Explicit UI cleanup only.")
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let url = documents.appendingPathComponent("qa-capture-ui.json")
        let draft = try JSONDecoder().decode(CaptureDraft.self, from: Data(contentsOf: url))
        let captures = try await CaptureDraftService().list()
        if ProcessInfo.processInfo.environment["AMOUNTLY_CAPTURE_UI_DISCARDED"] == "1" {
            XCTAssertFalse(captures.contains { $0.id == draft.id }, "Native discard must remove the private draft.")
            let records = try await ExpenseRepository().fetchExpenses()
            XCTAssertFalse(records.contains { $0.id.lowercased() == draft.id.uuidString.lowercased() }, "Keep/discard must not create a financial record.")
        }
        if ProcessInfo.processInfo.environment["AMOUNTLY_CAPTURE_UI_SAVED"] == "1" {
            XCTAssertFalse(captures.contains { $0.id == draft.id })
            let records = try await ExpenseRepository().fetchExpenses().filter { $0.id.lowercased() == draft.id.uuidString.lowercased() }
            XCTAssertEqual(records.count, 1)
            let expense = try XCTUnwrap(records.first)
            XCTAssertEqual(expense.amount, 12.50); XCTAssertEqual(expense.currency, "USD")
            XCTAssertEqual(RecordCoding.day(expense.expenseDate), "2026-10-13")
            XCTAssertEqual(expense.status, .draft); XCTAssertNil(expense.reviewedAt)
            let original = try await ReceiptStorage().signedURL(for: expense)
            let expected = try self.original()
            XCTAssertEqual(try Data(contentsOf: original), try Data(contentsOf: expected))
            try? FileManager.default.removeItem(at: original); try? FileManager.default.removeItem(at: expected)
        }
        if let current = captures.first(where: { $0.id == draft.id }) { try await CaptureDraftService().discard(current) }
        try FileManager.default.removeItem(at: url)
        try await AuthService.shared.signOut(); PrivateDocument.removeAll()
    }
}
