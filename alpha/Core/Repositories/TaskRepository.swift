//
//  TaskRepository.swift
//  alpha
//
//  Created by Claude Code on 2/1/26.
//

import Foundation
import Supabase

class TaskRepository {
    private let supabase = SupabaseClientManager.shared.client

    func fetchTasks(projectId: String) async throws -> [ProjectTask] {
        let response = try await supabase
            .from("tasks")
            .select("*")
            .eq("project_id", value: projectId)
            .order("name")
            .execute()

        let tasks: [ProjectTask] = try RecordCoding.decoder().decode([ProjectTask].self, from: response.data)
        return tasks
    }

    func fetchTask(id: String) async throws -> ProjectTask {
        let response = try await supabase
            .from("tasks")
            .select("*")
            .eq("id", value: id)
            .single()
            .execute()

        let task: ProjectTask = try RecordCoding.decoder().decode(ProjectTask.self, from: response.data)
        return task
    }

    func createTask(
        projectId: String,
        name: String,
        description: String?,
        rate: Double?
    ) async throws -> ProjectTask {
        let insert = TaskInsert(
            projectId: projectId,
            name: name,
            description: description,
            rate: rate
        )

        let response = try await supabase
            .from("tasks")
            .insert(insert)
            .select()
            .single()
            .execute()

        let task: ProjectTask = try RecordCoding.decoder().decode(ProjectTask.self, from: response.data)
        return task
    }

    func deleteTask(id: String) async throws {
        try await supabase
            .from("tasks")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

// MARK: - Insert DTOs

struct TaskInsert: Codable {
    let projectId: String
    let name: String
    let description: String?
    let rate: Double?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case name
        case description
        case rate
    }
}
