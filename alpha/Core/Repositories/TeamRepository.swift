//
//  TeamRepository.swift
//  alpha
//
//  Created by Claude Code on 2/1/26.
//

import Foundation
import Supabase

class TeamRepository {
    private let supabase = SupabaseClientManager.shared.client

    func fetchMembers() async throws -> [TeamMember] {
        let response = try await supabase
            .from("organization_members")
            .select("""
                *,
                user:users(*)
            """)
            .order("created_at", ascending: false)
            .execute()

        let members: [TeamMember] = try RecordCoding.decoder().decode([TeamMember].self, from: response.data)
        return members
    }

    func fetchAuditLog(limit: Int = 50) async throws -> [AuditLogEntry] {
        let response = try await supabase
            .from("audit_log")
            .select("""
                *,
                user:users(*)
            """)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let entries: [AuditLogEntry] = try RecordCoding.decoder().decode([AuditLogEntry].self, from: response.data)
        return entries
    }

    func removeMember(id: String) async throws {
        try await supabase
            .from("organization_members")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func updateMemberRole(id: String, role: String) async throws -> TeamMember {
        let update = TeamMemberRoleUpdate(role: role)

        let response = try await supabase
            .from("organization_members")
            .update(update)
            .eq("id", value: id)
            .select("""
                *,
                user:users(*)
            """)
            .single()
            .execute()

        let member: TeamMember = try RecordCoding.decoder().decode(TeamMember.self, from: response.data)
        return member
    }

    func sendInvite(email: String, role: String) async throws {
        let invite = InvitationInsert(email: email, role: role)

        try await supabase
            .from("invitations")
            .insert(invite)
            .execute()
    }
}

// MARK: - DTOs

struct TeamMemberRoleUpdate: Codable {
    let role: String
}

struct InvitationInsert: Codable {
    let email: String
    let role: String
}
