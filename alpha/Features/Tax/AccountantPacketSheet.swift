import SwiftUI

struct AccountantPacketSheet: View {
    let year: Int
    let month: Int
    let currency: String
    let basis: String
    let start: String
    let end: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var from: Date
    @State private var through: Date
    @State private var pending = false
    @State private var error: String?
    @State private var download: Task<Void, Never>?
    @State private var document: Document?
    private struct Document: Identifiable { let id = UUID(); let url: URL }
    init(year: Int, month: Int, currency: String, basis: String, start: String, end: String) {
        self.year = year; self.month = month; self.currency = currency; self.basis = basis; self.start = start; self.end = end
        _from = State(initialValue: RecordCoding.parseDate(start) ?? Date())
        _through = State(initialValue: RecordCoding.parseDate(end) ?? Date())
    }
    private var valid: Bool { RecordCoding.day(from) >= start && RecordCoding.day(through) <= end && from <= through }
    var body: some View {
        NavigationStack {
            Form {
                Text("\(currency) · \(basis == "cash" ? "Cash received" : "Invoices issued")")
                DatePicker("From", selection: $from, displayedComponents: .date).disabled(pending)
                DatePicker("Through", selection: $through, displayedComponents: .date).disabled(pending)
                Text("Download records, a receipt index and private original receipts in one ZIP. The index identifies missing originals and expense review state. Up to 100 receipts and 25 MB of originals per packet.").font(.caption)
                if !valid { Text("Choose dates within \(start) through \(end).").foregroundStyle(.red) }
                if let error { Text(error).foregroundStyle(.red) }
                Button(pending ? "Preparing packet…" : "Download ZIP") { prepare() }.disabled(pending || !valid)
                if pending { ProgressView(); Button("Cancel download") { download?.cancel() } }
            }.navigationTitle("Accountant Packet")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { download?.cancel(); dismiss() } } }

        }
        .sheet(item: $document, onDismiss: { if let url = document?.url { try? FileManager.default.removeItem(at: url) }; PrivateDocument.removeAll() }) { document in ShareSheet(activityItems: [document.url]) }
        .onDisappear { download?.cancel() }
        .onChange(of: appState.currentUser?.id) { _, _ in download?.cancel(); document = nil; PrivateDocument.removeAll(); dismiss() }
    }
    private func prepare() {
        guard !pending, valid, appState.currentUser?.canExportAccountantPacket == true else { return }
        pending = true; error = nil
        let fromDay = RecordCoding.day(from), throughDay = RecordCoding.day(through)
        download = Task { @MainActor in
            defer { pending = false }
            do {
#if DEBUG
                guard SupabaseClientManager.shared.client.localClient == nil else { throw PlatformError.signIn }
#endif
                _ = try await SupabaseClientManager.shared.client.auth.session
                var components = URLComponents(); components.path = "/api/reports/accountant"
                components.queryItems = ["year": String(year), "month": String(month), "currency": currency, "basis": basis, "start": fromDay, "end": throughDay].map { URLQueryItem(name: $0.key, value: $0.value) }
                guard let path = components.string else { throw PlatformError.input }
                let (bytes, response) = try await AmountlyPlatform.transport.request(path: path, limit: 32 * 1024 * 1024)
                try AmountlyTransport.check(response, mime: "application/zip")
                guard bytes.starts(with: [80, 75, 3, 4]) else { throw PlatformError.response }
                try Task.checkCancellation()
                document = Document(url: try PrivateDocument.write(bytes, extension: "zip", prefix: "accountant"))
            } catch is CancellationError { error = "Download cancelled. Try again when ready." }
            catch { self.error = (error as? PlatformError)?.localizedDescription ?? "Could not prepare the packet. Try again." }
        }
    }
}
