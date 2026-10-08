import XCTest
@testable import AmountlyPlatform

final class PlatformProtocol: URLProtocol, @unchecked Sendable {
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
final class TransportTests: XCTestCase {
    func transport(load: @escaping () throws -> Data? = { nil }, save: @escaping (Data?) throws -> Void = { _ in }) -> AmountlyTransport {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PlatformProtocol.self]
        return AmountlyTransport(configuration: config, load: load, save: save)
    }
    func testCookieSessionIsPrivatePersistentAndSameOrigin() async throws {
        var stored: Data?
        PlatformProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://amountly.app")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            return (200, ["Content-Type": "application/json", "Set-Cookie": "__Secure-amountly.session_token=synthetic.signed; Path=/; Max-Age=604800; Secure; HttpOnly; SameSite=Lax"], Data("{}".utf8))
        }
        let api = transport(save: { stored = $0 })
        _ = try await api.request(path: "/api/auth/sign-in/email", method: "POST", body: Data("{}".utf8))
        XCTAssertEqual(try api.cookieHeader(), "__Secure-amountly.session_token=synthetic.signed")
        XCTAssertNotNil(stored)
        let restored = transport(load: { stored }, save: { stored = $0 })
        XCTAssertEqual(try restored.cookieHeader(), try api.cookieHeader())
        PlatformProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Secure-amountly.session_token=synthetic.signed")
            return (200, ["Content-Type": "application/json"], Data("[]".utf8))
        }
        _ = try await restored.request(path: "/api/data/expenses")
        let generation = restored.generation
        try restored.clear(); XCTAssertNotEqual(generation, restored.generation); XCTAssertNil(stored)
        XCTAssertThrowsError(try restored.cookieHeader())
    }
    func testRejectsExternalDestinationsBeforeAttachingCredentials() async {
        var calls = 0; PlatformProtocol.handler = { _ in calls += 1; return (200, [:], Data()) }
        for url in ["https://evil.invalid/api/data/users", "http://amountly.app/api/data/users", "https://amountly.app:444/api/data/users", "https://user@amountly.app/api/data/users", "https://amountly.app/mcp"] {
            do { _ = try await transport().send(URLRequest(url: URL(string: url)!)); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .input) }
        }
        XCTAssertEqual(calls, 0)
    }
    func testRejectsInsecureAndWrongDomainCookies() async {
        for cookie in ["__Secure-amountly.session_token=synthetic; Path=/; Max-Age=300; HttpOnly", "__Secure-amountly.session_token=synthetic; Domain=evil.invalid; Path=/; Max-Age=300; Secure; HttpOnly", "__Secure-amountly.session_token=synthetic; Path=/; Max-Age=300; Secure"] {
            PlatformProtocol.handler = { _ in (200, ["Content-Type": "application/json", "Set-Cookie": cookie], Data("{}".utf8)) }
            let api = transport()
            do { _ = try await api.request(path: "/api/auth/sign-in/email", method: "POST", body: Data()); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .response) }
            XCTAssertThrowsError(try api.cookieHeader())
        }
    }
    func testBoundsResponseAndSafeErrors() async throws {
        PlatformProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data(repeating: 32, count: 101)) }
        do { _ = try await transport().request(path: "/api/data/users", limit: 100); XCTFail() } catch { XCTAssertEqual(error as? PlatformError, .tooLarge) }
        for (status, expected) in [(401, PlatformError.signIn), (403, .denied), (413, .tooLarge), (429, .busy), (500, .unavailable)] {
            let response = HTTPURLResponse(url: AmountlyTransport.origin, statusCode: status, httpVersion: nil, headerFields: nil)!
            XCTAssertThrowsError(try AmountlyTransport.check(response)) { XCTAssertEqual($0 as? PlatformError, expected) }
        }
    }
    func testServerCookieDeletionClearsPersistedSession() async throws {
        var persisted: Data?
        let api = transport(save: { persisted = $0 })
        PlatformProtocol.handler = { _ in (200, ["Content-Type": "application/json", "Set-Cookie": "__Secure-amountly.session_token=synthetic.signed; Path=/; Max-Age=604800; Secure; HttpOnly"], Data("{}".utf8)) }
        _ = try await api.request(path: "/api/auth/sign-in/email", method: "POST", body: Data())
        XCTAssertNotNil(persisted)
        PlatformProtocol.handler = { _ in (200, ["Content-Type": "application/json", "Set-Cookie": "__Secure-amountly.session_token=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly"], Data("{}".utf8)) }
        _ = try await api.request(path: "/api/auth/sign-out", method: "POST", body: Data())
        XCTAssertNil(persisted); XCTAssertThrowsError(try api.cookieHeader())
    }
    func testCredentialStoreFailureDoesNotEstablishSession() async {
        let api = transport(save: { _ in throw PlatformError.unavailable })
        PlatformProtocol.handler = { _ in (200, ["Content-Type": "application/json", "Set-Cookie": "__Secure-amountly.session_token=synthetic.signed; Path=/; Max-Age=300; Secure; HttpOnly"], Data("{}".utf8)) }
        do { _ = try await api.request(path: "/api/auth/sign-in/email", method: "POST", body: Data()); XCTFail() }
        catch { XCTAssertEqual(error as? PlatformError, .unavailable) }
        XCTAssertThrowsError(try api.cookieHeader())
    }
    func testNoCredentialForwardingOnRedirect() {
        let delegate = PlatformRedirectGuard(), session = URLSession(configuration: .ephemeral)
        let request = URLRequest(url: URL(string: "https://evil.invalid")!)
        delegate.urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: HTTPURLResponse(url: AmountlyTransport.origin, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: request) { XCTAssertNil($0) }
        session.invalidateAndCancel()
    }
}
