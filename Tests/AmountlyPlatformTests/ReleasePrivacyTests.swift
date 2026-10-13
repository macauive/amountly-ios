import XCTest
@testable import AmountlyPlatform

@MainActor
final class ReleasePrivacyTests: XCTestCase {
    private let userID = "00000000-0000-4000-8000-000000000001"

    private func transport(consent: AIConsentStore, authenticated: Bool = false) -> AmountlyTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlatformProtocol.self]
        let cookie = try! JSONEncoder().encode(["value": "synthetic.signed", "expires": "4102444800"])
        return AmountlyTransport(configuration: config, load: { authenticated ? cookie : nil }, aiConsent: consent)
    }

    func testEveryAIEndpointBlocksBeforeNetworkUntilConsent() async throws {
        let consent = AIConsentStore()
        let api = transport(consent: consent, authenticated: true)
        var calls = 0
        PlatformProtocol.handler = { _ in calls += 1; return (200, ["Content-Type": "application/json"], Data("{}".utf8)) }
        for path in ["/api/ai", "/api/ai/receipt"] {
            do { _ = try await api.request(path: path, method: "POST", body: Data("{}".utf8)); XCTFail("AI sent without permission") }
            catch { XCTAssertEqual(error as? PlatformError, .consent) }
        }
        XCTAssertEqual(calls, 0)
        consent.allow(userID: userID, sessionGeneration: api.generation)
        _ = try await api.request(path: "/api/ai", method: "POST", body: Data("{}".utf8))
        XCTAssertEqual(calls, 1)
        consent.revoke()
        do { _ = try await api.request(path: "/api/ai/receipt", method: "POST", body: Data()); XCTFail() }
        catch { XCTAssertEqual(error as? PlatformError, .consent) }
        XCTAssertEqual(calls, 1)
    }

    func testConsentBelongsToAccountAndSessionAndDoesNotPersist() throws {
        let consent = AIConsentStore()
        let api = transport(consent: consent)
        consent.allow(userID: userID, sessionGeneration: api.generation)
        XCTAssertTrue(consent.allows(userID: userID.uppercased(), sessionGeneration: api.generation))
        XCTAssertFalse(consent.allows(userID: "00000000-0000-4000-8000-000000000002", sessionGeneration: api.generation))
        XCTAssertFalse(consent.allows(userID: userID, sessionGeneration: UUID()))
        XCTAssertFalse(AIConsentStore().allows(userID: userID, sessionGeneration: api.generation))
        try api.clear()
        XCTAssertFalse(consent.allows(userID: userID, sessionGeneration: api.generation))
        consent.allow(userID: "invalid", sessionGeneration: api.generation)
        XCTAssertThrowsError(try consent.authorization(sessionGeneration: api.generation))
    }

    func testWithdrawalDuringRequestDiscardsResponseEvenAfterRegrant() async {
        let consent = AIConsentStore()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConsentRevocationProtocol.self]
        let api = AmountlyTransport(configuration: config, aiConsent: consent)
        consent.allow(userID: userID, sessionGeneration: api.generation)
        let id = userID, generation = api.generation
        ConsentRevocationProtocol.beforeResponse = { consent.revoke(); consent.allow(userID: id, sessionGeneration: generation) }
        do { _ = try await api.request(path: "/api/ai", method: "POST", body: Data()); XCTFail("Stale AI response escaped consent withdrawal") }
        catch { XCTAssertEqual(error as? PlatformError, .consent) }
    }

    func testDeletionUsesSessionWithoutClientSuppliedIdentity() async throws {
        let api = transport(consent: AIConsentStore(), authenticated: true)
        PlatformProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://amountly.app/api/account/deletion-request")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Secure-amountly.session_token=synthetic.signed")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://amountly.app")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 32)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) }
            }
            XCTAssertEqual(String(decoding: body, as: UTF8.self), "{}")
            return (200, ["Content-Type": "application/json"], Data("{\"requested\":true}".utf8))
        }
        try await AccountDeletionService(transport: api).request()
    }

    func testDeletionCannotReportSuccessWithoutAuthenticatedValidConfirmation() async throws {
        var calls = 0
        PlatformProtocol.handler = { _ in calls += 1; return (200, ["Content-Type": "application/json"], Data("{\"requested\":true}".utf8)) }
        do { try await AccountDeletionService(transport: transport(consent: AIConsentStore())).request(); XCTFail() }
        catch { XCTAssertEqual(error as? PlatformError, .signIn) }
        XCTAssertEqual(calls, 0)
        for body in ["{}", "{\"requested\":false}", "{\"requested\":1}", "{\"requested\":true,\"user_id\":\"other\"}"] {
            PlatformProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data(body.utf8)) }
            do { try await AccountDeletionService(transport: transport(consent: AIConsentStore(), authenticated: true)).request(); XCTFail() }
            catch { XCTAssertEqual(error as? PlatformError, .response) }
        }
        for status in [401, 403, 500] {
            PlatformProtocol.handler = { _ in (status, ["Content-Type": "application/json"], Data("{\"requested\":true}".utf8)) }
            do { try await AccountDeletionService(transport: transport(consent: AIConsentStore(), authenticated: true)).request(); XCTFail() }
            catch { XCTAssertEqual(error as? PlatformError, status == 401 ? .signIn : status == 403 ? .denied : .unavailable) }
        }
    }
}

private final class ConsentRevocationProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var beforeResponse: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            Self.beforeResponse?()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
