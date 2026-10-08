import Foundation
import Supabase

@MainActor
final class AmountlyDataClient {
    let auth: AmountlyAuthClient
    private let rest: PostgrestClient
#if DEBUG
    let localClient: SupabaseClient?
    var storage: SupabaseStorageClient { guard let localClient else { preconditionFailure("Legacy storage is local-test only.") }; return localClient.storage }
#endif
    convenience init() { self.init(transport: AmountlyPlatform.transport) }
    init(transport: AmountlyTransport) {
#if DEBUG
        if ProcessInfo.processInfo.environment["AMOUNTLY_LOCAL_TESTING"] == "1" {
            let env = ProcessInfo.processInfo.environment
            guard let raw = env["AMOUNTLY_LOCAL_URL"], let url = URL(string: raw), url.scheme == "http", url.host == "127.0.0.1",
                  [54321, 54331].contains(url.port ?? 0), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/", let key = env["AMOUNTLY_LOCAL_ANON_KEY"], !key.isEmpty else {
                preconditionFailure("Local integration configuration must be loopback-only.")
            }
            let local = SupabaseClient(supabaseURL: url, supabaseKey: key, options: .init(auth: .init(storageKey: "amountly-local-integration-session", flowType: .pkce, emitLocalSessionAsInitialSession: true)))
            localClient = local; auth = AmountlyAuthClient(local: local.auth)
            rest = PostgrestClient(url: url.appendingPathComponent("rest/v1"), headers: ["apikey": key], logger: nil, fetch: { request in
                var request = request
                let token = try await local.auth.session.accessToken
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return try await URLSession.shared.data(for: request)
            }, decoder: RecordCoding.decoder())
            return
        }
        localClient = nil
#endif
        auth = AmountlyAuthClient(transport: transport)
        rest = PostgrestClient(url: AmountlyTransport.origin.appendingPathComponent("api/data"), logger: nil, fetch: { request in
            try await transport.send(request)
        }, decoder: RecordCoding.decoder())
    }
    func from(_ table: String) -> PostgrestQueryBuilder { rest.from(table) }
    func rpc(_ command: String, params: some Encodable & Sendable) throws -> PostgrestFilterBuilder { try rest.rpc(command, params: params) }
}

@MainActor
enum AmountlyPlatform {
    static let transport = AmountlyTransport(load: { try KeychainHelper.shared.get("render-session-v1") }, save: { data in
        if let data { try KeychainHelper.shared.save(data, for: "render-session-v1") }
        else { try KeychainHelper.shared.delete("render-session-v1") }
    })
}

@MainActor
final class AmountlyAuthClient {
    private let transport: AmountlyTransport
    private var storedSession: Session?
    private var listeners: [UUID: AsyncStream<(event: AuthChangeEvent, session: Session?)>.Continuation] = [:]
#if DEBUG
    private let local: AuthClient?
    convenience init(local: AuthClient? = nil) { self.init(local: local, transport: AmountlyPlatform.transport) }
    init(local: AuthClient? = nil, transport: AmountlyTransport) { self.local = local; self.transport = transport }
#else
    init(transport: AmountlyTransport) { self.transport = transport }
#endif
    var currentSession: Session? {
#if DEBUG
        if let local { return local.currentSession }
#endif
        return storedSession
    }
    var session: Session { get async throws {
#if DEBUG
        if let local { return try await local.session }
#endif
        return try await refreshSession()
    } }
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
#if DEBUG
        if let local { return local.authStateChanges }
#endif
        let id = UUID()
        return AsyncStream { continuation in
            listeners[id] = continuation
            continuation.yield((.initialSession, storedSession))
            continuation.onTermination = { [weak self] _ in
                guard let owner = self else { return }
                Task { @MainActor in owner.listeners[id] = nil }
            }
        }
    }
    private func emit(_ event: AuthChangeEvent) { for listener in listeners.values { listener.yield((event, storedSession)) } }
    func call(_ path: String, body: [String: String]? = nil) async throws -> Data {
        let data = try body.map { try JSONEncoder().encode($0) }
        let (result, response) = try await transport.request(path: "/api/auth/\(path)", method: body == nil ? "GET" : "POST", body: data, limit: 64000)
        try AmountlyTransport.check(response)
        return result
    }
    func signIn(email: String, password: String) async throws -> Session {
#if DEBUG
        if let local { return try await local.signIn(email: email, password: password) }
#endif
        storedSession = nil; try transport.clear()
        _ = try await call("sign-in/email", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
        let result = try await refreshSession(); emit(.signedIn); return result
    }
    func refreshSession() async throws -> Session {
#if DEBUG
        if let local { return try await local.refreshSession() }
#endif
        let data: Data
        do { data = try await call("get-session") }
        catch let error as PlatformError where error == .signIn || error == .denied {
            storedSession = nil; try transport.clear(); emit(.signedOut)
            throw error
        }
        struct Wire: Decodable {
            struct Person: Decodable { let id: UUID; let email: String; let name: String; let emailVerified: Bool; let createdAt: String; let updatedAt: String }
            struct Info: Decodable { let expiresAt: String }
            let user: Person; let session: Info
        }
        guard String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) != "null" else {
            storedSession = nil; try transport.clear(); emit(.signedOut); throw PlatformError.signIn
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let expires = RecordCoding.parseDate(wire.session.expiresAt) else { throw PlatformError.response }
        guard wire.user.emailVerified, expires > Date() else {
            storedSession = nil; try transport.clear(); emit(.signedOut); throw PlatformError.signIn
        }
        let now = Date()
        let user = Auth.User(id: wire.user.id, appMetadata: [:], userMetadata: ["name": .string(wire.user.name)], aud: "authenticated",
            email: wire.user.email, createdAt: RecordCoding.parseDate(wire.user.createdAt) ?? now, emailConfirmedAt: now, updatedAt: now)
        // Compatibility model only; Render credentials live exclusively in the
        // private cookie transport. No empty JWT is ever used for authorization.
        storedSession = Session(accessToken: "", tokenType: "cookie", expiresIn: expires.timeIntervalSinceNow, expiresAt: expires.timeIntervalSince1970, refreshToken: "", user: user)
        return storedSession!
    }
    func signOut() async throws {
#if DEBUG
        if let local { try await local.signOut(); return }
#endif
        defer { storedSession = nil; try? transport.clear(); emit(.signedOut) }
        _ = try await call("sign-out", body: [:])
    }
    func signUp(email: String, password: String, data: [String: AnyJSON]) async throws {
#if DEBUG
        if let local { _ = try await local.signUp(email: email, password: password, data: data); return }
#endif
        guard (12...128).contains(password.utf16.count), case let .string(name)? = data["name"], (2...120).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count) else { throw PlatformError.input }
        _ = try await call("sign-up/email", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "name": name.trimmingCharacters(in: .whitespacesAndNewlines)])
    }
    func verifyEmail(email: String, token: String) async throws -> Session {
#if DEBUG
        if let local { _ = try await local.verifyOTP(email: email, token: token, type: .signup); return try await local.session }
#endif
        guard token.count == 6, token.utf8.allSatisfy({ (48...57).contains($0) }) else { throw PlatformError.input }
        _ = try await call("email-otp/verify-email", body: ["email": email, "otp": token])
        let result = try await refreshSession(); emit(.signedIn); return result
    }
    func changePassword(current: String, new: String) async throws {
        guard !current.isEmpty, current.utf16.count <= 128, (12...128).contains(new.utf16.count) else { throw PlatformError.input }
        struct Body: Encodable { let currentPassword: String; let newPassword: String; let revokeOtherSessions = true }
        let (data, response) = try await transport.request(path: "/api/auth/change-password", method: "POST", body: JSONEncoder().encode(Body(currentPassword: current, newPassword: new)), limit: 64000)
        try AmountlyTransport.check(response)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw PlatformError.response }
    }
    func resendEmail(email: String) async throws {
#if DEBUG
        if let local { try await local.resend(email: email, type: .signup); return }
#endif
        _ = try await call("email-otp/send-verification-otp", body: ["email": email, "type": "email-verification"])
    }
}
