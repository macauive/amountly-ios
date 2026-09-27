//
//  BillLineItem.swift
//  alpha
//
//  Created by Claude Code on 12/18/25.
//

import Foundation
import Supabase

struct BillLineItem: Identifiable, Codable {
    let id: UUID
    var description: String
    var amount: Double
    var category: String

    init(id: UUID = UUID(), description: String = "", amount: Double = 0.0, category: String = "OFFICE_SUPPLIES") {
        self.id = id
        self.description = description
        self.amount = amount
        self.category = category
    }
}

enum BillStatus: String, Codable, CaseIterable {
    case upcoming
    case due
    case paid
    case overdue
    case cancelled

    var displayName: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .due: return "Due"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .cancelled: return "Cancelled"
        }
    }
}

enum BillRecurrence: String, Codable, CaseIterable {
    case none = "once", weekly, biweekly, monthly, quarterly, yearly = "annually"
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let normalized = value == "none" ? "once" : value == "yearly" ? "annually" : value
        guard let recurrence = BillRecurrence(rawValue: normalized) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported recurrence") }
        self = recurrence
    }
    var displayName: String { switch self {
        case .none: return "Once"
        case .weekly: return "Weekly"
        case .biweekly: return "Every two weeks"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Annually"
    } }
}

struct Bill: Identifiable, Codable {
    let id: String
    let userId: String
    let name: String
    let payee: String
    let amount: Double
    let currency: String
    let category: String
    let dueDate: Date
    let status: BillStatus
    let recurrence: BillRecurrence
    let notes: String?
    let paidAt: Date?
    let autoPay: Bool
    let createdAt: Date?
    let updatedAt: Date?
    var version: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case payee
        case amount
        case currency
        case category
        case dueDate = "due_date"
        case status
        case recurrence
        case notes
        case paidAt = "paid_at"
        case autoPay = "auto_pay"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        payee = try container.decode(String.self, forKey: .payee)
        amount = try container.decode(Double.self, forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        category = try container.decode(String.self, forKey: .category)
        dueDate = try Self.decodeDate(container, key: .dueDate) ?? Date()
        status = try container.decodeIfPresent(BillStatus.self, forKey: .status) ?? .upcoming
        recurrence = try container.decodeIfPresent(BillRecurrence.self, forKey: .recurrence) ?? .monthly
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        paidAt = try Self.decodeDate(container, key: .paidAt)
        autoPay = try container.decodeIfPresent(Bool.self, forKey: .autoPay) ?? false
        createdAt = try Self.decodeDate(container, key: .createdAt)
        updatedAt = try Self.decodeDate(container, key: .updatedAt)
        version = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    init(
        id: String,
        userId: String,
        name: String,
        payee: String,
        amount: Double,
        currency: String = "USD",
        category: String,
        dueDate: Date,
        status: BillStatus,
        recurrence: BillRecurrence,
        notes: String?,
        paidAt: Date?,
        autoPay: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.payee = payee
        self.amount = amount
        self.currency = currency
        self.category = category
        self.dueDate = dueDate
        self.status = status
        self.recurrence = recurrence
        self.notes = notes
        self.paidAt = paidAt
        self.autoPay = autoPay
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var amountFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    var effectiveStatus: BillStatus {
        if status == .paid || status == .cancelled { return status }
        let today = Calendar.current.startOfDay(for: Date())
        if dueDate < today { return .overdue }
        return Calendar.current.isDate(dueDate, inSameDayAs: today) ? .due : .upcoming
    }
    var isPaid: Bool {
        status == .paid
    }

    var isOverdue: Bool {
        !isPaid && status != .cancelled && dueDate < Calendar.current.startOfDay(for: Date())
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        guard let date = RecordCoding.parseDate(value) else { throw RecordError.invalid }
        return date
    }
}

struct BillInsert: Codable {
    let userId: String
    let name: String
    let payee: String
    let amount: Double
    let currency: String
    let category: String
    let dueDate: String
    let status: String
    let recurrence: String
    let notes: String?
    let autoPay: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case payee
        case amount
        case currency
        case category
        case dueDate = "due_date"
        case status
        case recurrence
        case notes
        case autoPay = "auto_pay"
    }
}

struct BillStatusUpdate: Codable {
    let status: String
    let paidAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case paidAt = "paid_at"
    }
}

final class BillRepository {
    private let supabase = SupabaseClientManager.shared.client
    func fetchBills() async throws -> [Bill] {
        let scope = try await OwnershipResolver().currentScope()
        var rows: [Bill] = []
        while true {
            let data = try await supabase.from("bills").select().eq("user_id", value: scope.userId)
                .order("due_date").order("id").range(from: rows.count, to: rows.count + 199).execute().data
            let batch = try RecordCoding.decoder().decode([Bill].self, from: data)
            rows += batch
            if batch.count < 200 { return rows }
        }
    }
    func createBill(name: String, payee: String, amount: Double, category: String, dueDate: Date, recurrence: BillRecurrence, notes: String?, currency: String = "USD", autoPay: Bool = false, attempt: RecordAttempt = RecordAttempt()) async throws -> Bill {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              amount.isFinite, amount > 0, amount < 100000000, RecordCoding.money(amount) == amount, RecordCoding.currencies.contains(currency) else { throw RecordError.invalid }
        try await attempt.perform("create_money_record", params: ["p_kind": .string("bills"), "p_id": .string(attempt.id), "p_data": .object([
            "name": .string(name), "payee": .string(payee), "amount": .double(amount), "currency": .string(currency), "category": .string(category), "due_date": .string(RecordCoding.day(dueDate)), "status": .string("upcoming"), "recurrence": .string(recurrence.rawValue), "auto_pay": .bool(autoPay), "notes": .string(notes ?? "")])])
        return try await fetchBill(id: attempt.id)
    }
    func fetchBill(id: String) async throws -> Bill {
        let scope = try await OwnershipResolver().currentScope()
        return try await supabase.from("bills").select().eq("id", value: id).eq("user_id", value: scope.userId).single().execute().value
    }
    func action(_ bill: Bill, action: String, paidOn: Date? = nil) async throws {
        guard let version = bill.version, ["pay", "cancel"].contains(action) else { throw RecordError.conflict }
        do {
            try await supabase.rpc("bill_action", params: ["p_id": AnyJSON.string(bill.id), "p_action": .string(action), "p_expected_updated_at": .string(version), "p_paid_on": paidOn.map { .string(RecordCoding.day($0)) } ?? .null]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
        } catch { throw RecordError.safe(error) }
    }
}
