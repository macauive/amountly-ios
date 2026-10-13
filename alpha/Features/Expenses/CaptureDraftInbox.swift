import SwiftUI

struct CaptureDraftsView: View {
    @State private var resumed: CaptureDraft?
    @State private var discarded: CaptureDraft?
    var body: some View {
        List { CaptureDraftInbox(onResume: { resumed = $0 }, onDiscard: { discarded = $0 }) }.navigationTitle("Kept captures")
            .sheet(item: $resumed) { draft in
                ExpenseFormSheet(isPresented: Binding(get: { resumed != nil }, set: { if !$0 { resumed = nil } }), capture: draft, onSave: {})
            }
            .modifier(CaptureDiscardConfirmation(draft: $discarded))
    }
}

struct CaptureDraftInbox: View {
    @EnvironmentObject private var appState: AppState
    @State private var drafts: [CaptureDraft] = []
    let onResume: (CaptureDraft) -> Void
    let onDiscard: (CaptureDraft) -> Void
    @State private var error: String?
    @State private var loadVersion = UUID()
    private let service = CaptureDraftService()
    var body: some View {
        Section("Continue a capture (\(drafts.count))") {
            Text("Private unfinished captures. These are not expenses and are excluded from totals. Keep up to 10, one receipt per capture.").font(.caption)
            if let error { Text(error).foregroundStyle(.red); Button("Retry captures") { Task { await load() } } }
            ForEach(drafts) { draft in
                VStack(alignment: .leading, spacing: 8) {
                    Text(draft.payload.fields.merchant.isEmpty ? draft.file_name ?? "Unfinished expense" : draft.payload.fields.merchant).font(.headline)
                    Text("\(draft.payload.fields.amount.isEmpty ? "Amount needed" : draft.payload.fields.amount) \(draft.payload.fields.currency)").font(.caption)
                    HStack {
                        Button("Resume capture") { onResume(draft) }.buttonStyle(.borderless).accessibilityIdentifier("capture.resume.\(draft.id.uuidString.lowercased())")
                        Button("Discard", role: .destructive) { onDiscard(draft) }.buttonStyle(.borderless).accessibilityIdentifier("capture.discard.\(draft.id.uuidString.lowercased())")
                    }
                }
            }
            if drafts.isEmpty && error == nil { Text("Nothing kept for later yet.").foregroundStyle(.secondary) }
        }
        .task(id: appState.currentUser?.id) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .recordsChanged)) { _ in Task { await load() } }
    }
    private func load() async {
        let version = UUID(); loadVersion = version
        let owner = appState.currentUser?.id
        do {
            let rows = try await service.list()
            guard !Task.isCancelled, loadVersion == version, appState.currentUser?.id == owner else { return }
            drafts = rows; error = nil
        } catch {
            guard loadVersion == version, appState.currentUser?.id == owner else { return }
            drafts = []; self.error = "Kept captures are unavailable. Retry before starting another capture."
        }
    }
}

struct CaptureDiscardConfirmation: ViewModifier {
    @Binding var draft: CaptureDraft?
    @State private var busy = false
    @State private var error: String?
    func body(content: Content) -> some View {
        content.alert("Discard this unfinished capture?", isPresented: Binding(get: { draft != nil }, set: { if !$0 && !busy { draft = nil } })) {
            if let capture = draft { Button("Discard capture", role: .destructive) { Task {
                guard !busy else { return }
                busy = true; defer { busy = false }
                do { try await CaptureDraftService().discard(capture); draft = nil; NotificationCenter.default.post(name: .recordsChanged, object: nil) }
                catch { self.error = "Could not discard this capture. Close and reopen captures before retrying." }
            } }.disabled(busy) }
            Button("Cancel", role: .cancel) { draft = nil }.disabled(busy)
        } message: { Text("This removes the private draft and kept original. Saved expenses stay intact.") }
            .alert("Capture unavailable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil; draft = nil } })) { Button("OK") { error = nil; draft = nil } } message: { Text(error ?? "") }
    }
}
