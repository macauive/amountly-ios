import Foundation

@MainActor
enum ReceiptCaptureService {
    static func capture(url: URL) async throws -> AIReceiptFile {
#if DEBUG
        guard SupabaseClientManager.shared.client.localClient == nil else { throw PlatformError.signIn }
#endif
        _ = try await SupabaseClientManager.shared.client.auth.session
        let file = try ReceiptStorage.read(url: url)
        let (data, response) = try await AmountlyPlatform.transport.request(path: "/api/ai/receipt", method: "POST", body: file.data, mime: file.mime, limit: 128000)
        try AmountlyTransport.check(response)
        return try AIReceiptFile.decode(data)
    }
}
