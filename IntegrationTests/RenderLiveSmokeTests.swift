import XCTest
import Supabase
import UIKit
@testable import alpha

@MainActor
final class RenderLiveSmokeTests: XCTestCase {
    func testLiveFreelancerSetupReceiptAndPacket() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_SYNTHETIC_FREELANCER_TESTING"] == "1", "Dedicated synthetic QA opt-in required.")
        let email = try XCTUnwrap(env["AMOUNTLY_AI_QA_EMAIL"])
        let password = try XCTUnwrap(env["AMOUNTLY_AI_QA_PASSWORD"])
        let expectedID = try XCTUnwrap(env["AMOUNTLY_FREELANCER_QA_ID"])
        guard email.hasPrefix("ios-freelancer-qa-"), email.hasSuffix("@amountly.app"), UUID(uuidString: expectedID) != nil else { throw PlatformError.input }
        var stage = "synthetic sign-in"
        do {
            try await AuthService.shared.signInWithPassword(email: email, password: password)
            let session = try await SupabaseClientManager.shared.client.auth.session
            guard session.user.id.uuidString.lowercased() == expectedID.lowercased() else { throw PlatformError.denied }
            stage = "native freelancer onboarding"
            let user = try await AuthService.shared.createPersonalUser(name: "Synthetic iOS freelancer QA", accountType: .freelancer)
            XCTAssertTrue(user.canExportAccountantPacket)
            stage = "native private receipt upload"
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 550)).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 550))
                ("SYNTHETIC NATIVE SHOP\nQA RECEIPT\nDate: 2026-10-07\nOffice paper: USD 10.00\nSales tax: USD 0.80\nTOTAL PAID: USD 10.80" as NSString).draw(in: CGRect(x: 30, y: 30, width: 940, height: 490), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
            }
            let original = try XCTUnwrap(image.pngData())
            let source = try PrivateDocument.write(original, extension: "png", prefix: "receipt")
            defer { try? FileManager.default.removeItem(at: source) }
            let path = try await ReceiptStorage().upload(url: source)
            let repository = ExpenseRepository()
            stage = "native expense save and review"
            var expense = try await repository.createExpense(description: "Synthetic native hosted packet", amount: 10.80, currency: "USD", category: "OFFICE_SUPPLIES", merchant: "Synthetic Native Shop", expenseDate: try XCTUnwrap(RecordCoding.parseDate("2026-10-07")), projectId: nil, notes: "Dedicated QA account only", status: "DRAFT", receiptPath: path)
            try await repository.setReviewed(expense, reviewed: true)
            expense = try await repository.fetchExpense(id: expense.id)
            XCTAssertNotNil(expense.reviewedAt)
            stage = "authenticated original download"
            let receipt = try await ReceiptStorage().signedURL(for: expense)
            XCTAssertTrue(receipt.isFileURL); XCTAssertEqual(try Data(contentsOf: receipt), original)
            stage = "hosted authorized accountant packet"
            let (bytes, response) = try await AmountlyPlatform.transport.request(path: "/api/reports/accountant?year=2026&month=1&start=2026-10-07&end=2026-10-07&currency=USD&basis=cash", limit: 32 * 1024 * 1024)
            try AmountlyTransport.check(response, mime: "application/zip")
            XCTAssertTrue(bytes.starts(with: [80, 75, 3, 4]))
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try bytes.write(to: documents.appendingPathComponent("qa-hosted-packet.zip"), options: [.atomic, .completeFileProtection])
            try original.write(to: documents.appendingPathComponent("qa-hosted-original.png"), options: [.atomic, .completeFileProtection])
            try await AuthService.shared.signOut()
            PrivateDocument.removeAll()
            print("LIVE PASS: dedicated freelancer native onboarding, receipt upload/save/review, original byte match and authorized ZIP")
        } catch {
            try? await AuthService.shared.signOut(); PrivateDocument.removeAll()
            XCTFail("Dedicated hosted QA failed at " + stage)
        }
    }
    func testLiveProtectedReadsReceiptCaptureAndPacket() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_AI_LIVE_TESTING"] == "1", "Requires explicit QA opt-in.")
        let email = try XCTUnwrap(env["AMOUNTLY_AI_QA_EMAIL"]), password = try XCTUnwrap(env["AMOUNTLY_AI_QA_PASSWORD"])
        let transport = AmountlyTransport()
        // Use the same private transport for every API in this test.
        let auth = AmountlyAuthClient(transport: transport)
        var stage = "sign-in"
        var actor: alpha.User?
        do {
            let session = try await auth.signIn(email: email, password: password)
            for table in ["expenses", "invoices", "users"] {
                stage = "protected " + table + " read"
                let owner = table == "users" ? "&id=eq.\(session.user.id.uuidString.lowercased())" : ""
                let (data, response) = try await transport.request(path: "/api/data/\(table)?select=*&limit=1\(owner)")
                try AmountlyTransport.check(response)
                if table == "expenses" { _ = try RecordCoding.decoder().decode([Expense].self, from: data) }
                else if table == "users" {
                    actor = try RecordCoding.decoder().decode([alpha.User].self, from: data).first
                    XCTAssertEqual(actor?.id.lowercased(), session.user.id.uuidString.lowercased())
                }
                else { XCTAssertTrue((try JSONSerialization.jsonObject(with: data)) is [[String: Any]]) }
            }
            stage = "receipt-file AI"
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 550)).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 550))
                ("DEMO SHOP\nPURCHASE RECEIPT\nDate: 2026-10-07\nOffice paper: USD 10.00\nSales tax: USD 0.80\nTOTAL PAID: USD 10.80" as NSString).draw(in: CGRect(x: 30, y: 30, width: 940, height: 490), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
            }
            let bytes = try XCTUnwrap(image.pngData())
            let (data, response) = try await transport.request(path: "/api/ai/receipt", method: "POST", body: bytes, mime: "image/png", limit: 128000)
            try AmountlyTransport.check(response)
            let receipt = try AIReceiptFile.decode(data)
            XCTAssertEqual(receipt.document_type, .receipt); XCTAssertEqual(receipt.amount, "10.80"); XCTAssertEqual(receipt.currency, "USD"); XCTAssertEqual(receipt.expense_date, "2026-10-07")
            stage = "accountant packet"
            let (packet, packetResponse) = try await transport.request(path: "/api/reports/accountant?year=2026&month=1&start=2026-10-07&end=2026-10-07&currency=USD&basis=cash", limit: 32 * 1024 * 1024)
            if try XCTUnwrap(actor).canExportAccountantPacket {
                try AmountlyTransport.check(packetResponse, mime: "application/zip")
                XCTAssertTrue(packet.starts(with: [80, 75, 3, 4]))
                print("LIVE PASS: authorized accountant packet")
            } else {
                XCTAssertEqual(packetResponse.statusCode, 403)
                print("LIVE PASS: restricted QA role denied accountant packet; authorized download remains unverified")
            }
            try await auth.signOut()
        } catch {
            try? await auth.signOut()
            XCTFail("Live Render verification failed at \(stage): \((error as? PlatformError)?.localizedDescription ?? "Check the private test diagnostics.")")
        }
    }

    // Explicit manual UI fixture: credentials stay in XCTest's private environment;
    // only the normal session cookie is persisted to the simulator's Keychain.
    func testPrepareManualQAUI() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["AMOUNTLY_QA_UI"] == "prepare", "Explicit manual QA preparation only.")
        let email = try XCTUnwrap(env["AMOUNTLY_AI_QA_EMAIL"]), password = try XCTUnwrap(env["AMOUNTLY_AI_QA_PASSWORD"])
        try await AuthService.shared.signInWithPassword(email: email, password: password)
        _ = try await AuthService.shared.getCurrentUser()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 550)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 550))
            ("DEMO SHOP\nPURCHASE RECEIPT\nDate: 2026-10-07\nOffice paper: USD 10.00\nSales tax: USD 0.80\nTOTAL PAID: USD 10.80" as NSString).draw(in: CGRect(x: 30, y: 30, width: 940, height: 490), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
        }
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try XCTUnwrap(image.pngData()).write(to: documents.appendingPathComponent("qa-synthetic-receipt.png"), options: [.atomic, .completeFileProtection])
    }

    func testCleanUpManualQAUI() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AMOUNTLY_QA_UI"] == "cleanup", "Explicit manual QA cleanup only.")
        try await AuthService.shared.signOut()
        PrivateDocument.removeAll()
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        for name in ["qa-synthetic-receipt.png", "qa-hosted-packet.zip", "qa-hosted-original.png"] {
            let url = documents.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
