import XCTest
import UIKit
@testable import alpha

@MainActor
final class WebRefreshParityTests: XCTestCase {
    func testOriginalPDFPagingAndPageBudget() throws {
        func pdf(_ count: Int) throws -> URL {
            let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0,y: 0,width: 600,height: 800)).pdfData { context in
                for page in 0..<count { context.beginPage(); ("Synthetic page \(page)" as NSString).draw(at: CGPoint(x: 30,y: 30), withAttributes: [.font:UIFont.systemFont(ofSize: 24)]) }
            }
            return try PrivateDocument.write(data, extension: "pdf", prefix: "receipt")
        }
        let valid = try pdf(2), oversized = try pdf(6)
        defer { try? FileManager.default.removeItem(at: valid); try? FileManager.default.removeItem(at: oversized) }
        let first = try ReceiptOriginalView.renderedPage(url: valid, page: 0)
        let second = try ReceiptOriginalView.renderedPage(url: valid, page: 1)
        XCTAssertEqual(first.pages, 2); XCTAssertNotEqual(first.image.pngData(), second.image.pngData())
        XCTAssertThrowsError(try ReceiptOriginalView.renderedPage(url: valid, page: 2))
        XCTAssertThrowsError(try ReceiptOriginalView.renderedPage(url: oversized, page: 0))
    }
    private func transport() -> AmountlyTransport {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RenderProtocol.self]
        return AmountlyTransport(configuration: config)
    }
    private func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 2048)
        while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
        return data
    }
    private func draft(id: UUID, revision: Int = 1, file: Bool = false) throws -> Data {
        var fields = CaptureFields(); fields.description = "Synthetic native paper"; fields.amount = "12.50"; fields.currency = "USD"
        let payload = CapturePayload(method: .manual, fields: fields, text: "", extraction: nil, extracted: false)
        return try JSONSerialization.data(withJSONObject: ["id":id.uuidString,"revision":revision,"updated_at":"2026-10-12T00:00:00.000Z","payload":JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)),"file_name":file ? "receipt.png" as Any : NSNull(),"content_type":file ? "image/png" as Any : NSNull()])
    }
    override func tearDown() { RenderProtocol.handler = nil }
    func testCaptureAuthenticationFailurePreventsEveryRequest() async {
        RenderProtocol.handler = { _ in XCTFail("Unauthenticated capture reached network"); return (500, [:], Data()) }
        let service = CaptureDraftService(transport: transport(), authenticate: { throw PlatformError.signIn })
        do { _ = try await service.list(); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .signIn) }
    }
    func testKeepListOriginalAndRevisionedDiscardUseSharedAPI() async throws {
        let id = UUID(), value = try draft(id: id, file: true)
        let png = Data([137,80,78,71,13,10,26,10])
        let file = try PrivateDocument.write(png, extension: "png", prefix: "receipt")
        defer { try? FileManager.default.removeItem(at: file) }
        var methods: [String] = []
        RenderProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/capture-drafts"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            methods.append(request.httpMethod!)
            if request.httpMethod == "PUT" {
                let data = self.body(request), text = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(text.contains("name=\"metadata\"")); XCTAssertTrue(text.contains("\"extraction\":null"))
                XCTAssertTrue(text.contains("filename=\"receipt.png\"")); XCTAssertNotNil(data.range(of: png))
                return (200,["Content-Type":"application/json"],value)
            }
            if request.httpMethod == "DELETE" {
                let data = try JSONSerialization.jsonObject(with: self.body(request)) as! [String: Any]
                XCTAssertEqual(data["revision"] as? Int, 1)
                return (204,[:],Data())
            }
            if request.url?.query?.contains("file=1") == true {
                XCTAssertTrue(request.url!.query!.contains("revision=1"))
                return (200,["Content-Type":"image/png"],png)
            }
            return (200,["Content-Type":"application/json"],Data("[".utf8)+value+Data("]".utf8))
        }
        let service = CaptureDraftService(transport: transport(), authenticate: {})
        var fields = CaptureFields(); fields.description = "Synthetic native paper"; fields.amount = "12.50"; fields.currency = "USD"
        let saved = try await service.keep(id: id, revision: 0, payload: CapturePayload(method: .manual, fields: fields, text: "", extraction: nil, extracted: false), file: file, originalName: "receipt.png")
        let captures = try await service.list()
        XCTAssertEqual(captures.first?.id, id)
        let restoredOriginal = try await service.original(saved)
        let original = try XCTUnwrap(restoredOriginal)
        defer { try? FileManager.default.removeItem(at: original) }
        XCTAssertEqual(try Data(contentsOf: original), png)
        try await service.discard(saved)
        XCTAssertEqual(methods, ["PUT","GET","GET","DELETE"])
    }
    func testStaleCapturesCapacityAndMalformedRepliesFailSafely() async throws {
        let id = UUID(), value = try draft(id: id)
        let draft = try CaptureDraft.decode(value)
        let service = CaptureDraftService(transport: transport(), authenticate: {})
        for status in [409,413] {
            RenderProtocol.handler = { _ in (status,["Content-Type":"application/json"],Data("{}".utf8)) }
            do { try await service.discard(draft); XCTFail() } catch { XCTAssertTrue(error is CaptureError) }
        }
        RenderProtocol.handler = { _ in (200,["Content-Type":"application/json"],Data("[{}]".utf8)) }
        do { _ = try await service.list(); XCTFail() } catch {}
    }
    private func session(_ id: UUID) -> Data {
        Data("{\"user\":{\"id\":\"\(id)\",\"email\":\"synthetic@example.invalid\",\"name\":\"Synthetic\",\"emailVerified\":true,\"createdAt\":\"2026-01-01T00:00:00Z\",\"updatedAt\":\"2026-01-01T00:00:00Z\"},\"session\":{\"expiresAt\":\"2099-01-01T00:00:00Z\"}}".utf8)
    }
    private func profile(_ id: UUID) throws -> User {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var row = try JSONSerialization.jsonObject(with: encoder.encode(User.preview)) as! [String: Any]
        row["id"] = id.uuidString; row["organization_id"] = NSNull(); row["account_type"] = "freelancer"
        return try RecordCoding.decoder().decode(User.self, from: JSONSerialization.data(withJSONObject: row))
    }
    func testForegroundRevalidationPreservesSameOwnerAndRejectsRevocation() async throws {
        let id = UUID(), user = try profile(id), wire = session(id)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let users = try encoder.encode([user]), api = transport()
        let state = AppState(authService: AuthService(client: AmountlyDataClient(transport: api)), invalidatePending: { api.invalidatePending() })
        state.login(user: user, organization: nil)
        RenderProtocol.handler = { request in (200,["Content-Type":"application/json"],request.url?.path == "/api/auth/get-session" ? wire : users) }
        state.suspendPrivateUI(); XCTAssertTrue(state.privacyShield)
        await state.resumePrivateUI()
        XCTAssertFalse(state.privacyShield); XCTAssertEqual(state.currentUser?.id, user.id); XCTAssertTrue(state.isAuthenticated)
        RenderProtocol.handler = { _ in (200,["Content-Type":"application/json"],Data("null".utf8)) }
        state.suspendPrivateUI(); await state.resumePrivateUI()
        XCTAssertNil(state.currentUser); XCTAssertFalse(state.isAuthenticated); XCTAssertFalse(state.privacyShield)
    }
    func testForegroundFailureKeepsPrivateScreenCoveredUntilRetry() async throws {
        let api = transport(), state = AppState(authService: AuthService(client: AmountlyDataClient(transport: api)))
        state.login(user: try profile(UUID()), organization: nil)
        RenderProtocol.handler = { _ in (503,["Content-Type":"application/json"],Data("{}".utf8)) }
        state.suspendPrivateUI(); await state.resumePrivateUI()
        XCTAssertTrue(state.privacyShield); XCTAssertNotNil(state.sessionCheckError)
    }
    func testForegroundAccountChangeClearsPreviousAIConsent() async throws {
        let previous = try profile(UUID()), next = try profile(UUID()), api = transport()
        let state = AppState(authService: AuthService(client: AmountlyDataClient(transport: api)))
        state.login(user: previous, organization: nil)
        AIConsentStore.shared.allow(userID: previous.id, sessionGeneration: AmountlyPlatform.transport.generation)
        defer { AIConsentStore.shared.revoke() }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let users = try encoder.encode([next]), wire = session(UUID(uuidString: next.id)!)
        RenderProtocol.handler = { request in (200,["Content-Type":"application/json"],request.url?.path == "/api/auth/get-session" ? wire : users) }
        state.suspendPrivateUI(); await state.resumePrivateUI()
        XCTAssertEqual(state.currentUser?.id, next.id)
        XCTAssertFalse(AIConsentStore.shared.allows(userID: previous.id, sessionGeneration: AmountlyPlatform.transport.generation))
    }
}
