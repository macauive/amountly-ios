import SwiftUI
import Supabase

struct FilingReminder: Decodable, Identifiable {
    let id: String
    let name: String
    let form_type: String
    let due_date: String
    let filed_date: String?
    let status: String
    let amount_due: Double?
    let amount_paid: Double?
    let notes: String?
    let updated_at: String
}
extension FilingReminder {
    static func fetchAll() async throws -> [FilingReminder] {
        var all: [FilingReminder] = []
        while true {
            let page: [FilingReminder] = try await SupabaseClientManager.shared.client.from("tax_filings").select().order("due_date").order("id").range(from: all.count, to: all.count + 199).execute().value
            all += page
            if page.count < 200 { return all }
        }
    }
}
struct TaxRemindersView: View {
    @State private var rows: [FilingReminder] = []
    @State private var error: String?
    @State private var create = false
    @State private var editing: FilingReminder?
    @State private var busy = false
    @State private var year = Calendar.current.component(.year, from: Date())
    var body: some View {
        List {
            Section {
                Button("Add Filing Reminder") { create = true }
                Stepper("Estimate year: \(String(year))", value: $year, in: 2025...2026)
                Button("Add Quarterly Reminders") { Task { await seed() } }.disabled(busy)
                Text("These are reminders and records only. Amountly does not file returns or pay taxes.").font(.caption)
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(rows) { row in
                Button { editing = row } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.name).font(.headline)
                        Text("\(row.form_type) · Due \(row.due_date)")
                        Text(row.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption)
                    }
                }
            }
        }.navigationTitle("Filings & Deadlines")
            .task { await load() }.refreshable { await load() }
            .sheet(isPresented: $create, onDismiss: { Task { await load() } }) { FilingReminderForm(existing: nil) }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { FilingReminderForm(existing: $0) }
    }
    private func load() async {
        do {
            rows = try await FilingReminder.fetchAll(); error = nil
        } catch { self.error = "Could not load filing reminders." }
    }
    private func seed() async {
        busy = true; defer { busy = false }
        do { try await SupabaseClientManager.shared.client.rpc("seed_quarterly_estimates", params: ["p_year": year]).execute(); await load() }
        catch { self.error = "Could not confirm reminders. Reload before retrying." }
    }
}
private struct FilingReminderForm: View {
    let existing: FilingReminder?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var form = "1040-ES"
    @State private var due = Date()
    @State private var filed = Date()
    @State private var status = "not_started"
    @State private var amount = ""
    @State private var paid = ""
    @State private var notes = ""
    @State private var requestID = UUID().uuidString
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Form type", text: $form)
                DatePicker("Due date", selection: $due, displayedComponents: .date)
                Picker("Status", selection: $status) { ForEach(["not_started", "in_progress", "filed", "accepted", "rejected"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
                if ["filed","accepted"].contains(status) { DatePicker("Filed date", selection: $filed, in: ...Date(), displayedComponents: .date) }
                TextField("Amount due (optional)", text: $amount).keyboardType(.decimalPad)
                TextField("Amount paid (optional)", text: $paid).keyboardType(.decimalPad)
                TextField("Notes", text: $notes, axis: .vertical)
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy).navigationTitle(existing == nil ? "Filing Reminder" : "Edit Reminder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy || name.isEmpty || form.isEmpty) }
                }
                .onAppear { if let existing { name = existing.name; form = existing.form_type; due = RecordCoding.parseDate(existing.due_date) ?? Date(); filed = existing.filed_date.flatMap(RecordCoding.parseDate) ?? Date(); status = existing.status; amount = existing.amount_due.map(String.init(describing:)) ?? ""; paid = existing.amount_paid.map(String.init(describing:)) ?? ""; notes = existing.notes ?? "" } }
        }
    }
    private func save() async {
        guard name.count <= 200, form.count <= 100, notes.count <= 10000,
              [amount, paid].allSatisfy({ $0.isEmpty || (Double($0).map { $0.isFinite && $0 >= 0 && $0 < 100000000 } ?? false) }), let user = appState.currentUser else { error = "Check the filing fields."; return }
        busy = true; defer { busy = false }
        var data: [String: AnyJSON] = ["name": .string(name), "form_type": .string(form), "due_date": .string(RecordCoding.day(due)), "status": .string(status), "amount_due": Double(amount).map(AnyJSON.double) ?? .null, "amount_paid": Double(paid).map(AnyJSON.double) ?? .null, "notes": .string(notes)]
        if ["filed", "accepted"].contains(status) { data["filed_date"] = .string(RecordCoding.day(filed)) }
        do {
            let client = SupabaseClientManager.shared.client
            if let existing {
                try await client.from("tax_filings").update(data).eq("id", value: existing.id).eq("updated_at", value: existing.updated_at).select("id").single().execute()
            } else {
                data["id"] = .string(requestID); data["user_id"] = .string(user.id)
                data["organization_id"] = user.organizationId.map(AnyJSON.string) ?? .null
                try await client.from("tax_filings").insert(data).execute()
            }
            dismiss()
        } catch { self.error = RecordError.safe(error).localizedDescription }
    }
}
