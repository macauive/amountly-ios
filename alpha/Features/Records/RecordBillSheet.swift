import SwiftUI

struct RecordBillSheet: View {
    let row: SearchRecord
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var bill: Bill?
    @State private var supplier: VendorBill?
    @State private var error: String?
    @State private var paidOn = Date()
    @State private var action: String?
    @State private var saving = false
    @State private var history = false
    private var mayChange: Bool { row.kind == .bills ? appState.hasCapability(.manageBillPayments) : appState.hasCapability(.manageBills) }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red) }
                if let bill {
                    Text(bill.name).font(.headline); Text(bill.payee)
                    Text("\(bill.amountFormatted) · Due \(RecordCoding.day(bill.dueDate)) · \(bill.effectiveStatus.displayName)")
                    if let notes = bill.notes { Text(notes) }
                } else if let supplier {
                    Text(supplier.bill_number).font(.headline); Text(supplier.vendor?.name ?? "Supplier")
                    Text("\(supplier.total.formatted(.currency(code: supplier.currency ?? "USD"))) · Due \(RecordCoding.calendarDay(supplier.due_date)) · \(supplier.displayStatus.displayName)")
                    if let notes = supplier.notes { Text(notes) }
                } else if error == nil { ProgressView("Loading exact bill…") }
                if bill != nil || supplier != nil {
                    Button("History") { history = true }
                    if mayChange && (bill.map { !$0.isPaid && $0.status != .cancelled } ?? supplier?.isOpen ?? false) {
                        DatePicker("Paid on", selection: $paidOn, in: ...Date(), displayedComponents: .date)
                        Button("Record Payment") { action = "pay" }
                        Button("Cancel Bill", role: .destructive) { action = "cancel" }
                        Text("Records an existing payment. No money is moved. Changes preserve history.").font(.caption)
                    }
                }
            }.disabled(saving).navigationTitle("Review bill")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back to results") { dismiss() }.disabled(saving) } }
        }.task { await load() }
            .confirmationDialog("Confirm bill change", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                if let action { Button(action == "pay" ? "Confirm recorded payment" : "Confirm cancellation") { Task { await change(action) } } }
            }
            .sheet(isPresented: $history) { RecordHistoryView(kind: row.kind.rawValue, id: row.recordID) }
            .interactiveDismissDisabled(saving)
    }
    private func load() async {
        do {
            try row.validate()
            if row.kind == .bills {
                guard appState.currentUser?.accountType == .personal && appState.hasCapability(.viewBills) else { throw PlatformError.denied }
                bill = try await BillRepository().fetchBill(id: row.recordID)
            } else {
                guard appState.hasCapability(.viewAccountsPayable) else { throw PlatformError.denied }
                supplier = try await VendorRepository().bills().first { $0.id == row.recordID }
                guard supplier != nil else { throw PlatformError.denied }
            }
            error = nil
        } catch { bill = nil; supplier = nil; self.error = "This bill is unavailable or outside your access." }
    }
    private func change(_ action: String) async {
        guard !saving, mayChange else { return }
        saving = true; defer { saving = false; self.action = nil }
        do {
            if let bill { try await BillRepository().action(bill, action: action, paidOn: paidOn) }
            else if let supplier { try await VendorRepository().action(supplier, action: action, paidOn: paidOn) }
            await load()
        } catch { self.error = RecordError.safe(error).localizedDescription }
    }
}
