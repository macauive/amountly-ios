import Foundation
import Supabase

struct RecordError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static let invalid = RecordError(message: "Check the fields and current record status before trying again.")
    static let conflict = RecordError(message: "This record changed. Reload and review before retrying.")
    static func safe(_ error: Error) -> RecordError {
        if let error = error as? RecordError { return error }
        let code = (error as? PostgrestError)?.code ?? ""
        if ["PT409", "40001", "23505", "PGRST116"].contains(code) { return .conflict }
        if code == "42501" { return RecordError(message: "You do not have permission to change this record.") }
        if code.hasPrefix("22") || code.hasPrefix("23") { return .invalid }
        return RecordError(message: "Could not confirm the change. Retry the original request or reload to check its status.")
    }
}

// Keeps the exact original payload and ID after an uncertain network outcome.
// The form must be reopened to start a different request.
final class RecordAttempt {
    nonisolated let id = UUID().uuidString.lowercased()
    nonisolated init() {}
    private var params: [String: AnyJSON]?
    private var uncertain = false
    private var confirmed = false
    private var running = false
    func perform(_ command: String, params proposed: [String: AnyJSON]) async throws {
        guard !running else { throw RecordError(message: "This request is already in progress.") }
        if confirmed { return }
        running = true
        defer { running = false }
        if params == nil { params = proposed }
        do {
            try await SupabaseClientManager.shared.client.rpc(command, params: params!).execute()
            confirmed = true
            NotificationCenter.default.post(name: .recordsChanged, object: nil)
        } catch {
            // A new invoice ID can be looked up after an uncertain first save.
            // No second invoice is created and no changed form content is sent.
            if command == "save_invoice", uncertain {
                struct Saved: Decodable { let id: String }
                if let saved: [Saved] = try? await SupabaseClientManager.shared.client.from("invoices").select("id").eq("id", value: id).execute().value, !saved.isEmpty {
                    confirmed = true
                    NotificationCenter.default.post(name: .recordsChanged, object: nil)
                    return
                }
            }
            let code = (error as? PostgrestError)?.code ?? ""
            if !code.hasPrefix("22") && !code.hasPrefix("23") && !code.hasPrefix("42") && code != "PT409" && code != "40001" { uncertain = true }
            throw RecordError.safe(error)
        }
    }
}
extension Notification.Name { static let recordsChanged = Notification.Name("amountly.recordsChanged") }

struct RecordEvent: Decodable, Identifiable {
    let id: String
    let action: String
    let created_at: Date
}

#if DEBUG
// Diagnostics deliberately contain field names / stable error codes only.
func recordDiagnostic(_ error: Error) {
    switch error {
    case DecodingError.keyNotFound(let key, let context): print("Record decode missing field: \(context.codingPath.map(\.stringValue).joined(separator: "."))).\(key.stringValue)")
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context), DecodingError.dataCorrupted(let context): print("Record decode invalid field: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
    case let error as PostgrestError: print("Record API code: \(error.code ?? "unknown")")
    default: print("Record request failed")
    }
}
#endif
