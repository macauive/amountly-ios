import Foundation

nonisolated struct AISession: Sendable, Equatable { let userID: String, token: String }

// Never forward the user's bearer token across an HTTP redirect.
final class AIRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class AIClient {
    static let endpoint = URL(string: "https://amountly.app/api/ai")!
    private let session: URLSession
    private let identity: () async throws -> AISession
    private let transport: ((URLRequest) async throws -> (Data, HTTPURLResponse))?
    init(configuration: URLSessionConfiguration = .ephemeral, transport: ((URLRequest) async throws -> (Data, HTTPURLResponse))? = nil, identity: @escaping () async throws -> AISession) {
        configuration.timeoutIntervalForRequest = 65
        configuration.timeoutIntervalForResource = 75
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration, delegate: AIRedirectGuard(), delegateQueue: nil)
        self.identity = identity
        self.transport = transport
    }
    deinit { session.invalidateAndCancel() }
    func run<P: Encodable, R: AIResult>(_ task: AITask, payload: P, as: R.Type = R.self) async throws -> R {
        let expected: any AIResult.Type
        switch task {
        case .expense: expected = AIExpense.self
        case .receipt: expected = AIReceipt.self
        case .line: expected = AILine.self
        case .reminder: expected = AIReminder.self
        case .time: expected = AITime.self
        case .contact: expected = AIContact.self
        case .dashboard: expected = AIDashboard.self
        }
        guard R.self == expected else { throw AIError.input }
        let payloadData = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: payloadData, options: [.fragmentsAllowed])
        try AIRequestPolicy.validate(task, payload: object)
        let text: String
        if let string = object as? String { text = string }
        else { text = String(decoding: payloadData, as: UTF8.self) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 12000 else { throw AIError.input }
        let body = try JSONSerialization.data(withJSONObject: ["task": task.rawValue, "payload": object])
        guard body.count <= 64000 else { throw AIError.input }
        let actor: AISession
        do { actor = try await identity() } catch { throw AIError.signIn }
        guard !actor.userID.isEmpty, actor.token.range(of: #"^[A-Za-z0-9._-]{20,8192}$"#, options: .regularExpression) != nil else { throw AIError.signIn }
        try Task.checkCancellation()
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if transport == nil { request.setValue("Bearer \(actor.token)", forHTTPHeaderField: "Authorization") }
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            if let transport {
                let (data, http) = try await transport(request)
                switch http.statusCode {
                case 200: break
                case 400, 413, 415: throw AIError.input
                case 401: throw AIError.signIn
                case 403: throw AIError.denied
                case 429: throw AIError.limit
                default: throw AIError.unavailable
                }
                guard http.url == Self.endpoint, http.mimeType == "application/json", data.count <= 256000 else { throw AIError.response }
                try Task.checkCancellation()
                guard try await identity() == actor else { throw AIError.signIn }
                return try AIValidation.decode(R.self, data: data)
            }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.url == Self.endpoint else { throw AIError.response }
            switch http.statusCode {
            case 200: break
            case 400, 413, 415: throw AIError.input
            case 401: throw AIError.signIn
            case 403: throw AIError.denied
            case 429: throw AIError.limit
            default: throw AIError.unavailable
            }
            guard http.mimeType == "application/json", response.expectedContentLength <= 256000 else { throw AIError.response }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 256000 else { throw AIError.response }
                data.append(byte)
            }
            try Task.checkCancellation()
            // A result from a previous account must never fill the current account's form.
            let current: AISession
            do { current = try await identity() } catch { throw AIError.signIn }
            guard current.userID == actor.userID else { throw AIError.signIn }
            return try AIValidation.decode(R.self, data: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as AIError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw AIError.network
        }
    }
}
