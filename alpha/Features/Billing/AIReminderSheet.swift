import SwiftUI

struct AIReminderSheet: View {
    @EnvironmentObject private var appState: AppState
    let invoice: Invoice
    @Environment(\.dismiss) private var dismiss
    @State private var requestID: UUID?
    @State private var subject = ""
    @State private var message = ""
    @State private var reason = ""
    @State private var tone = ""
    @State private var error: String?
    @State private var generated = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(invoice.invoiceNumber)
                    Text("Draft a reminder to review and share. Nothing is sent automatically.").font(.caption)
                    if requestID != nil { ProgressView("Drafting reminder…") }
                    else {
                        Button(generated ? "Generate another draft" : "Draft reminder", systemImage: "wand.and.stars") { error = nil; requestID = UUID() }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if generated {
                    Section("Review reminder · \(tone)") {
                        TextField("Subject", text: $subject)
                        TextEditor(text: $message).frame(minHeight: 180)
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        ShareLink("Share draft", item: subject + "\n\n" + message)
                        Button("Copy draft") { UIPasteboard.general.setItems([["public.utf8-plain-text": subject + "\n\n" + message]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)]) }
                    }
                }
            }.navigationTitle("Payment Reminder")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .onChange(of: appState.currentUser?.id) { _, _ in requestID = nil; subject = ""; message = ""; generated = false; dismiss() }
                .task(id: requestID) {
                    guard let id = requestID else { return }
                    defer { if requestID == id { requestID = nil } }
                    do {
                        guard [.sent, .overdue].contains(invoice.status), invoice.balanceDue > 0 else { throw AIError.input }
                        let input = AIReminderInput(invoice_number: invoice.invoiceNumber, total: invoice.balanceDue, currency: invoice.currency,
                            due_date: RecordCoding.day(invoice.dueDate), status: invoice.isOverdue ? "OVERDUE" : invoice.status.rawValue.uppercased(),
                            client: .init(name: invoice.displayClientName, contact_name: nil))
                        let draft: AIReminder = try await AIService.client.run(.reminder, payload: input)
                        try Task.checkCancellation()
                        guard requestID == id else { return }
                        subject = draft.subject; message = draft.body; reason = draft.reason; tone = draft.tone.rawValue; generated = true
                    } catch is CancellationError { }
                    catch { self.error = AIError.message(error) }
                }
        }
    }
}
