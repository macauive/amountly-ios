import Foundation
import Auth

@MainActor
enum AIService {
    static let client = AIClient(transport: { request in
        do { return try await AmountlyPlatform.transport.send(request, limit: 256000) }
        catch PlatformError.consent { throw AIError.consent }
    }) {
#if DEBUG
        // Loopback fixtures must never borrow a persisted hosted session.
        guard SupabaseClientManager.shared.client.localClient == nil else { throw AIError.signIn }
#endif
        do {
            let generation = AmountlyPlatform.transport.generation
            let permission = try AIConsentStore.shared.authorization(sessionGeneration: generation)
            let session = try await SupabaseClientManager.shared.client.auth.session
            guard AIConsentStore.shared.allows(userID: session.user.id.uuidString, sessionGeneration: generation),
                  AmountlyPlatform.transport.generation == generation else { throw AIError.consent }
            try AIConsentStore.shared.validate(permission, sessionGeneration: generation)
            // AIClient rechecks this identity after every response. Include the
            // consent revision so withdrawal/regrant cannot admit an old result.
            return AISession(userID: session.user.id.uuidString, token: generation.uuidString + "." + permission.uuidString)
        } catch PlatformError.consent { throw AIError.consent }
    }
}
