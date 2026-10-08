//
//  SupabaseClient.swift
//  alpha
//
//  Created by Claude Code on 12/18/24.
//

import Foundation
import Supabase

// Historical name retained at repository call sites; production uses Render.
@MainActor
final class SupabaseClientManager {
    static let shared = SupabaseClientManager()
    let client = AmountlyDataClient()
    private init() {}
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
