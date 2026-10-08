import Foundation

nonisolated enum PlatformError: LocalizedError, Equatable {
    case input, signIn, denied, unavailable, response, tooLarge, busy
    var errorDescription: String? {
        switch self {
        case .input: "Check your details and try again."
        case .signIn: "Sign in again to continue."
        case .denied: "You do not have permission to complete this request."
        case .unavailable: "Could not reach Amountly. Try again."
        case .response: "Amountly returned an unexpected response. Try again."
        case .tooLarge: "This file or packet is too large. Choose a smaller file or date range."
        case .busy: "The service is busy. Try again shortly."
        }
    }
}

// All production authentication, records, AI, receipts and exports share this
// private session. No cookies enter shared browser storage or plaintext files.
@MainActor
final class AmountlyTransport {
    static let origin = URL(string: "https://amountly.app")!
    private let session: URLSession
    private let save: (Data?) throws -> Void
    private var cookie: HTTPCookie?
    private(set) var generation = UUID()
    init(configuration: URLSessionConfiguration = .ephemeral,
         load: @escaping () throws -> Data? = { nil }, save: @escaping (Data?) throws -> Void = { _ in }) {
        self.save = save
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 65; configuration.timeoutIntervalForResource = 75
        session = URLSession(configuration: configuration, delegate: PlatformRedirectGuard(), delegateQueue: nil)
        if let data = try? load(), let fields = try? JSONDecoder().decode([String: String].self, from: data),
           let value = fields["value"], let expiry = fields["expires"].flatMap(Double.init), expiry > Date().timeIntervalSince1970,
           Self.validCookieValue(value) {
            cookie = HTTPCookie(properties: [.name: "__Secure-amountly.session_token", .value: value,
                .domain: "amountly.app", .path: "/", .secure: "TRUE", .expires: Date(timeIntervalSince1970: expiry)])
        }
    }
    deinit { session.invalidateAndCancel() }
    static func validCookieValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8192 && value.utf8.allSatisfy { $0 > 32 && $0 < 127 && $0 != 59 && $0 != 44 && $0 != 34 && $0 != 92 }
    }
    func clear() throws { generation = UUID(); cookie = nil; try save(nil) }
    func cookieHeader() throws -> String {
        guard let cookie, cookie.expiresDate.map({ $0 > Date() }) == true else { throw PlatformError.signIn }
        return "\(cookie.name)=\(cookie.value)"
    }
    func request(path: String, method: String = "GET", body: Data? = nil, mime: String = "application/json", limit: Int = 4 * 1024 * 1024) async throws -> (Data, HTTPURLResponse) {
        guard path.hasPrefix("/api/"), let url = URL(string: path, relativeTo: Self.origin)?.absoluteURL else { throw PlatformError.input }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        if body != nil { request.setValue(mime, forHTTPHeaderField: "Content-Type") }
        return try await send(request, limit: limit)
    }
    func send(_ proposed: URLRequest, limit: Int = 4 * 1024 * 1024) async throws -> (Data, HTTPURLResponse) {
        guard let url = proposed.url, url.scheme == "https", url.host == "amountly.app", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil, url.fragment == nil, url.path.hasPrefix("/api/"), limit > 0 else { throw PlatformError.input }
        var request = proposed
        request.setValue(nil, forHTTPHeaderField: "Authorization"); request.setValue(nil, forHTTPHeaderField: "apikey")
        request.setValue(try? cookieHeader(), forHTTPHeaderField: "Cookie")
        request.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let expectedGeneration = generation
        do {
            let (data, http) = try await Self.read(session: session, request: request, limit: limit)
            try Task.checkCancellation()
            guard generation == expectedGeneration else { throw PlatformError.signIn }
            if let raw = http.value(forHTTPHeaderField: "Set-Cookie") {
                for candidate in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: url)
                where candidate.name == "__Secure-amountly.session_token" {
                    guard candidate.domain == "amountly.app", candidate.path == "/", candidate.isSecure,
                          candidate.isHTTPOnly else { throw PlatformError.response }
                    if candidate.expiresDate.map({ $0 <= Date() }) == true { try clear() }
                    else {
                        guard Self.validCookieValue(candidate.value), let expiry = candidate.expiresDate else { throw PlatformError.response }
                        try save(JSONEncoder().encode(["value": candidate.value, "expires": String(expiry.timeIntervalSince1970)]))
                        cookie = candidate
                    }
                }
            }
            return (data, http)
        } catch is CancellationError { throw CancellationError() }
        catch let error as PlatformError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw PlatformError.unavailable }
    }
    // Stream on the cooperative executor so a large receipt ZIP cannot block
    // SwiftUI. Bound both declared and actual size before exposing any bytes.
    nonisolated private static func read(session: URLSession, request: URLRequest, limit: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == request.url, !(300...399).contains(http.statusCode) else { throw PlatformError.response }
        guard response.expectedContentLength <= limit else { throw PlatformError.tooLarge }
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes { guard data.count < limit else { throw PlatformError.tooLarge }; data.append(byte) }
        return (data, http)
    }
    static func check(_ response: HTTPURLResponse, mime: String? = "application/json") throws {
        switch response.statusCode {
        case 200...299: break
        case 400, 422: throw PlatformError.input
        case 401: throw PlatformError.signIn
        case 403: throw PlatformError.denied
        case 413: throw PlatformError.tooLarge
        case 429: throw PlatformError.busy
        default: throw PlatformError.unavailable
        }
        if let mime, response.mimeType != mime { throw PlatformError.response }
    }
}
final class PlatformRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
