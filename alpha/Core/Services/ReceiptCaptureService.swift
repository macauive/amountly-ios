import Foundation
import Auth

@MainActor
enum ReceiptCaptureService {
    static func capture(url: URL) async throws -> AIReceiptFile {
#if DEBUG
        guard SupabaseClientManager.shared.client.localClient == nil else { throw PlatformError.signIn }
#endif
        let generation = AmountlyPlatform.transport.generation
        let permission = try AIConsentStore.shared.authorization(sessionGeneration: generation)
        let session = try await SupabaseClientManager.shared.client.auth.session
        guard AIConsentStore.shared.allows(userID: session.user.id.uuidString, sessionGeneration: generation),
              AmountlyPlatform.transport.generation == generation else { throw PlatformError.consent }
        try AIConsentStore.shared.validate(permission, sessionGeneration: generation)
        let file = try ReceiptStorage.read(url: url)
        let (data, response) = try await AmountlyPlatform.transport.request(path: "/api/ai/receipt", method: "POST", body: file.data, mime: file.mime, limit: 128000)
        try AmountlyTransport.check(response)
        try AIConsentStore.shared.validate(permission, sessionGeneration: AmountlyPlatform.transport.generation)
        return try AIReceiptFile.decode(data)
    }
}
