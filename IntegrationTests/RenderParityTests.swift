import XCTest
import Supabase
@testable import alpha

final class RenderProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@MainActor
final class RenderParityTests: XCTestCase {
    private let id = "00000000-0000-4000-8000-000000000001"
    private var sessionData: Data {
        Data("{\"user\":{\"id\":\"\(id)\",\"email\":\"qa@example.invalid\",\"name\":\"Synthetic QA\",\"emailVerified\":true,\"createdAt\":\"2026-10-07T00:00:00Z\",\"updatedAt\":\"2026-10-07T00:00:00Z\"},\"session\":{\"expiresAt\":\"2099-10-07T00:00:00Z\"}}".utf8)
    }
    func makeClient() -> AmountlyDataClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RenderProtocol.self]
        return AmountlyDataClient(transport: AmountlyTransport(configuration: config))
    }
    func testCookieLoginRecordsAndSignOutUseProtectedAPI() async throws {
        let session = sessionData
        var paths: [String] = []
        RenderProtocol.handler = { request in
            let path = request.url!.path; paths.append(path)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://amountly.app")
            let cookie = "__Secure-amountly.session_token=synthetic.signed; Path=/; Max-Age=604800; Secure; HttpOnly; SameSite=Lax"
            if path == "/api/auth/sign-in/email" { return (200, ["Content-Type": "application/json", "Set-Cookie": cookie], Data("{}".utf8)) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Secure-amountly.session_token=synthetic.signed")
            return (200, ["Content-Type": "application/json"], path == "/api/auth/get-session" ? session : path == "/api/auth/sign-out" ? Data("{}".utf8) : Data("[]".utf8))
        }
        let client = makeClient()
        let auth = try await client.auth.signIn(email: "qa@example.invalid", password: "synthetic-password")
        XCTAssertEqual(auth.user.id.uuidString.lowercased(), id)
        XCTAssertEqual(auth.accessToken, ""); XCTAssertEqual(auth.refreshToken, "")
        let records: [Expense] = try await client.from("expenses").select().execute().value
        XCTAssertTrue(records.isEmpty)
        try await client.auth.signOut(); XCTAssertNil(client.auth.currentSession)
        XCTAssertEqual(paths, ["/api/auth/sign-in/email", "/api/auth/get-session", "/api/data/expenses", "/api/auth/sign-out"])
    }
    func testSessionRevocationCannotRestoreOldProfile() async throws {
        RenderProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data("null".utf8)) }
        let client = makeClient()
        do { _ = try await client.auth.session; XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .signIn) }
        XCTAssertNil(client.auth.currentSession)
    }
    func testRejectedSessionClearsCachedIdentityAndCookie() async throws {
        let session = sessionData
        var revoked = false
        var cleared = false
        RenderProtocol.handler = { request in
            if request.url?.path == "/api/auth/sign-in/email" {
                return (200, ["Content-Type": "application/json", "Set-Cookie": "__Secure-amountly.session_token=synthetic.signed; Path=/; Max-Age=604800; Secure; HttpOnly"], Data("{}".utf8))
            }
            if cleared {
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                return (200, ["Content-Type": "application/json"], Data(" null \n".utf8))
            }
            return (revoked ? 401 : 200, ["Content-Type": "application/json"], revoked ? Data("{}".utf8) : session)
        }
        let client = makeClient()
        _ = try await client.auth.signIn(email: "qa@example.invalid", password: "synthetic-password")
        XCTAssertNotNil(client.auth.currentSession)
        revoked = true
        do { _ = try await client.auth.session; XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .signIn) }
        XCTAssertNil(client.auth.currentSession)
        cleared = true
        do { _ = try await client.auth.session; XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .signIn) }
    }
    func testSixDigitOTPAndSignupLimitsRejectBeforeNetwork() async {
        RenderProtocol.handler = { _ in XCTFail("Invalid auth input reached network"); return (500, [:], Data()) }
        let client = makeClient()
        for code in ["12345", "12345678", "123ab6", "１２３４５６"] {
            do { _ = try await client.auth.verifyEmail(email: "qa@example.invalid", token: code); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .input) }
        }
        do { try await client.auth.signUp(email: "qa@example.invalid", password: "short", data: ["name": .string("Synthetic QA")]); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .input) }
    }
    func testPasswordChangeRequiresCurrentPasswordAndRevokesOtherSessions() async throws {
        RenderProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/change-password")
            XCTAssertEqual(request.httpMethod, "POST")
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(Set(body.keys), ["currentPassword", "newPassword", "revokeOtherSessions"])
            XCTAssertEqual(body["revokeOtherSessions"] as? Bool, true)
            return (200, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        let client = makeClient()
        try await client.auth.changePassword(current: "synthetic-current", new: "synthetic-new-password")
        RenderProtocol.handler = { _ in XCTFail("Invalid password input reached network"); return (500, [:], Data()) }
        do { try await client.auth.changePassword(current: "", new: "synthetic-new-password"); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .input) }
        do { try await client.auth.changePassword(current: "synthetic-current", new: "short"); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .input) }
    }
    func testExistingProfileCannotBeReplacedBySoloSetup() async throws {
        let session = sessionData
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var profile = try JSONSerialization.jsonObject(with: encoder.encode(User.preview)) as! [String: Any]
        profile["id"] = id; profile["account_type"] = "business"; profile["role"] = "OWNER"
        let payload = try JSONSerialization.data(withJSONObject: [profile])
        RenderProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET", "Setup must never mutate an existing profile")
            return (200, ["Content-Type": "application/json"], request.url?.path == "/api/auth/get-session" ? session : payload)
        }
        let service = AuthService(client: makeClient())
        let user = try await service.createPersonalUser(name: "Replacement name", accountType: .freelancer)
        XCTAssertEqual(user.accountType, .business); XCTAssertEqual(user.role, .owner)
        XCTAssertEqual(user.name, User.preview.name)
    }
    func testNewSoloProfileUsesOneInsertWithoutLegacyAccountMutation() async throws {
        let session = sessionData
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var profile = try JSONSerialization.jsonObject(with: encoder.encode(User.preview)) as! [String: Any]
        profile["id"] = id; profile["account_type"] = "freelancer"; profile["role"] = "MEMBER"; profile["organization_id"] = NSNull()
        let payload = try JSONSerialization.data(withJSONObject: [profile])
        var inserts = 0
        RenderProtocol.handler = { request in
            if request.url?.path == "/api/auth/get-session" { return (200, ["Content-Type": "application/json"], session) }
            XCTAssertEqual(request.url?.path, "/api/data/users", "Onboarding must use the web profile contract.")
            if request.httpMethod == "POST" {
                inserts += 1
                return (201, ["Content-Type": "application/json"], Data("null".utf8))
            }
            XCTAssertEqual(request.httpMethod, "GET", "Setup cannot update roles or account types after creating a profile.")
            return (200, ["Content-Type": "application/json"], inserts == 0 ? Data("[]".utf8) : payload)
        }
        let user = try await AuthService(client: makeClient()).createPersonalUser(name: "Synthetic QA", accountType: .freelancer)
        XCTAssertEqual(inserts, 1); XCTAssertEqual(user.accountType, .freelancer); XCTAssertEqual(user.role, .member); XCTAssertNil(user.organizationId)
    }
    func testMissingAndInactiveProfilesAreNotConfused() async throws {
        let session = sessionData
        RenderProtocol.handler = { request in (200, ["Content-Type": "application/json"], request.url?.path == "/api/auth/get-session" ? session : Data("[]".utf8)) }
        let service = AuthService(client: makeClient())
        do { _ = try await service.restoreAuthenticatedState(); XCTFail() }
        catch { guard case .profileSetupRequired? = error as? alpha.AuthError else { XCTFail("Expected setup state"); return } }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var profile = try JSONSerialization.jsonObject(with: encoder.encode(User.preview)) as! [String: Any]
        profile["is_active"] = false
        let payload = try JSONSerialization.data(withJSONObject: [profile])
        RenderProtocol.handler = { request in (200, ["Content-Type": "application/json"], request.url?.path == "/api/auth/get-session" ? session : payload) }
        do { _ = try await service.getUserInfo(); XCTFail() }
        catch { XCTAssertTrue(error is RecordError) }
    }
    func testExpenseReviewMarkerAndMissingMarkerDecode() throws {
        let encoder = RecordCoding.decoder()
        let data = try JSONEncoder().encode(Expense.preview)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["expense_date"] = "2026-10-07"; object["created_at"] = "2026-10-07T00:00:00Z"; object["updated_at"] = "2026-10-07T00:00:00Z"
        object["project"] = NSNull(); object["user"] = NSNull(); object["task"] = NSNull(); object["status"] = "DRAFT"
        object.removeValue(forKey: "reviewed_at")
        var expense = try encoder.decode(Expense.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(expense.needsReview)
        object["reviewed_at"] = "2026-10-07T01:00:00Z"
        expense = try encoder.decode(Expense.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNotNil(expense.reviewedAt); XCTAssertFalse(expense.needsReview)
        object["reviewed_at"] = NSNull(); object["status"] = "APPROVED"
        expense = try encoder.decode(Expense.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(expense.needsReview)
    }

    func testAccountantPacketRequiresActiveStandaloneFreelancer() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var profile = try JSONSerialization.jsonObject(with: encoder.encode(User.preview)) as! [String: Any]
        func allowed() throws -> Bool {
            try RecordCoding.decoder().decode(alpha.User.self, from: JSONSerialization.data(withJSONObject: profile)).canExportAccountantPacket
        }
        profile["account_type"] = "business"; profile["role"] = "OWNER"
        XCTAssertFalse(try allowed())
        profile["account_type"] = "personal"; profile["organization_id"] = NSNull()
        XCTAssertFalse(try allowed())
        profile["account_type"] = "freelancer"
        XCTAssertTrue(try allowed())
        profile["organization_id"] = id
        XCTAssertFalse(try allowed())
        profile["organization_id"] = NSNull(); profile["is_active"] = false
        XCTAssertFalse(try allowed())
    }
}
