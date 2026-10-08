import Foundation
import Supabase

final class ReceiptStorage {
    static func read(url: URL) throws -> (data: Data, mime: String) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, (1...ReceiptRules.maxBytes).contains(size) else { throw RecordError(message: "Choose a JPEG, PNG, WebP or PDF receipt up to 10 MB.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let mime = ReceiptRules.mimeType(extension: url.pathExtension, data: data) else { throw RecordError.invalid }
        return (data, mime)
    }
    static func validPath(_ path: String) -> Bool {
        path.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|pdf)$"#, options: .regularExpression) != nil
    }
    func upload(url: URL) async throws -> String {
        let file = try Self.read(url: url)
#if DEBUG
        if let client = SupabaseClientManager.shared.client.localClient {
            let user = try await client.auth.session.user.id.uuidString.lowercased()
            let path = "\(user)/\(UUID().uuidString.lowercased()).\(url.pathExtension.lowercased())"
            try await client.storage.from("receipts").upload(path, data: file.data, options: FileOptions(contentType: file.mime, upsert: false))
            return path
        }
#endif
        let actor = try await SupabaseClientManager.shared.client.auth.session.user.id.uuidString.lowercased()
        let (data, response) = try await AmountlyPlatform.transport.request(path: "/api/receipts/upload", method: "PUT", body: file.data, mime: file.mime, limit: 1024)
        try AmountlyTransport.check(response)
        struct Uploaded: Decodable { let path: String }
        guard let result = try? JSONDecoder().decode(Uploaded.self, from: data), Self.validPath(result.path), result.path.hasPrefix(actor + "/") else { throw PlatformError.response }
        return result.path
    }
    // Render receipts require cookies: download through the private transport,
    // then present a protected local copy. Never open a record-supplied URL.
    func signedURL(for expense: Expense) async throws -> URL {
        guard let path = expense.receiptPath, Self.validPath(path) else { throw RecordError(message: "This original receipt is unavailable. Attach a current copy.") }
#if DEBUG
        if let client = SupabaseClientManager.shared.client.localClient { return try await client.storage.from("receipts").createSignedURL(path: path, expiresIn: 60) }
#endif
        let (data, response) = try await AmountlyPlatform.transport.request(path: "/api/receipts/\(path)", limit: ReceiptRules.maxBytes)
        try AmountlyTransport.check(response, mime: nil)
        let ext = String(path.split(separator: ".").last!)
        guard ReceiptRules.mimeType(extension: ext, data: data) == response.mimeType else { throw PlatformError.response }
        return try PrivateDocument.write(data, extension: ext, prefix: "receipt")
    }
}

@MainActor
enum PrivateDocument {
    static func removeAll() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("amountly-private-exports"))
    }
    static func write(_ data: Data, extension ext: String, prefix: String) throws -> URL {
        guard ["jpg", "png", "webp", "pdf", "zip", "csv"].contains(ext), ["receipt", "accountant"].contains(prefix) else { throw PlatformError.input }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("amountly-private-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let url = dir.appendingPathComponent("\(prefix)-\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
