import SwiftUI

struct RecordListFilterGroup: View {
    @Binding var filters: RecordFilters
    let statuses: [String]
    var body: some View {
        DisclosureGroup("Search and filter records") {
            VStack(spacing: 10) { RecordFilterControls(filters: $filters, statuses: statuses) }
        }.padding(.horizontal)
    }
}

struct RecordSearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filters: RecordFilters
    @State private var rows: [SearchRecord] = []
    @State private var selected: SearchRecord?
    @State private var loading = true
    @State private var error: String?
    @State private var loadVersion = UUID()
    init(query: String = "", kind: String = "all") { _filters = State(initialValue: RecordFilters(query: query, kind: kind)) }
    var body: some View {
        List {
            Section("Find financial records") {
                Text("Search records you can access. No AI processing. Invoice dates are issue dates; bill dates are due dates.").font(.caption)
                RecordFilterControls(filters: $filters, includeKind: true)
            }
            if loading { ProgressView("Loading accessible records…") }
            else if let error { Text(error).foregroundStyle(.red); Button("Retry records") { Task { await load() } } }
            else if !filters.valid { Text("Choose valid filters and a From date before Through.").foregroundStyle(.red) }
            else {
                let results = filters.apply(rows)
                Section("\(results.count) matching records") {
                    ForEach(results) { row in
                        Button { selected = row } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.label).font(.headline)
                                Text("\(row.amount.formatted(.currency(code: row.currency))) · \(row.date) · \(row.status.capitalized)")
                                Text(row.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption)
                            }.foregroundStyle(.primary)
                        }.accessibilityIdentifier("records.result.\(row.kind.rawValue).\(row.recordID.lowercased())")
                    }
                    if results.isEmpty { Text("No records match these filters.") }
                }
            }
        }.navigationTitle("Records")
            .task(id: appState.currentUser?.id) { await load() }.refreshable { await load() }
            .sheet(item: $selected, onDismiss: { Task { await load() } }) { row in RecordSourceSheet(row: row) }
    }
    private func load() async {
        guard let actor = appState.currentUser else { rows = []; return }
        let version = UUID(); loadVersion = version
        loading = true; rows = []; error = nil
        do {
            let result = try await RecordSearchRepository().load(actor: actor)
            guard !Task.isCancelled, loadVersion == version, appState.currentUser?.id == actor.id, appState.currentUser?.organizationId == actor.organizationId else { return }
            rows = result; loading = false
        } catch {
            guard loadVersion == version, appState.currentUser?.id == actor.id else { return }
            rows = []; loading = false; self.error = "Could not load all searchable records. No partial results are shown."
        }
    }
}
struct RecordFilterControls: View {
    @FocusState private var editingQuery: Bool
    @Binding var filters: RecordFilters
    var includeKind = false
    var statuses = RecordFilters.statuses
    var body: some View {
        TextField("Name, number or amount", text: $filters.query).textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($editingQuery).submitLabel(.search).onSubmit { editingQuery = false }
        HStack { TextField("From YYYY-MM-DD", text: $filters.start); TextField("Through YYYY-MM-DD", text: $filters.end) }.textInputAutocapitalization(.never).autocorrectionDisabled()
        if includeKind {
            Picker("Record type", selection: $filters.kind) {
                Text("All records").tag("all")
                ForEach(RecordKind.allCases, id: \.rawValue) { Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag($0.rawValue) }
            }
        }
        Picker("Status", selection: $filters.status) { Text("All statuses").tag("all"); ForEach(statuses, id: \.self) { Text($0 == $0.lowercased() ? "Bill: \($0.capitalized)" : $0.capitalized).tag($0) } }
        if includeKind { Picker("Receipt (expenses)", selection: $filters.receipt) { Text("Any").tag("all"); Text("Attached").tag("attached"); Text("Missing").tag("missing") } }
        Button("Clear filters") { filters = RecordFilters() }
        if !filters.valid { Text("Invalid filters. Choose calendar dates with From on or before Through.").foregroundStyle(.red).font(.caption) }
    }
}
private struct RecordSourceSheet: View {
    let row: SearchRecord
    @State private var expense: Expense?
    @State private var invoice: Invoice?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let expense { ExpenseDetailSheet(expense: expense) { dismiss() } }
            else if let invoice { InvoiceDetailSheet(invoice: invoice) { dismiss() } }
            else if row.kind == .bills || row.kind == .vendorBills { RecordBillSheet(row: row) }
            else { NavigationStack { VStack { if let error { Text(error) } else { ProgressView("Loading exact record…") } }.toolbar { Button("Close") { dismiss() } } } }
        }.task {
            do {
                try row.validate()
                if row.kind == .expenses { expense = try await ExpenseRepository().fetchExpense(id: row.recordID) }
                else if row.kind == .invoices { invoice = try await InvoiceRepository().fetchInvoice(id: row.recordID) }
            } catch { self.error = "This record is unavailable or outside your access." }
        }
    }
}
