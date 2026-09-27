//
//  Expense.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import Foundation

enum ExpenseStatus: String, Codable {
    case draft = "DRAFT"
    case submitted = "SUBMITTED"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case reimbursed = "REIMBURSED"

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
        case .reimbursed:
            return "Reimbursed"
        }
    }
}

enum ExpenseCategory: String, Codable, CaseIterable {
    case officeSupplies = "OFFICE_SUPPLIES"
    case travel = "TRAVEL"
    case meals = "MEALS"
    case software = "SOFTWARE"
    case hardware = "HARDWARE"
    case marketing = "MARKETING"
    case utilities = "UTILITIES"
    case other = "OTHER"

    var displayName: String {
        switch self {
        case .officeSupplies:
            return "Office Supplies"
        case .travel:
            return "Travel"
        case .meals:
            return "Meals"
        case .software:
            return "Software"
        case .hardware:
            return "Hardware"
        case .marketing:
            return "Marketing"
        case .utilities:
            return "Utilities"
        case .other:
            return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .officeSupplies:
            return "pencil.and.ruler"
        case .travel:
            return "airplane"
        case .meals:
            return "fork.knife"
        case .software:
            return "apps.iphone"
        case .hardware:
            return "desktopcomputer"
        case .marketing:
            return "megaphone"
        case .utilities:
            return "bolt"
        case .other:
            return "square.grid.2x2"
        }
    }
}

struct Expense: Codable, Identifiable {
    let id: String
    let userId: String
    let projectId: String?
    let taskId: String?
    let amount: Double
    let currency: String
    let category: ExpenseCategory
    let description: String
    let merchant: String?
    let expenseDate: Date
    let receiptUrl: String?
    let status: ExpenseStatus
    let notes: String?
    let invoiceId: String?
    let createdAt: Date
    let updatedAt: Date

    var version: String? = nil
    var receiptPath: String? = nil

    // Populated by backend joins
    let project: Project?
    let task: ProjectTask?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case amount
        case currency
        case category
        case description
        case merchant
        case expenseDate = "expense_date"
        case receiptUrl = "receipt_url"
        case receiptPath = "receipt_path"
        case status
        case notes
        case invoiceId = "invoice_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case project
        case task
        case user
    }

    // Computed properties
    var amountFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    var hasReceipt: Bool {
        receiptPath != nil || receiptUrl != nil
    }
}

// MARK: - Preview Helpers
extension Expense {
    static let preview = Expense(
        id: "expense_1",
        userId: "user_1",
        projectId: "project_1",
        taskId: nil,
        amount: 125.50,
        currency: "USD",
        category: .officeSupplies,
        description: "Office supplies for new office setup",
        merchant: "Staples",
        expenseDate: Date(),
        receiptUrl: nil,
        status: .submitted,
        notes: nil,
        invoiceId: nil,
        createdAt: Date(),
        updatedAt: Date(),
        project: .preview,
        task: nil,
        user: .preview
    )

    static let previewTravel = Expense(
        id: "expense_2",
        userId: "user_1",
        projectId: "project_1",
        taskId: nil,
        amount: 450.00,
        currency: "USD",
        category: .travel,
        description: "Flight to client meeting",
        merchant: "United Airlines",
        expenseDate: Date().addingTimeInterval(-86400), // Yesterday
        receiptUrl: "https://example.com/receipt.pdf",
        status: .approved,
        notes: "Client meeting in NYC",
        invoiceId: nil,
        createdAt: Date(),
        updatedAt: Date(),
        project: .preview,
        task: nil,
        user: .preview
    )
}
