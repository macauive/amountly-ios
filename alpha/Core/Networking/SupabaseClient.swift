//
//  SupabaseClient.swift
//  alpha
//
//  Created by Claude Code on 12/18/24.
//

import Foundation
import Supabase

class SupabaseClientManager {
    static let shared = SupabaseClientManager()

    let client: SupabaseClient

    private init() {
        let config = SupabaseConfig.shared

        var projectURL = config.projectURL
        var publicKey = config.anonKey
        var storageKey: String? = nil
#if DEBUG
        // Integration runs are opt-in and can only target the loopback test stack.
        // Never permit an environment override to redirect credentials to a remote host.
        if ProcessInfo.processInfo.environment["AMOUNTLY_LOCAL_TESTING"] == "1" {
            let env = ProcessInfo.processInfo.environment
            guard let raw = env["AMOUNTLY_LOCAL_URL"], let localURL = URL(string: raw),
                  localURL.scheme == "http", localURL.host == "127.0.0.1",
                  [54321, 54331].contains(localURL.port ?? 0), localURL.user == nil,
                  localURL.password == nil, localURL.query == nil, localURL.fragment == nil,
                  localURL.path.isEmpty || localURL.path == "/",
                  let key = env["AMOUNTLY_LOCAL_ANON_KEY"], !key.isEmpty else {
                preconditionFailure("Local integration configuration is missing or not loopback-only.")
            }
            projectURL = localURL; publicKey = key
            storageKey = "amountly-local-integration-session"
        }
#endif
        self.client = SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: publicKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storageKey: storageKey,
                    flowType: .pkce,
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )

        print("🔧 SupabaseClient: Initialized")
    }
}

struct OwnershipScope {
    let userId: String
    let organizationId: String?

    var usesOrganization: Bool {
        organizationId != nil
    }
}

final class OwnershipResolver {
    private let supabase = SupabaseClientManager.shared.client

    func currentScope() async throws -> OwnershipScope {
        let userId = try await supabase.auth.session.user.id.uuidString

        let user: User = try await supabase
            .from("users")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        guard user.isActive else { throw AuthError.notAuthenticated }
        return OwnershipScope(userId: user.id, organizationId: user.accountType == .business ? user.organizationId : nil)
    }
}
