import Foundation
import Supabase

class InvoiceRepository {
    private let supabase = SupabaseClientManager.shared.client
    private let ownershipResolver = OwnershipResolver()
    private let selection = "*,client:clients(*),project:projects(*),line_items:invoice_line_items(*),payments:invoice_payments(*,reversal:invoice_payment_reversals(id,reason))"

    private func decode(_ data: Data) throws -> [Invoice] {
        var rows = try RecordCoding.decoder().decode([Invoice].self, from: data)
        let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        for index in rows.indices { rows[index].version = raw[index]["updated_at"] as? String }
        return rows
    }
    func fetchInvoices(status: String? = nil, clientId: String? = nil, limit: Int = 200, offset: Int = 0) async throws -> [Invoice] {
        let scope = try await ownershipResolver.currentScope()
        var query = supabase.from("invoices").select(selection)
        if let organization = scope.organizationId { query = query.eq("organization_id", value: organization) }
        else { query = query.eq("user_id", value: scope.userId) }
        if let status { query = query.eq("status", value: status.uppercased()) }
        if let clientId { query = query.eq("client_id", value: clientId) }
        var rows: [Invoice] = []
        var page = max(0, offset)
        while true {
            let response = try await query.order("created_at", ascending: false).order("id").range(from: page, to: page + 199).execute()
            let batch = try decode(response.data)
            rows += batch
            if batch.count < 200 { return rows }
            page += 200
        }
    }
    func fetchInvoice(id: String) async throws -> Invoice {
        let scope = try await ownershipResolver.currentScope()
        var query = supabase.from("invoices").select(selection).eq("id", value: id)
        if let org = scope.organizationId { query = query.eq("organization_id", value: org) }
        else { query = query.eq("user_id", value: scope.userId) }
        let response = try await query.execute()
        guard let invoice = try decode(response.data).first else { throw RecordError.conflict }
        return invoice
    }
    func createInvoice(clientId: String, projectId: String?, dueDate: Date, lineItems: [InvoiceLineItemCreate], taxRate: Double?, notes: String?, currency: String, attempt: RecordAttempt = RecordAttempt(), issueDate: Date = Date()) async throws -> Invoice {
        guard !lineItems.isEmpty, lineItems.count <= 100, RecordCoding.currencies.contains(currency), lineItems.allSatisfy({ !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.description.count <= 2000 && $0.quantity.isFinite && $0.quantity > 0 && $0.rate.isFinite && $0.rate >= 0 }) else { throw RecordError.invalid }
        let data: [String: AnyJSON] = ["client_id": .string(clientId), "project_id": projectId.map(AnyJSON.string) ?? .null, "invoice_number": .null, "issue_date": .string(RecordCoding.day(issueDate)), "due_date": .string(RecordCoding.day(dueDate)), "tax_rate": .double(taxRate ?? 0), "currency": .string(currency), "notes": .string(notes ?? "")]
        let lines: [AnyJSON] = lineItems.map { .object(["description": .string($0.description), "quantity": .double($0.quantity), "rate": .double($0.rate)]) }
        try await attempt.perform("save_invoice", params: ["p_id": .string(attempt.id), "p_data": .object(data), "p_lines": .array(lines), "p_expected_updated_at": .null])
        return try await fetchInvoice(id: attempt.id)
    }
    func action(_ invoice: Invoice, _ action: String) async throws {
        guard ["issue", "cancel", "delete"].contains(action), let version = invoice.version else { throw RecordError.conflict }
        do {
            try await supabase.rpc("invoice_action", params: ["p_id": invoice.id, "p_action": action, "p_expected_updated_at": version]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
        } catch { throw RecordError.safe(error) }
    }
    func sendInvoice(id: String) async throws -> Invoice {
        let invoice = try await fetchInvoice(id: id)
        try await action(invoice, "issue")
        return try await fetchInvoice(id: id)
    }
    func markAsPaid(id: String) async throws -> Invoice {
        // All payment entry must collect date, method and amount in the payment form.
        throw RecordError(message: "Open Record Payment to record an invoice payment.")
    }
    func createFromTime(entries: [TimeEntry], clientId: String, dueDate: Date, currency: String, attempt: RecordAttempt, issueDate: Date = Date(), taxRate: Double = 0) async throws {
        let actor = try await AuthService.shared.getCurrentUser()
        guard let project = entries.first?.projectId, entries.count <= 100, entries.allSatisfy({
            $0.projectId == project && FinancialRules.canInvoiceTime(status: $0.status.rawValue, freelancer: actor.accountType == .freelancer, isOwner: $0.userId == actor.id, reserved: $0.isReserved, hasProject: true)
        }) else { throw RecordError.invalid }
        try await attempt.perform("create_invoice_from_time", params: ["p_id": .string(attempt.id), "p_entry_ids": .array(entries.map { .string($0.id) }), "p_data": .object(["project_id": .string(project), "client_id": .string(clientId), "issue_date": .string(RecordCoding.day(issueDate)), "due_date": .string(RecordCoding.day(dueDate)), "currency": .string(currency), "tax_rate": .double(taxRate)])])
    }
}
struct InvoiceLineItemCreate { let description: String; let quantity: Double; let rate: Double }
