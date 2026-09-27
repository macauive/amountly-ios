//
//  Invoice.swift
//  alpha
//
//  Created by Claude Code on 11/25/25.
//

import Foundation

// MARK: - Invoice Line Item

struct InvoiceLineItem: Codable, Identifiable {
    let id: String
    let invoiceId: String
    let description: String
    let quantity: Double
    let rate: Double
    let amount: Double
    let order: Int
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId = "invoice_id"
        case description
        case quantity
        case rate
        case amount
        case order
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var total: Double {
        quantity * rate
    }
}

// MARK: - Preview Helpers
extension InvoiceLineItem {
    static let preview = InvoiceLineItem(
        id: "line_1",
        invoiceId: "invoice_1",
        description: "Website Design & Development",
        quantity: 40,
        rate: 150.0,
        amount: 6000.0,
        order: 0,
        createdAt: Date(),
        updatedAt: Date()
    )

    static let preview2 = InvoiceLineItem(
        id: "line_2",
        invoiceId: "invoice_1",
        description: "Logo Design",
        quantity: 1,
        rate: 500.0,
        amount: 500.0,
        order: 1,
        createdAt: Date(),
        updatedAt: Date()
    )
}

// MARK: - Invoice Status

enum InvoiceStatus: String, Codable {
    case draft = "draft"
    case sent = "sent"
    case paid = "paid"
    case overdue = "overdue"
    case cancelled = "cancelled"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()

        guard let status = InvoiceStatus(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid invoice status: \(rawValue)"
            )
        }

        self = status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .draft:
            return "Draft"
        case .sent:
            return "Sent"
        case .paid:
            return "Paid"
        case .overdue:
            return "Overdue"
        case .cancelled:
            return "Cancelled"
        }
    }
}

struct Invoice: Codable, Identifiable {
    let id: String
    let organizationId: String?
    let userId: String?
    let clientId: String?
    let projectId: String?
    let invoiceNumber: String
    let issueDate: Date
    let dueDate: Date
    let subtotal: Double
    let taxRate: Double?
    let taxAmount: Double?
    let total: Double
    let currency: String
    let status: InvoiceStatus
    let notes: String?
    let paidAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    var version: String? = nil
    var payments: [InvoicePayment]? = nil
    var issuedSnapshot: InvoiceSnapshot? = nil
    var displayClientName: String? { if let client = issuedSnapshot?.client { return client.name }; return client?.name }
    var displayClientEmail: String? { if let client = issuedSnapshot?.client { return client.email }; return client?.email }
    var displayClientAddress: String? { if let client = issuedSnapshot?.client { return client.address }; return client?.address }
    var lastPaymentDate: Date? { (payments ?? []).filter { !$0.isReversed }.map(\.paid_on).max() }
    var amountPaid: Double { RecordCoding.money((payments ?? []).filter { !$0.isReversed }.reduce(0) { $0 + $1.amount }) }
    var balanceDue: Double { status == .paid || status == .cancelled ? 0 : max(0, RecordCoding.money(total - amountPaid)) }
    var displayStatus: InvoiceStatus { [.sent, .overdue].contains(status) ? (isOverdue ? .overdue : .sent) : status }
    var needsLegacyReview: Bool { status == .paid && (payments ?? []).isEmpty }

    // Populated by backend joins
    let client: Client?
    let project: Project?
    let lineItems: [InvoiceLineItem]?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case userId = "user_id"
        case clientId = "client_id"
        case projectId = "project_id"
        case invoiceNumber = "invoice_number"
        case issueDate = "issue_date"
        case dueDate = "due_date"
        case subtotal
        case taxRate = "tax_rate"
        case taxAmount = "tax_amount"
        case total
        case currency
        case status
        case notes
        case paidAt = "paid_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case payments
        case issuedSnapshot = "issued_snapshot"
        case client
        case project
        case lineItems = "line_items"
    }

    // Computed properties
    var totalFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: total)) ?? String(format: "$%.2f", total)
    }

    var isOverdue: Bool {
        guard [.sent, .overdue].contains(status), balanceDue > 0 else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var daysUntilDue: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: dueDate)
        return components.day ?? 0
    }
}

// MARK: - Preview Helpers
extension Invoice {
    static let preview = Invoice(
        id: "invoice_1",
        organizationId: "org_1",
        userId: "user_1",
        clientId: "client_1",
        projectId: "project_1",
        invoiceNumber: "INV-2025-001",
        issueDate: Date(),
        dueDate: Date().addingTimeInterval(60 * 60 * 24 * 30), // 30 days
        subtotal: 15000.00,
        taxRate: 8.25,
        taxAmount: 1237.50,
        total: 16237.50,
        currency: "USD",
        status: .sent,
        notes: "Thank you for your business!",
        paidAt: nil,
        createdAt: Date(),
        updatedAt: Date(),
        client: .preview,
        project: .preview,
        lineItems: [.preview, .preview2]
    )
}
