import SwiftUI

struct QuickBillSheet: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var payee = ""
    @State private var amount = ""
    @State private var currency = "USD"
    @State private var category = "other"
    @State private var dueDate = Date()
    @State private var recurrence: BillRecurrence = .none
    @State private var autoPay = false
    @State private var notes = ""
    @State private var saving = false
    @State private var attempted = false
    @State private var error: String?
    @State private var attempt = RecordAttempt()
    var body: some View {
        if appState.hasCapability(.viewAccountsPayable) {
            VendorBillForm(isPresented: $isPresented)
        } else {
            NavigationStack {
                Form {
                    Section("Bill") {
                        TextField("Name", text: $name)
                        TextField("Payee", text: $payee)
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                        Picker("Currency", selection: $currency) { ForEach(RecordCoding.currencies, id: \.self) { Text($0) } }
                        Picker("Category", selection: $category) {
                            ForEach(["rent", "utilities", "insurance", "subscription", "loan", "credit_card", "phone", "internet", "other"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                        }
                    }.disabled(attempted)
                    Section("Schedule") {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                        Picker("Recurrence", selection: $recurrence) { ForEach(BillRecurrence.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                        Toggle("Auto-pay reminder", isOn: $autoPay)
                        TextField("Notes", text: $notes, axis: .vertical)
                        Text("Tracks your bill schedule. Amountly does not set up payments or bank AutoPay.").font(.caption)
                    }.disabled(attempted)
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                }
                .navigationTitle("Add Bill")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button(attempted ? "Retry" : "Save") { Task { await save() } }.disabled(saving || name.isEmpty || payee.isEmpty || Double(amount) == nil) }
                }
                .interactiveDismissDisabled(saving)
                .onAppear { currency = appState.currentUser?.reportingCurrency ?? "USD" }
            }
        }
    }
    private func save() async {
        guard let value = Double(amount), value.isFinite, value > 0 else { error = "Enter a positive amount."; return }
        saving = true; attempted = true
        defer { saving = false }
        do {
            _ = try await BillRepository().createBill(name: name, payee: payee, amount: value, category: category, dueDate: dueDate, recurrence: recurrence, notes: notes, currency: currency, autoPay: autoPay, attempt: attempt)
            isPresented = false
        } catch { self.error = RecordError.safe(error).localizedDescription }
    }
}
