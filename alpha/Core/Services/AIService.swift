import Foundation
import Auth

@MainActor
enum AIService {
    static let client = AIClient(transport: { request in
        try await AmountlyPlatform.transport.send(request, limit: 256000)
    }) {
#if DEBUG
        // Loopback fixtures must never borrow a persisted hosted session.
        guard SupabaseClientManager.shared.client.localClient == nil else { throw AIError.signIn }
#endif
        let session = try await SupabaseClientManager.shared.client.auth.session
        return AISession(userID: session.user.id.uuidString, token: AmountlyPlatform.transport.generation.uuidString)
    }
}
