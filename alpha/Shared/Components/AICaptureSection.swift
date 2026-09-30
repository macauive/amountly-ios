import SwiftUI

extension EnvironmentValues {
    @Entry var aiCaptureClient: AIClient? = nil
}

// A suggestion is transient: only an explicit Apply changes the editable form.
// SwiftUI cancels the request when its sheet closes or a new request replaces it.
struct AICaptureSection<Result: AIResult>: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.aiCaptureClient) private var environmentClient
    let title: String
    @Binding var text: String
    let task: AITask
    let apply: (Result) -> Void
    var client: AIClient = AIService.client
    @State private var requestID: UUID?
    @State private var submitted = ""
    @State private var result: Result?
    @State private var error: String?
    var body: some View {
        Section(title) {
            TextEditor(text: $text).frame(minHeight: 82).accessibilityLabel(title + " text")
                .disabled(requestID != nil)
            Text("Describe the details or paste text. Review the AI suggestion before applying it.").font(.caption).foregroundStyle(.secondary)
            if text.utf16.count > 12000 { Text("Use no more than 12,000 characters.").foregroundStyle(.red) }
            if requestID != nil {
                HStack { ProgressView("Asking Amountly AI…"); Spacer(); Button("Cancel") { requestID = nil } }
            } else {
                Button("Get suggestion", systemImage: "wand.and.stars") {
                    submitted = text; result = nil; error = nil; requestID = UUID()
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf16.count > 12000)
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityLabel(error) }
            if let result {
                ForEach(Array(result.preview.enumerated()), id: \.offset) { _, line in Text(line).font(.callout).textSelection(.enabled) }
                Button("Apply suggestion") { apply(result); self.result = nil }
            }
        }
        .onChange(of: appState.currentUser?.id) { _, _ in requestID = nil; result = nil; error = nil; text = "" }
        .onChange(of: text) { _, _ in result = nil; error = nil }
        .task(id: requestID) {
            guard let id = requestID else { return }
            defer { if requestID == id { requestID = nil } }
            do {
                let value: Result = try await (environmentClient ?? client).run(task, payload: submitted)
                try Task.checkCancellation()
                guard requestID == id, text == submitted else { return }
                result = value
            } catch is CancellationError { }
            catch { if requestID == id { self.error = AIError.message(error) } }
        }
    }
}
