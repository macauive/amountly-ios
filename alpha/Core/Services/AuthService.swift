import Foundation
import Supabase

@MainActor
final class AuthService {
    static let shared = AuthService()
    private let client: AmountlyDataClient
    private let decoder = RecordCoding.decoder()
    private init() { client = SupabaseClientManager.shared.client }
    init(client: AmountlyDataClient) { self.client = client }
    var isAuthenticated: Bool { client.auth.currentSession != nil }
    var currentSession: Session? { client.auth.currentSession }
    func login(email: String, password: String) async throws -> (User, Organization?) {
        _ = try await client.auth.signIn(email: email, password: password)
        let user = try await getCurrentUser()
        return (user, try await organization(for: user))
    }
    func logout() async throws { try await client.auth.signOut() }
    func signOut() async throws { try await logout() }
    func signInWithPassword(email: String, password: String) async throws { _ = try await client.auth.signIn(email: email, password: password) }
    func signUp(email: String, password: String, name: String) async throws { try await client.auth.signUp(email: email, password: password, data: ["name": .string(name)]) }
    func verifyOTP(email: String, token: String) async throws -> Session { try await client.auth.verifyEmail(email: email, token: token) }
    func resendOTP(email: String) async throws { try await client.auth.resendEmail(email: email) }
    func getUserInfo() async throws -> User? {
        let session = try await client.auth.session
        let data = try await client.from("users").select().eq("id", value: session.user.id.uuidString).execute().data
        let rows = try decoder.decode([User].self, from: data)
        if let user = rows.first, !user.isActive { throw RecordError(message: "This account is inactive.") }
        return rows.first
    }
    func getCurrentUser() async throws -> User {
        guard let user = try await getUserInfo() else { throw AuthError.profileSetupRequired }
        return user
    }
    func restoreAuthenticatedState() async throws -> RestoredAppState? {
#if DEBUG
        if client.localClient != nil && client.auth.currentSession == nil { return nil }
#endif
        do {
            let user = try await getCurrentUser()
            if user.accountType == .business && user.organizationId == nil { throw AuthError.organizationSetupRequired }
            return RestoredAppState(user: user, organization: try await organization(for: user))
        } catch PlatformError.signIn { return nil }
    }
    func checkAuthStatus() async -> Bool { (try? await restoreAuthenticatedState()) != nil }
    func getOrganization(_ id: String) async throws -> Organization {
        try await client.from("organizations").select().eq("id", value: id).single().execute().value
    }
    private func organization(for user: User) async throws -> Organization? {
        guard let id = user.organizationId else { return nil }
        return try await getOrganization(id)
    }
    func userHasOrganization() async throws -> Bool { try await getUserInfo()?.organizationId != nil }
    func createPersonalUser(name: String, accountType: AccountType) async throws -> User {
        // An existing profile is authoritative. Never overwrite its role/workspace.
        if let user = try await getUserInfo() { return user }
        let session = try await client.auth.session
        let insert = PersonalUserInsert(id: session.user.id.uuidString, email: session.user.email ?? "", name: String(name.prefix(120)), accountType: accountType.rawValue, role: "MEMBER")
        do { try await client.from("users").insert(insert).execute() }
        catch { if (error as? PostgrestError)?.code != "23505" { throw RecordError.safe(error) } }
        return try await getCurrentUser()
    }
    func setupOrganization(name: String, companyName: String) async throws -> (User, Organization) {
        let user = try await getCurrentUser()
        guard user.accountType == .business else { throw RecordError.invalid }
        if let id = user.organizationId { return (user, try await getOrganization(id)) }
        guard !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, companyName.count <= 200 else { throw RecordError.invalid }
        let response = try await client.from("organizations").insert(["name": companyName]).select().single().execute()
        let org = try decoder.decode(Organization.self, from: response.data)
        try await client.from("users").update(["organization_id": org.id, "role": "OWNER"]).eq("id", value: user.id).execute()
        return (try await getCurrentUser(), org)
    }
    func observeAuthStateChanges(handler: @escaping (AuthChangeEvent, Session?) -> Void) -> Task<Void, Never> {
        Task { for await (event, session) in client.auth.authStateChanges { handler(event, session) } }
    }
    func requestPasswordReset(email: String) async throws { _ = try await client.auth.call("email-otp/request-password-reset", body: ["email": email]) }
    func resetPassword(email: String, otp: String, password: String) async throws {
        guard (12...128).contains(password.utf16.count), otp.count == 6, otp.utf8.allSatisfy({ (48...57).contains($0) }) else { throw PlatformError.input }
        _ = try await client.auth.call("email-otp/reset-password", body: ["email": email, "otp": otp, "password": password])
    }
}

// MARK: - Auth Errors

enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case profileSetupRequired
    case organizationSetupRequired
    case signUpFailed
    case sessionNotEstablished
    case restoreFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .profileSetupRequired, .organizationSetupRequired: return "Finish setting up your account to continue."
        case .notAuthenticated:
            return "User is not authenticated"
        case .signUpFailed:
            return "Failed to sign up user"
        case .sessionNotEstablished:
            return "Session could not be established after verification"
        case .restoreFailed:
            return "Could not restore your session. Sign in again."
        }
    }
}

struct RestoredAppState {
    let user: User
    let organization: Organization?
}

// MARK: - Insert DTOs

struct OrganizationInsert: Codable {
    let name: String
    let email: String
    let ownerId: String

    enum CodingKeys: String, CodingKey {
        case name
        case email
        case ownerId = "owner_id"
    }
}

struct UserInsert: Codable {
    let id: String
    let organizationId: String
    let email: String
    let name: String
    let role: String
    let accountType: String

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case email
        case name
        case role
        case accountType = "account_type"
    }
}

struct PersonalUserInsert: Codable {
    let id: String
    let email: String
    let name: String
    let accountType: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case accountType = "account_type"
        case role
    }
}
