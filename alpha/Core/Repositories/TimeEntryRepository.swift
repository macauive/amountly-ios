//
//  TimeEntryRepository.swift
//  alpha
//
//  Created by Claude Code on 12/18/24.
//

import Foundation
import Supabase

class TimeEntryRepository {
    private let supabase = SupabaseClientManager.shared.client
    private let ownershipResolver = OwnershipResolver()

    func fetchTimeEntries(
        startDate: Date? = nil,
        endDate: Date? = nil,
        projectId: String? = nil
    ) async throws -> [TimeEntry] {
        _ = try await ownershipResolver.currentScope()
        var query = supabase
            .from("time_entries")
            .select("""
                *,
                project:projects(*),
                task:tasks(*),
                billing_links:invoice_time_links(invoice_id,released_at)
            """)


        // Apply filters first
        if let startDate = startDate {
            query = query.gte("start_at", value: startDate.iso8601String)
        }

        if let endDate = endDate {
            query = query.lte("start_at", value: endDate.iso8601String)
        }

        if let projectId = projectId {
            query = query.eq("project_id", value: projectId)
        }

        var rows: [TimeEntry] = []
        while true {
            let response = try await query.order("start_at", ascending: false).order("id").range(from: rows.count, to: rows.count + 199).execute()
            var batch = try RecordCoding.decoder().decode([TimeEntry].self, from: response.data)
            let raw = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] ?? []
            for index in batch.indices { batch[index].version = raw[index]["updated_at"] as? String }
            rows += batch
            if batch.count < 200 { return rows }
        }
    }

    func createTimeEntry(
        projectId: String,
        taskId: String?,
        startAt: Date,
        endAt: Date,
        durationMinutes: Int,
        notes: String?,
        source: String
    ) async throws -> TimeEntry {
        let scope = try await ownershipResolver.currentScope()
        let insert = TimeEntryInsert(
            userId: scope.userId,
            projectId: projectId,
            taskId: taskId,
            startAt: startAt.iso8601String,
            endAt: endAt.iso8601String,
            durationMinutes: durationMinutes,
            notes: notes,
            source: source,
            status: "SUBMITTED"
        )

        let response = try await supabase
            .from("time_entries")
            .insert(insert)
            .select()
            .single()
            .execute()

        let entry: TimeEntry = try RecordCoding.decoder().decode(TimeEntry.self, from: response.data)
        return entry
    }

    func deleteTimeEntry(id: String) async throws {
        try await supabase
            .from("time_entries")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func fetchUnbilledTimeEntries(projectId: String? = nil, startDate: Date? = nil, endDate: Date? = nil) async throws -> [TimeEntry] {
        let actor = try await AuthService.shared.getCurrentUser()
        return try await fetchTimeEntries(startDate: startDate, endDate: endDate, projectId: projectId).filter {
            FinancialRules.canInvoiceTime(status: $0.status.rawValue, freelancer: actor.accountType == .freelancer, isOwner: $0.userId == actor.id, reserved: $0.isReserved, hasProject: $0.projectId != nil)
        }
    }

    func updateTimeEntry(
        id: String,
        projectId: String,
        taskId: String?,
        startAt: Date,
        endAt: Date,
        durationMinutes: Int,
        notes: String?,
        billableRate: Double?
    ) async throws -> TimeEntry {
        let update = TimeEntryUpdate(
            projectId: projectId,
            taskId: taskId,
            startAt: startAt.iso8601String,
            endAt: endAt.iso8601String,
            durationMinutes: durationMinutes,
            notes: notes,
            billableRate: billableRate
        )

        let response = try await supabase
            .from("time_entries")
            .update(update)
            .eq("id", value: id)
            .select()
            .single()
            .execute()

        let entry: TimeEntry = try RecordCoding.decoder().decode(TimeEntry.self, from: response.data)
        return entry
    }
}

// MARK: - Insert DTOs

struct TimeEntryInvoiceUpdate: Codable {
    let status: String
    let invoiceId: String

    enum CodingKeys: String, CodingKey {
        case status
        case invoiceId = "invoice_id"
    }
}

struct TimeEntryUpdate: Codable {
    let projectId: String
    let taskId: String?
    let startAt: String
    let endAt: String
    let durationMinutes: Int
    let notes: String?
    let billableRate: Double?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case taskId = "task_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case durationMinutes = "duration_minutes"
        case notes
        case billableRate = "billable_rate"
    }
}

struct TimeEntryInsert: Codable {
    let userId: String
    let projectId: String
    let taskId: String?
    let startAt: String
    let endAt: String
    let durationMinutes: Int
    let notes: String?
    let source: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case durationMinutes = "duration_minutes"
        case notes
        case source
        case status
    }
}

// MARK: - Date Extension

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
