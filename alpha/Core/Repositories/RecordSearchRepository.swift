import Foundation

extension SearchRecord {
    init(_ row: Expense) { self.init(recordID: row.id, kind: .expenses, label: row.merchant?.isEmpty == false ? row.merchant! : row.description, detail: row.description, currency: row.currency, date: RecordCoding.day(row.expenseDate), status: row.status.rawValue, amount: row.amount, receipt: row.hasReceipt) }
    init(_ row: Invoice) { self.init(recordID: row.id, kind: .invoices, label: row.invoiceNumber, detail: row.displayClientName ?? row.notes ?? "", currency: row.currency, date: RecordCoding.day(row.issueDate), status: row.status.rawValue.uppercased(), amount: row.total, receipt: false) }
    init(_ row: Bill) { self.init(recordID: row.id, kind: .bills, label: row.name, detail: row.notes ?? "", currency: row.currency, date: RecordCoding.day(row.dueDate), status: row.effectiveStatus.rawValue, amount: row.amount, receipt: false) }
    init(_ row: VendorBill) { self.init(recordID: row.id, kind: .vendorBills, label: row.bill_number, detail: row.vendor?.name ?? row.notes ?? "", currency: row.currency ?? "USD", date: RecordCoding.calendarDay(row.due_date), status: row.displayStatus.rawValue, amount: row.total, receipt: false) }
}
@MainActor
final class RecordSearchRepository {
    func load(actor: User) async throws -> [SearchRecord] {
        let current = try await AuthService.shared.getCurrentUser()
        guard current.id == actor.id, current.organizationId == actor.organizationId, current.accountType == actor.accountType, current.role == actor.role else { throw PlatformError.signIn }
        var rows: [SearchRecord] = []
        if actor.hasCapability(.viewOwnExpenses) { rows += try await ExpenseRepository().fetchExpenses().map { SearchRecord($0) } }
        if actor.hasCapability(.viewInvoices) { rows += try await InvoiceRepository().fetchInvoices().map { SearchRecord($0) } }
        if actor.accountType == .personal && actor.hasCapability(.viewBills) { rows += try await BillRepository().fetchBills().map { SearchRecord($0) } }
        if actor.hasCapability(.viewAccountsPayable) { rows += try await VendorRepository().bills().map { SearchRecord($0) } }
        try rows.forEach { try $0.validate() }
        return rows
    }
}
