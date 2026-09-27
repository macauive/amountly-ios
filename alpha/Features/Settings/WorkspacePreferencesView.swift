import SwiftUI
import Supabase

struct WorkspacePreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currency = "USD"
    @State private var basis = "cash"
    @State private var month = 1
    @State private var tax = 0.0
    @State private var terms = 30
    @State private var dateFormat = "MM/DD/YYYY"
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("Shared with the web app") {
                Picker("Default currency", selection: $currency) { ForEach(RecordCoding.currencies, id: \.self) { Text($0) } }
                Picker("Income basis", selection: $basis) { Text("Cash").tag("cash"); Text("Accrual").tag("accrual") }
                Picker("Fiscal year begins", selection: $month) { ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) } }
                HStack { Text("Default tax %"); Spacer(); TextField("Default tax %", value: $tax, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100).accessibilityLabel("Default tax percent") }
                Picker("Payment terms", selection: $terms) {
                    ForEach(Array(Set([0, 7, 15, 30, 45, 60, 90, terms])).sorted(), id: \.self) { days in
                        Text(days == 0 ? "Due on Receipt" : "Net \(days)").tag(days)
                    }
                }
                Picker("Date format", selection: $dateFormat) { ForEach(["MM/DD/YYYY","DD/MM/YYYY","YYYY-MM-DD"], id: \.self) { Text($0) } }
            }.disabled(saving)
            if let message { Text(message) }
            Button("Save Preferences") { Task { await save() } }.disabled(saving)
        }.navigationTitle("Workspace Preferences")
            .onAppear {
                guard let user = appState.currentUser else { return }
                currency = user.reportingCurrency; basis = user.incomeBasis; month = user.fiscalStartMonth
                tax = user.preferences?["default_tax_rate"]?.value as? Double ?? Double(user.preferences?["default_tax_rate"]?.value as? Int ?? 0)
                terms = user.preferences?["payment_terms"]?.value as? Int ?? 30
                dateFormat = user.preferences?["date_format"]?.value as? String ?? "MM/DD/YYYY"
            }
    }
    private func save() async {
        guard tax.isFinite, (0...100).contains(tax), let user = appState.currentUser else { message = "Check the tax rate."; return }
        saving = true; defer { saving = false }
        do {
            let client = SupabaseClientManager.shared.client
            let patch: [String: AnyJSON] = ["default_currency": .string(currency), "accounting_basis": .string(basis), "fiscal_year_start": .integer(month), "default_tax_rate": .double(tax), "payment_terms": .integer(terms), "date_format": .string(dateFormat)]
            try await client.rpc("set_own_preferences", params: ["p_patch": AnyJSON.object(patch)]).execute()
            let data = try await client.from("users").select().eq("id", value: user.id).single().execute().data
            appState.currentUser = try RecordCoding.decoder().decode(User.self, from: data)
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
            message = "Preferences saved."
        } catch { message = RecordError.safe(error).localizedDescription }
    }
}
