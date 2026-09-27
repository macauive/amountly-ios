//
//  AuthService.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//  Updated for Supabase on 12/18/24.
//

import Foundation
import Supabase

@MainActor
class AuthService {
    static let shared = AuthService()

    private let supabase = SupabaseClientManager.shared.client

    private init() {}

    // MARK: - Authentication State

    var isAuthenticated: Bool {
        supabase.auth.currentSession != nil
    }

    var currentSession: Session? {
        supabase.auth.currentSession
    }

    // MARK: - Login

    func login(email: String, password: String) async throws -> (User, Organization?) {
        // Sign in with Supabase Auth
        let session = try await supabase.auth.signIn(
            email: email,
            password: password
        )

        return try await fetchAuthenticatedAppState(for: session)
    }

    // MARK: - Logout

    func logout() async throws {
        try await supabase.auth.signOut()
    }

    // MARK: - Get Current User

    func getCurrentUser() async throws -> User {
        guard let session = supabase.auth.currentSession else {
            throw AuthError.notAuthenticated
        }

        return try await fetchUser(for: session)
    }

    // MARK: - Get User Info (returns nil if not exists)

    func getUserInfo() async throws -> User? {
        guard let userId = supabase.auth.currentSession?.user.id else {
            throw AuthError.notAuthenticated
        }

        let response = try await supabase.from("users").select().eq("id", value: userId.uuidString).execute()
        let users = try decoder.decode([User].self, from: response.data)
        if let user = users.first, !user.isActive { throw RecordError(message: "This account is inactive.") }
        return users.first

    }

    // MARK: - Restore Authenticated State

    func restoreAuthenticatedState() async throws -> RestoredAppState? {
        guard let session = supabase.auth.currentSession else {
            return nil
        }

        do {
            let (user, organization) = try await fetchAuthenticatedAppState(for: session)
            return RestoredAppState(user: user, organization: organization)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            print("Authentication operation failed; retry or sign in again.")
            throw AuthError.restoreFailed(underlying: error)
        }
    }

    // MARK: - Create Personal User (no organization)

    func createPersonalUser(name: String, accountType: AccountType) async throws -> User {
        guard let session = supabase.auth.currentSession else {
            throw AuthError.notAuthenticated
        }

        let userId = session.user.id
        let email = session.user.email ?? ""

        print("👤 AuthService.createPersonalUser: Creating \(accountType.displayName) user")

        let userInsert = PersonalUserInsert(
            id: userId.uuidString,
            email: email,
            name: name,
            accountType: accountType.rawValue,
            role: "MEMBER"
        )

        let response = try await supabase
            .from("users")
            .insert(userInsert)
            .select()
            .single()
            .execute()

        let user = try decoder.decode(User.self, from: response.data)
        print("✅ AuthService.createPersonalUser: Personal user created")

        return user
    }

    // MARK: - Get Organization

    func getOrganization(_ organizationId: String) async throws -> Organization {
        let organization: Organization = try await supabase
            .from("organizations")
            .select()
            .eq("id", value: organizationId)
            .single()
            .execute()
            .value

        return organization
    }

    // MARK: - Session Management

    func observeAuthStateChanges(handler: @escaping (AuthChangeEvent, Session?) -> Void) -> Task<Void, Never> {
        Task {
            for await (event, _session) in supabase.auth.authStateChanges {
                await MainActor.run {
                    handler(event, _session)
                }
            }
        }
    }

    // MARK: - Check Auth Status

    func checkAuthStatus() async -> Bool {
        do {
            return try await restoreAuthenticatedState() != nil
        } catch {
            return false
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, name: String) async throws {
        // Create auth user with name in metadata
        print("AuthService.signUp: Creating user")

        _ = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["name": .string(name)]
        )
        print("✅ AuthService.signUp: User created")
    }

    // MARK: - Sign In with Password

    func signInWithPassword(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)

    }

    // MARK: - Sign Out

    func signOut() async throws {
        print("🔐 AuthService.signOut: Signing out")
        try await supabase.auth.signOut()
        print("✅ AuthService.signOut: Sign out successful")
    }

    // MARK: - Email Verification (OTP)

    func verifyOTP(email: String, token: String) async throws -> Session {
        print("🔐 AuthService.verifyOTP: Starting OTP verification")

        let response = try await supabase.auth.verifyOTP(
            email: email,
            token: token,
            type: .signup
        )

        print("🔐 AuthService.verifyOTP: OTP verified for user: \(response.user.id)")
        print("🔐 AuthService.verifyOTP: User role from response: \(response.user.role ?? "none")")

        // Session might be in the response or need to be fetched
        if let responseSession = response.session {
            print("🔐 AuthService.verifyOTP: Session found in response")
            print("🔐 AuthService.verifyOTP: Token type: \(responseSession.tokenType)")

            // CRITICAL: Refresh the session to get a new JWT with the "authenticated" role
            // After OTP verification, the JWT might still have role: "anon"
            // Refreshing ensures we get a JWT with role: "authenticated"
            print("🔄 AuthService.verifyOTP: Refreshing session to get authenticated role...")

            do {
                let refreshedSession = try await supabase.auth.refreshSession()
                print("✅ AuthService.verifyOTP: Session refreshed")

                // Verify the refreshed session is stored
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                if let storedSession = supabase.auth.currentSession {
                    print("✅ AuthService.verifyOTP: Refreshed session stored in client: \(storedSession.user.id)")
                    print("✅ AuthService.verifyOTP: Refreshed session verified")
                } else {
                    print("⚠️ AuthService.verifyOTP: WARNING - Refreshed session not stored in client!")
                }

                return refreshedSession
            } catch {
                print("Authentication operation failed; retry or sign in again.")
                print("⚠️ AuthService.verifyOTP: Falling back to original session")

                // Fall back to original session if refresh fails
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                if let storedSession = supabase.auth.currentSession {
                    print("✅ AuthService.verifyOTP: Original session stored in client: \(storedSession.user.id)")
                }

                return responseSession
            }
        }

        // Verify session is now available from currentSession
        guard let currentSession = supabase.auth.currentSession else {
            print("⚠️ AuthService.verifyOTP: Warning - session not immediately available after verifyOTP")
            // Force a small delay for session to be stored
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            guard let retrySession = supabase.auth.currentSession else {
                print("❌ AuthService.verifyOTP: Session not available after retry")
                throw AuthError.sessionNotEstablished
            }
            print("✅ AuthService.verifyOTP: Session available after retry")
            return retrySession
        }

        print("✅ AuthService.verifyOTP: Session immediately available from currentSession")
        return currentSession
    }

    func resendOTP(email: String) async throws {
        print("📧 AuthService: Resending OTP")
        try await supabase.auth.resend(email: email, type: .signup)
        print("✅ AuthService: OTP resend request sent")
    }

    // MARK: - Organization Check

    func userHasOrganization() async throws -> Bool {
        guard let userId = supabase.auth.currentSession?.user.id else {
            print("⚠️ AuthService.userHasOrganization: No active session")
            return false
        }

        print("🔍 AuthService.userHasOrganization: Checking for user: \(userId)")

        do {
            let response = try await supabase
                .from("users")
                .select("organization_id")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()

            struct OrganizationPresence: Decodable {
                let organizationId: String?

                enum CodingKeys: String, CodingKey {
                    case organizationId = "organization_id"
                }
            }

            let presence = try decoder.decode(OrganizationPresence.self, from: response.data)
            print("✅ AuthService.userHasOrganization: User exists; organization_id=\(presence.organizationId ?? "nil")")
            return presence.organizationId != nil
        } catch {
            // User doesn't exist in users table yet (no organization)
            print("Authentication operation failed; retry or sign in again.")
            return false
        }
    }

    // MARK: - Setup Organization (Called after signup during onboarding)

    func setupOrganization(name: String, companyName: String) async throws -> (User, Organization) {
        print("🏢 AuthService.setupOrganization: Starting organization setup")

        // Try to get session with retry
        var session: Session?
        var attempts = 0
        let maxAttempts = 3

        while attempts < maxAttempts {
            session = supabase.auth.currentSession
            if session != nil {
                break
            }

            attempts += 1
            print("⚠️ AuthService.setupOrganization: Attempt \(attempts)/\(maxAttempts) - Session not found, waiting...")
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        guard let session = session else {
            print("❌ AuthService.setupOrganization: No active session found after \(maxAttempts) attempts")
            throw AuthError.notAuthenticated
        }

        let userId = session.user.id
        let email = session.user.email ?? ""
        print("✅ AuthService.setupOrganization: Session found for user: \(userId)")
        print("📧 AuthService.setupOrganization: Email present: \(!email.isEmpty)")
        print("🔐 AuthService.setupOrganization: Email confirmed: \(session.user.emailConfirmedAt != nil)")

        // Step 1: Create organization
        print("AuthService.setupOrganization: Creating organization")
        let orgInsert = OrganizationInsert(
            name: companyName,
            email: email,
            ownerId: userId.uuidString
        )

        do {
            // DEBUG: Print the actual request details
            print("🔍 AuthService.setupOrganization: About to insert organization")

            let orgResponse = try await supabase
                .from("organizations")
                .insert(orgInsert)
                .select()
                .single()
                .execute()

            let organization: Organization = try decoder.decode(Organization.self, from: orgResponse.data)
            print("✅ AuthService.setupOrganization: Organization created with ID: \(organization.id)")

            // Step 2: Create user record linked to organization
            print("👤 AuthService.setupOrganization: Creating user record")
            let userInsert = UserInsert(
                id: userId.uuidString,
                organizationId: organization.id,
                email: email,
                name: name,
                role: "OWNER",
                accountType: "business"
            )

            let userResponse = try await supabase
                .from("users")
                .insert(userInsert)
                .select()
                .single()
                .execute()

            let user: User = try decoder.decode(User.self, from: userResponse.data)
            print("✅ AuthService.setupOrganization: User record created")
            print("✅ AuthService.setupOrganization: Organization setup complete!")

            return (user, organization)
        } catch {
            print("AuthService.setupOrganization: Failed to complete setup.")

            throw error
        }
    }

    // MARK: - Private Helpers

    private let decoder = RecordCoding.decoder()

    private func fetchAuthenticatedAppState(for session: Session) async throws -> (User, Organization?) {
        let user = try await fetchUser(for: session)
        let organization = try await fetchOrganizationIfNeeded(for: user)
        return (user, organization)
    }

    private func fetchUser(for session: Session) async throws -> User {
        let response = try await supabase
            .from("users")
            .select()
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()

        let user = try decoder.decode(User.self, from: response.data)
        guard user.isActive else { throw RecordError(message: "This account is inactive.") }
        return user
    }

    private func fetchOrganizationIfNeeded(for user: User) async throws -> Organization? {
        guard let organizationId = user.organizationId else {
            return nil
        }

        return try await getOrganization(organizationId)
    }
}

// MARK: - Auth Errors

enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case signUpFailed
    case sessionNotEstablished
    case restoreFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .signUpFailed:
            return "Failed to sign up user"
        case .sessionNotEstablished:
            return "Session could not be established after verification"
        case .restoreFailed(let underlying):
            return "Failed to restore authenticated app state: \(underlying.localizedDescription)"
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
