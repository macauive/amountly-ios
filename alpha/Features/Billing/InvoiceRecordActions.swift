import SwiftUI
import Supabase

struct InvoiceRecordActions: View {
    let invoice: Invoice
    let onSaved: () -> Void
    @State private var showingHistory = false
    @State private var correction: InvoicePayment?
    @State private var legacy = false
    @State private var editing = false
    @State private var pendingAction: String?
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(spacing: 12) {
            Button("History") { showingHistory = true }
            if invoice.status == .draft {
                Button("Edit Draft") { editing = true }
                Button("Delete Draft", role: .destructive) { pendingAction = "delete" }
            } else if [.sent, .overdue].contains(invoice.status) && (invoice.payments ?? []).isEmpty {
                Button("Cancel Invoice", role: .destructive) { pendingAction = "cancel" }
            }
            ForEach((invoice.payments ?? []).filter { !$0.isReversed }) { payment in
                Button("Correct \(payment.amount.formatted(.currency(code: invoice.currency))) payment") { correction = payment }
            }
            if invoice.needsLegacyReview { Button("Review Historical Payment") { legacy = true } }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.disabled(busy)
            .confirmationDialog("Confirm invoice change", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
                if let action = pendingAction { Button(action == "delete" ? "Delete Draft" : "Cancel Invoice", role: .destructive) { Task { busy = true; defer { busy = false }; do { try await InvoiceRepository().action(invoice, action); onSaved() } catch { self.error = RecordError.safe(error).localizedDescription } } } }
            } message: { Text("\(invoice.invoiceNumber) · \(invoice.totalFormatted). Check this record before continuing.") }
            .sheet(isPresented: $showingHistory) { RecordHistoryView(kind: "invoices", id: invoice.id) }
            .sheet(item: $correction) { payment in PaymentEvidenceForm(invoice: invoice, payment: payment, onSaved: onSaved) }
            .sheet(isPresented: $legacy) { PaymentEvidenceForm(invoice: invoice, payment: nil, onSaved: onSaved) }
            .sheet(isPresented: $editing) { InvoiceDraftEditor(invoice: invoice, onSaved: onSaved) }
    }
}

private struct PaymentEvidenceForm: View {
    let invoice: Invoice
    let payment: InvoicePayment?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var action = "record_payment"
    @State private var reason = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var method = "bank_transfer"
    @State private var reference = ""
    @State private var attempt = RecordAttempt()
    @State private var attempted = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(invoice.invoiceNumber).font(.headline)
                    Text(payment == nil ? "The historical Paid label is not evidence. Record money you can verify, or reopen the balance." : "Correct an entry recorded incorrectly. The full original amount will be excluded from totals and the balance will reopen. This does not issue a refund.")
                }
                Section {
                    if payment == nil {
                        Picker("Outcome", selection: $action) { Text("Record verified payment").tag("record_payment"); Text("Reopen balance").tag("reopen") }
                        if action == "record_payment" {
                            TextField("Verified amount", text: $amount).keyboardType(.decimalPad)
                            DatePicker("Actually received", selection: $date, in: ...Date(), displayedComponents: .date)
                            Picker("Method", selection: $method) { ForEach(["bank_transfer","card","cash","check","other"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
                            TextField("Reference", text: $reference)
                        }
                    }
                    TextField("Evidence and reason", text: $reason, axis: .vertical).lineLimit(3...6)
                    Text("The original record and your explanation are preserved. Do not include bank or card numbers.").font(.caption)
                }.disabled(attempted)
                if let error { Text(error).foregroundStyle(.red) }
                Button(attempted ? "Retry Original Request" : "Confirm Reviewed Evidence") { Task { await save() } }.disabled(busy)
            }.navigationTitle(payment == nil ? "Historical Payment" : "Correct Payment")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
        }
    }
    private func save() async {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (payment == nil ? 10...1000 : 5...500).contains(reason.count) else { error = "Enter a reason with sufficient detail."; return }
        busy = true; defer { busy = false }
        do {
            if let payment {
                attempted = true
                try await PaymentRepository().reverse(payment: payment, reason: reason, attempt: attempt)
            } else {
                guard let version = invoice.version else { throw RecordError.conflict }
                var data: [String: AnyJSON] = ["action": .string(action), "evidence": .string(reason)]
                if action == "record_payment" {
                    guard let value = Double(amount), value.isFinite, value > 0, value <= invoice.total, date >= invoice.issueDate else { throw RecordError.invalid }
                    data.merge(["amount": .double(value), "paid_on": .string(RecordCoding.day(date)), "method": .string(method), "reference": .string(reference)]) { _, new in new }
                }
                attempted = true
                try await attempt.perform("review_legacy_payment", params: ["p_id": .string(attempt.id), "p_invoice_id": .string(invoice.id), "p_expected_updated_at": .string(version), "p_data": .object(data)])
            }
            dismiss(); onSaved()
        } catch { self.error = RecordError.safe(error).localizedDescription }
    }
}

private struct InvoiceDraftEditor: View {
    let invoice: Invoice
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [LineItem] = []
    @State private var number = ""
    @State private var due = Date()
    @State private var tax = 0.0
    @State private var notes = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Invoice number", text: $number)
                DatePicker("Due date", selection: $due, displayedComponents: .date)
                TextField("Tax %", value: $tax, format: .number).keyboardType(.decimalPad)
                Section("Line items") {
                    ForEach($lines) { $line in
                        VStack { TextField("Description", text: $line.description); HStack { TextField("Quantity", value: $line.quantity, format: .number); TextField("Rate", value: $line.rate, format: .number) }.keyboardType(.decimalPad) }
                    }.onDelete { lines.remove(atOffsets: $0) }
                    Button("Add Line") { lines.append(LineItem()) }.disabled(lines.count >= 100)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                Text("Time-linked invoice lines are protected by the server. Delete the draft to release reserved time before changing its source.").font(.caption)
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy).navigationTitle("Edit Draft")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy) }
                }
                .onAppear { number = invoice.invoiceNumber; due = invoice.dueDate; tax = invoice.taxRate ?? 0; notes = invoice.notes ?? ""; lines = (invoice.lineItems ?? []).sorted { $0.order < $1.order }.map { LineItem(description: $0.description, quantity: $0.quantity, rate: $0.rate) } }
        }
    }
    private func save() async {
        guard let version = invoice.version, let client = invoice.clientId, !lines.isEmpty, tax.isFinite, (0...100).contains(tax), lines.allSatisfy({ !$0.description.isEmpty && $0.quantity.isFinite && $0.quantity > 0 && $0.rate.isFinite && $0.rate >= 0 }) else { error = "Check the draft fields."; return }
        busy = true; defer { busy = false }
        do {
            let data: [String: AnyJSON] = ["client_id": .string(client), "project_id": invoice.projectId.map(AnyJSON.string) ?? .null, "invoice_number": .string(number), "issue_date": .string(RecordCoding.day(invoice.issueDate)), "due_date": .string(RecordCoding.day(due)), "currency": .string(invoice.currency), "tax_rate": .double(tax), "notes": .string(notes)]
            try await SupabaseClientManager.shared.client.rpc("save_invoice", params: ["p_id": AnyJSON.string(invoice.id), "p_data": .object(data), "p_expected_updated_at": .string(version), "p_lines": .array(lines.map { .object(["description": .string($0.description), "quantity": .double($0.quantity), "rate": .double($0.rate)]) })]).execute()
            NotificationCenter.default.post(name: .recordsChanged, object: nil); dismiss(); onSaved()
        } catch { self.error = RecordError.safe(error).localizedDescription }
    }
}
