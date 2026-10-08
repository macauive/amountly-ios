import SwiftUI
import Supabase

struct ReviewInboxView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expenses: [Expense] = []
    @State private var legacyInvoices: [Invoice] = []
    @State private var selectedInvoice: Invoice?
    @State private var selectedExpense: Expense?
    @State private var soloReview: Expense?
    private var isSolo: Bool { appState.currentUser?.accountType == .freelancer && appState.currentUser?.organizationId == nil }
    @State private var entries: [TimeEntry] = []
    @State private var error: String?
    @State private var loading = true
    @State private var busy = false
    @State private var history: ReviewRecord?
    @State private var pending: ReviewRecord?
    private struct ReviewRecord: Identifiable { let id: String; let kind: String; let title: String; let version: String?; let action: String }
    private var canReview: Bool { appState.currentUser?.accountType == .business && appState.currentUser?.isAdmin == true }
    var body: some View {
        List {
            Text(isSolo ? "Review saved amounts, currency, dates, categories and receipts. Reviewed is a personal check; expenses remain captured records." : "Review captured expenses and time. Approvals require a different owner or administrator.").font(.caption)
            if loading { ProgressView("Loading review inbox…") }
            if let error { Text(error).foregroundStyle(.red) }
            if !legacyInvoices.isEmpty {
                Section("Historical payments to verify") {
                    Text("A Paid label without receipts is excluded from cash income. Review evidence before recording money received.").font(.caption)
                    ForEach(legacyInvoices) { invoice in
                        Button("\(invoice.invoiceNumber) · \(invoice.totalFormatted)") { selectedInvoice = invoice }
                    }
                }
            }
            Section(isSolo ? "Saved expense review" : "Expenses to review") {
                ForEach(expenses.filter { isSolo ? ($0.needsReview || $0.reviewedAt != nil) : [.draft, .rejected, .submitted].contains($0.status) }) { expense in
                    VStack(alignment: .leading) {
                        Text(expense.description).font(.headline)
                        Text("\(expense.amountFormatted) · \(expense.status.displayName)").font(.caption)
                        Button("Open saved expense") { selectedExpense = expense }
                        if isSolo && expense.userId == appState.currentUser?.id && [.draft, .rejected].contains(expense.status) {
                            Text(expense.reviewedAt == nil ? "Needs review" : "Reviewed").font(.caption)
                            Button(expense.reviewedAt == nil ? "Mark reviewed" : "Clear review") { soloReview = expense }
                        }
                        controls(kind: "expenses", id: expense.id, title: expense.description, owner: expense.userId, status: expense.status.rawValue, version: expense.version)
                    }
                }
            }
            Section("Time to review") {
                ForEach(entries.filter { !$0.isReserved && [.draft, .rejected, .submitted].contains($0.status) }) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.project?.name ?? "Tracked time").font(.headline)
                        Text("\(entry.durationFormatted) · \(entry.status.displayName)").font(.caption)
                        controls(kind: "time_entries", id: entry.id, title: entry.notes ?? "Tracked time", owner: entry.userId, status: entry.status.rawValue, version: entry.version)
                    }
                }
            }
        }.navigationTitle("Review Inbox")
            .task { await load() }.refreshable { await load() }
            .sheet(item: $selectedInvoice) { invoice in InvoiceDetailSheet(invoice: invoice, onUpdate: { Task { await load() } }) }
            .sheet(item: $selectedExpense) { expense in ExpenseDetailSheet(expense: expense) { Task { await load() } } }
            .confirmationDialog("Confirm expense review", isPresented: Binding(get: { soloReview != nil }, set: { if !$0 { soloReview = nil } }), titleVisibility: .visible) {
                if let expense = soloReview { Button(expense.reviewedAt == nil ? "Confirm mark reviewed" : "Confirm clear review") { Task { await markReviewed(expense) } } }
            } message: { Text("Check the saved amount, currency, date, category and receipt. This change is recorded in history.") }
            .sheet(item: $history) { record in RecordHistoryView(kind: record.kind, id: record.id) }
            .confirmationDialog("Confirm review action", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let record = pending { Button(record.action.capitalized) { Task { await review(record) } } }
            } message: { Text(pending?.title ?? "") }
            .disabled(busy)
    }
    @ViewBuilder private func controls(kind: String, id: String, title: String, owner: String, status: String, version: String?) -> some View {
        HStack {
            Button("History") { history = ReviewRecord(id: id, kind: kind, title: title, version: version, action: "") }
            if owner == appState.currentUser?.id && ["DRAFT", "REJECTED"].contains(status) && appState.currentUser?.accountType == .business {
                Button("Submit") { pending = ReviewRecord(id: id, kind: kind, title: title, version: version, action: "submit") }
            }
            if canReview && owner != appState.currentUser?.id && status == "SUBMITTED" {
                Button("Approve") { pending = ReviewRecord(id: id, kind: kind, title: title, version: version, action: "approve") }
                Button("Reject") { pending = ReviewRecord(id: id, kind: kind, title: title, version: version, action: "reject") }
            }
        }.buttonStyle(.bordered).font(.caption)
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            expenses = try await ExpenseRepository().fetchExpenses()
            if appState.hasCapability(.viewInvoices) || appState.hasCapability(.viewAccountsReceivable) {
                legacyInvoices = try await InvoiceRepository().fetchInvoices().filter(\.needsLegacyReview)
            }
            if appState.currentUser?.accountType != .personal { entries = try await TimeEntryRepository().fetchTimeEntries() }
            error = nil
        } catch { self.error = "Could not load the complete review inbox." }
    }
    private func markReviewed(_ expense: Expense) async {
        guard !busy else { return }; busy = true; defer { busy = false; soloReview = nil }
        do { try await ExpenseRepository().setReviewed(expense, reviewed: expense.reviewedAt == nil); await load() }
        catch { self.error = RecordError.safe(error).localizedDescription }
    }
    private func review(_ record: ReviewRecord) async {
        busy = true; defer { busy = false }
        do {
            guard let version = record.version else { throw RecordError.conflict }
            try await SupabaseClientManager.shared.client.rpc("review_work_record", params: ["p_kind": record.kind, "p_id": record.id, "p_action": record.action, "p_expected_updated_at": version]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
            await load()
        } catch { self.error = RecordError.safe(error).localizedDescription }
    }
}
struct RecordHistoryView: View {
    let kind: String
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var events: [RecordEvent] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Loading history…") }
                if let error { Text(error) }
                ForEach(events) { event in VStack(alignment: .leading) { Text(event.action.replacingOccurrences(of: "_", with: " ").capitalized); Text(event.created_at, style: .date).font(.caption) } }
                if !loading && events.isEmpty && error == nil { Text("No recorded history.") }
            }.navigationTitle("Record History")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task {
                    defer { loading = false }
                    do {
                        while true {
                            let client = SupabaseClientManager.shared.client
                            let query = client.from("record_events").select("id,action,created_at").eq("record_type", value: kind).eq("record_id", value: id)
                            let data = try await query.order("created_at", ascending: false).order("id").range(from: events.count, to: events.count + 199).execute().data
                            let page = try RecordCoding.decoder().decode([RecordEvent].self, from: data); events += page
                            if page.count < 200 { break }
                        }
                    } catch { self.error = "Could not load record history." }
                }
        }
    }
}
