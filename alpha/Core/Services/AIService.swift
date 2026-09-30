import Foundation
import Supabase

@MainActor
enum AIService {
    static let client = AIClient {
        let auth = SupabaseClientManager.shared.client.auth
        let session = try await auth.session
        return AISession(userID: session.user.id.uuidString, token: session.accessToken)
    }
}
