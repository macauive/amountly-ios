#if DEBUG
import Foundation

// An explicit simulator-only fixture for release UI checks. All requests are
// handled locally; there is no hosted account or real deletion request.
@MainActor
enum ReleaseReadinessPreview {
    static var enabled: Bool { ProcessInfo.processInfo.environment["AMOUNTLY_RELEASE_UI_TESTING"] == "1" }
    static var user: User {
        User(id: "00000000-0000-4000-8000-000000000001", organizationId: nil,
             email: "reviewer@example.invalid", name: "Synthetic Review", role: .member,
             accountType: .freelancer, hourlyRate: nil, isActive: true, avatarUrl: nil,
             phone: nil, timezone: "America/Chicago", preferences: nil,
             createdAt: Date(), updatedAt: Date())
    }
    static func transport() -> AmountlyTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseReadinessProtocol.self]
        let cookie = try! JSONEncoder().encode(["value": "synthetic.signed", "expires": "4102444800"])
        return AmountlyTransport(configuration: configuration, load: { cookie })
    }
}

private final class ReleaseReadinessProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let allowed = request.url?.absoluteString == "https://amountly.app/api/account/deletion-request"
            && request.httpMethod == "POST"
            && request.value(forHTTPHeaderField: "Cookie") == "__Secure-amountly.session_token=synthetic.signed"
        let response = HTTPURLResponse(url: request.url!, statusCode: allowed ? 200 : 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((allowed ? "{\"requested\":true}" : "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
