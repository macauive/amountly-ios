//
//  ProjectRepository.swift
//  alpha
//
//  Created by Claude Code on 12/18/24.
//

import Foundation
import Supabase

class ProjectRepository {
    private let supabase = SupabaseClientManager.shared.client
    private let ownershipResolver = OwnershipResolver()

    func fetchProjects() async throws -> [Project] {
        let scope = try await ownershipResolver.currentScope()
        var query = supabase
            .from("projects")
            .select("""
                *,
                client:clients(*)
            """)
            .eq("is_active", value: true)
            .is("archived_at", value: nil)

        if let organizationId = scope.organizationId {
            query = query.eq("organization_id", value: organizationId)
        } else {
            query = query.eq("user_id", value: scope.userId)
        }

        var rows: [Project] = []
        while true {
            let response = try await query.order("name").order("id").range(from: rows.count, to: rows.count + 199).execute()
            let batch = try RecordCoding.decoder().decode([Project].self, from: response.data)
            rows += batch
            if batch.count < 200 { return rows }
        }
    }

    func fetchProject(id: String) async throws -> Project {
        let response = try await supabase
            .from("projects")
            .select("""
                *,
                client:clients(*),
                tasks:tasks(*)
            """)
            .eq("id", value: id)
            .single()
            .execute()

        let project: Project = try RecordCoding.decoder().decode(Project.self, from: response.data)
        return project
    }

    func updateProjectBilling(
        id: String,
        billingModel: String?,
        rate: Double?,
        budget: Double?
    ) async throws -> Project {
        let updates = ProjectBillingUpdate(
            billingModel: billingModel,
            rate: rate,
            budget: budget
        )

        let response = try await supabase
            .from("projects")
            .update(updates)
            .eq("id", value: id)
            .select()
            .single()
            .execute()

        let project: Project = try RecordCoding.decoder().decode(Project.self, from: response.data)
        return project
    }

    func deleteProject(id: String) async throws {
        try await supabase
            .from("projects")
            .update(["archived_at": Date().iso8601String])
            .eq("id", value: id)
            .execute()
    }

    func archiveProject(id: String) async throws -> Project {
        let update = ProjectActiveUpdate(isActive: false)

        let response = try await supabase
            .from("projects")
            .update(update)
            .eq("id", value: id)
            .select()
            .single()
            .execute()

        let project: Project = try RecordCoding.decoder().decode(Project.self, from: response.data)
        return project
    }

    func createProject(
        name: String,
        clientId: String?,
        description: String?,
        billingModel: String?,
        rate: Double?,
        budget: Double?,
        color: String?
    ) async throws -> Project {
        let scope = try await ownershipResolver.currentScope()
        let insert = ProjectInsert(
            organizationId: scope.organizationId,
            userId: scope.organizationId == nil ? scope.userId : nil,
            name: name,
            clientId: clientId,
            description: description,
            billingModel: billingModel,
            rate: rate,
            budget: budget,
            color: color
        )

        let response = try await supabase
            .from("projects")
            .insert(insert)
            .select()
            .single()
            .execute()

        let project: Project = try RecordCoding.decoder().decode(Project.self, from: response.data)
        return project
    }

    func updateProject(
        id: String,
        name: String,
        clientId: String?,
        description: String?,
        billingModel: String?,
        rate: Double?,
        budget: Double?,
        color: String?
    ) async throws -> Project {
        let scope = try await ownershipResolver.currentScope()
        let update = ProjectInsert(
            organizationId: scope.organizationId,
            userId: scope.organizationId == nil ? scope.userId : nil,
            name: name,
            clientId: clientId,
            description: description,
            billingModel: billingModel,
            rate: rate,
            budget: budget,
            color: color
        )

        let response = try await supabase
            .from("projects")
            .update(update)
            .eq("id", value: id)
            .select()
            .single()
            .execute()

        let project: Project = try RecordCoding.decoder().decode(Project.self, from: response.data)
        return project
    }
}

// MARK: - Update DTOs

struct ProjectBillingUpdate: Codable {
    let billingModel: String?
    let rate: Double?
    let budget: Double?

    enum CodingKeys: String, CodingKey {
        case billingModel = "billing_model"
        case rate
        case budget
    }
}

struct ProjectActiveUpdate: Codable {
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
    }
}

struct ProjectInsert: Codable {
    let organizationId: String?
    let userId: String?
    let name: String
    let clientId: String?
    let description: String?
    let billingModel: String?
    let rate: Double?
    let budget: Double?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id"
        case userId = "user_id"
        case name
        case clientId = "client_id"
        case description
        case billingModel = "billing_model"
        case rate
        case budget
        case color
    }
}
