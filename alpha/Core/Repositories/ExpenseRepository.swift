import Foundation
import Supabase

class ExpenseRepository {
    private let supabase = SupabaseClientManager.shared.client
    private func decode(_ data: Data) throws -> [Expense] {
        var rows = try RecordCoding.decoder().decode([Expense].self, from: data)
        let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        for index in rows.indices { rows[index].version = raw[index]["updated_at"] as? String }
        return rows
    }
    func fetchExpenses() async throws -> [Expense] {
        _ = try await OwnershipResolver().currentScope()
        var rows: [Expense] = []
        while true {
            let data = try await supabase.from("expenses").select("*,project:projects(*)").is("archived_at", value: nil)
                .order("expense_date", ascending: false).order("id").range(from: rows.count, to: rows.count + 199).execute().data
            let batch = try decode(data); rows += batch
            if batch.count < 200 { return rows }
        }
    }
    func fetchExpense(id: String) async throws -> Expense {
        let data = try await supabase.from("expenses").select("*,project:projects(*)").eq("id", value: id).execute().data
        guard let row = try decode(data).first else { throw RecordError.conflict }; return row
    }
    private func fields(description: String, amount: Double, currency: String, category: String, merchant: String?, expenseDate: Date, projectId: String?, notes: String?) throws -> [String: AnyJSON] {
        guard amount.isFinite, amount > 0, amount < 100000000, RecordCoding.money(amount) == amount,
              RecordCoding.currencies.contains(currency), ExpenseCategory(rawValue: category) != nil,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, description.count <= 10000 else { throw RecordError.invalid }
        return ["description": .string(description), "amount": .double(amount), "currency": .string(currency), "category": .string(category), "merchant": merchant.map(AnyJSON.string) ?? .null, "expense_date": .string(RecordCoding.day(expenseDate)), "project_id": projectId.map(AnyJSON.string) ?? .null, "notes": notes.map(AnyJSON.string) ?? .null]
    }
    func createExpense(description: String, amount: Double, currency: String, category: String, merchant: String?, expenseDate: Date, projectId: String?, notes: String?, status: String, attempt: RecordAttempt = RecordAttempt(), receiptPath: String? = nil) async throws -> Expense {
        guard status == "DRAFT" else { throw RecordError.invalid }
        var data = try fields(description: description, amount: amount, currency: currency, category: category, merchant: merchant, expenseDate: expenseDate, projectId: projectId, notes: notes)
        data["status"] = .string("DRAFT")
        if let receiptPath { data["receipt_path"] = .string(receiptPath) }
        try await attempt.perform("create_money_record", params: ["p_kind": .string("expenses"), "p_id": .string(attempt.id), "p_data": .object(data)])
        return try await fetchExpense(id: attempt.id)
    }
    func updateExpense(id: String, description: String, amount: Double, currency: String, category: String, merchant: String?, expenseDate: Date, projectId: String?, notes: String?, status: String, expectedVersion: String?, receiptPath: String? = nil) async throws -> Expense {
        guard let expectedVersion else { throw RecordError.conflict }
        var data = try fields(description: description, amount: amount, currency: currency, category: category, merchant: merchant, expenseDate: expenseDate, projectId: projectId, notes: notes)
        guard ["DRAFT", "REJECTED"].contains(status) else { throw RecordError.invalid }
        data["status"] = .string("DRAFT")
        if let receiptPath { guard ReceiptStorage.validPath(receiptPath) else { throw RecordError.invalid }; data["receipt_path"] = .string(receiptPath) }
        do {
            let response = try await supabase.from("expenses").update(data).eq("id", value: id).eq("updated_at", value: expectedVersion).select().single().execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
            return try RecordCoding.decoder().decode(Expense.self, from: response.data)
        } catch { throw RecordError.safe(error) }
    }
    func updateStatus(id: String, status: String, expectedVersion: String?) async throws -> Expense {
        guard let action = ["SUBMITTED": "submit", "APPROVED": "approve", "REJECTED": "reject"][status], let expectedVersion else { throw RecordError.conflict }
        do {
            try await supabase.rpc("review_work_record", params: ["p_kind": "expenses", "p_id": id, "p_action": action, "p_expected_updated_at": expectedVersion]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
            return try await fetchExpense(id: id)
        } catch { throw RecordError.safe(error) }
    }
    func deleteExpense(id: String, expectedVersion: String?) async throws {
        guard let expectedVersion else { throw RecordError.conflict }
        do {
            try await supabase.from("expenses").update(["archived_at": Date().iso8601String]).eq("id", value: id).eq("updated_at", value: expectedVersion).select("id").single().execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
        } catch { throw RecordError.safe(error) }
    }
    func setReviewed(_ expense: Expense, reviewed: Bool) async throws {
        let scope = try await OwnershipResolver().currentScope()
        let user = try await AuthService.shared.getCurrentUser()
        guard user.accountType == .freelancer, user.organizationId == nil, expense.userId.lowercased() == scope.userId.lowercased(),
              [.draft, .rejected].contains(expense.status), UUID(uuidString: expense.id) != nil, let version = expense.version else { throw RecordError.invalid }
        do {
            try await supabase.rpc("set_expense_review", params: ["p_id": AnyJSON.string(expense.id), "p_reviewed": .bool(reviewed), "p_expected_updated_at": .string(version)]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
        } catch { throw RecordError.safe(error) }
    }

}
