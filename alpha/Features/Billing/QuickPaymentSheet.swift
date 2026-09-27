import SwiftUI

struct QuickPaymentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    var initialInvoice: Invoice? = nil
    var onSave: () -> Void = {}
    @State private var invoices: [Invoice] = []
    @State private var selectedID = ""
    @State private var amount = ""
    @State private var method = "bank_transfer"
    @State private var reference = ""
    @State private var date = Date()
    @State private var saving = false
    @State private var attempted = false
    @State private var error: String?
    @State private var attempt = RecordAttempt()
    private var invoice: Invoice? { invoices.first { $0.id == selectedID } }
    var body: some View {
        NavigationStack {
            if appState.currentUser?.accountType == .personal {
                BillsView().navigationTitle("Record Bill Payment")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { isPresented = false } } }
            } else {
                Form {
                    Section("Invoice") {
                        Picker("Invoice", selection: $selectedID) {
                            Text("Choose an issued invoice").tag("")
                            ForEach(invoices) { row in Text("\(row.invoiceNumber) · \(row.currency)").tag(row.id) }
                        }
                        if let invoice { LabeledContent("Balance due", value: invoice.balanceDue.formatted(.currency(code: invoice.currency))) }
                    }.disabled(attempted)
                    Section("Payment received") {
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                        DatePicker("Paid on", selection: $date, in: ...Date(), displayedComponents: .date)
                        Picker("Method", selection: $method) {
                            Text("Bank Transfer").tag("bank_transfer")
                            Text("Card").tag("card")
                            Text("Cash").tag("cash")
                            Text("Check").tag("check")
                            Text("Other").tag("other")
                        }
                        TextField("Reference (optional)", text: $reference)
                    }.disabled(attempted)
                    Section { Text("This records money already received. It does not charge your client.") }
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                }
                .navigationTitle("Record Payment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(attempted ? "Retry" : "Record") { Task { await save() } }
                            .disabled(saving || invoice == nil || Double(amount) == nil)
                    }
                }
                .task {
                    do {
                        invoices = try await InvoiceRepository().fetchInvoices().filter { [.sent, .overdue].contains($0.status) && $0.balanceDue > 0 }
                        selectedID = initialInvoice?.id ?? ""
                        if let invoice { amount = String(invoice.balanceDue) }
                    } catch { self.error = "Could not load invoices. Close and try again." }
                }
                .interactiveDismissDisabled(saving)
            }
        }
    }
    private func save() async {
        guard let invoice, let value = Double(amount), value.isFinite, value > 0, value <= invoice.balanceDue else { error = "Enter an amount within the outstanding balance."; return }
        saving = true; attempted = true
        defer { saving = false }
        do {
            try await PaymentRepository().record(invoice: invoice, amount: value, method: method, reference: reference, date: date, attempt: attempt)
            onSave(); isPresented = false
        } catch { self.error = RecordError.safe(error).localizedDescription }
    }
}
