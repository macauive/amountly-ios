//
//  TimeEntry.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import Foundation

enum TimeEntryStatus: String, Codable {
    case draft = "DRAFT"
    case submitted = "SUBMITTED"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case invoiced = "INVOICED"

    var displayName: String {
        switch self {
        case .draft:
            return "Draft"
        case .submitted:
            return "Submitted"
        case .approved:
            return "Approved"
        case .rejected:
            return "Rejected"
        case .invoiced:
            return "Invoiced"
        }
    }
}

enum TimeEntrySource: String, Codable {
    case mobile = "MOBILE"
    case web = "WEB"
    case imported = "IMPORT"
    case api = "API"

    var displayName: String {
        switch self {
        case .mobile:
            return "Mobile"
        case .web:
            return "Web"
        case .imported:
            return "Import"
        case .api:
            return "API"
        }
    }
}

struct TimeEntry: Codable, Identifiable {
    let id: String
    let userId: String
    let projectId: String?
    let taskId: String?
    let startAt: Date
    let endAt: Date
    let durationMinutes: Int
    let notes: String?
    let status: TimeEntryStatus
    let source: TimeEntrySource
    let billableRate: Double?
    let invoiceId: String?
    let createdAt: Date
    let updatedAt: Date

    var version: String? = nil
    var billingLinks: [TimeBillingLink]? = nil
    var isReserved: Bool { invoiceId != nil || (billingLinks ?? []).contains { $0.released_at == nil } }

    // Populated by backend joins
    let project: Project?
    let task: ProjectTask?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case durationMinutes = "duration_minutes"
        case notes
        case status
        case source
        case billableRate = "billable_rate"
        case invoiceId = "invoice_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case billingLinks = "billing_links"
        case project
        case task
        case user
    }

    // Computed properties
    var durationHours: Double {
        return Double(durationMinutes) / 60.0
    }

    var durationFormatted: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let start = formatter.string(from: startAt)
        let end = formatter.string(from: endAt)

        return "\(start) - \(end)"
    }

    var billableAmount: Double? {
        guard let rate = billableRate else { return nil }
        return rate * durationHours
    }
}

// MARK: - Preview Helpers
extension TimeEntry {
    static let preview = TimeEntry(
        id: "entry_1",
        userId: "user_1",
        projectId: "project_1",
        taskId: "task_1",
        startAt: Date().addingTimeInterval(-7200), // 2 hours ago
        endAt: Date(),
        durationMinutes: 120,
        notes: "Working on homepage redesign",
        status: .submitted,
        source: .mobile,
        billableRate: 150.0,
        invoiceId: nil,
        createdAt: Date(),
        updatedAt: Date(),
        project: .preview,
        task: .preview,
        user: .preview
    )

    static let previewDraft = TimeEntry(
        id: "entry_2",
        userId: "user_1",
        projectId: "project_1",
        taskId: "task_2",
        startAt: Date().addingTimeInterval(-3600), // 1 hour ago
        endAt: Date(),
        durationMinutes: 60,
        notes: "Code review and testing",
        status: .draft,
        source: .mobile,
        billableRate: 150.0,
        invoiceId: nil,
        createdAt: Date(),
        updatedAt: Date(),
        project: .preview,
        task: .previewDevelopment,
        user: .preview
    )
}

struct TimeBillingLink: Codable { let invoice_id: String; let released_at: String? }
