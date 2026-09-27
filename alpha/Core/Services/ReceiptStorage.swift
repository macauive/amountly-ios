import Foundation
import Supabase
import UniformTypeIdentifiers

final class ReceiptStorage {
    func upload(url: URL) async throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, (1...10 * 1024 * 1024).contains(size) else { throw RecordError(message: "Receipt must be a file smaller than 10 MB.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let ext = url.pathExtension.lowercased()
        guard let mime = ReceiptRules.mimeType(extension: ext, data: data) else {
            throw RecordError(message: "The receipt contents do not match an allowed file type or size.")
        }
        let client = SupabaseClientManager.shared.client
        let user = try await client.auth.session.user.id.uuidString.lowercased()
        let path = "\(user)/\(UUID().uuidString.lowercased()).\(ext)"
        try await client.storage.from("receipts").upload(path, data: data, options: FileOptions(contentType: mime, upsert: false))
        return path
    }
    func signedURL(for expense: Expense) async throws -> URL {
        let client = SupabaseClientManager.shared.client
        var path = expense.receiptPath
        if path == nil, let legacy = expense.receiptUrl, let url = URL(string: legacy) {
            let prefix = "/storage/v1/object/sign/receipts/"
            guard url.scheme == "https", url.host == SupabaseConfig.shared.projectURL.host, url.path.hasPrefix(prefix) else { throw RecordError.invalid }
            path = String(url.path.dropFirst(prefix.count))
        }
        guard let path, !path.hasPrefix("/"), !path.contains(".."), !path.contains("\\"), path.count <= 300 else { throw RecordError.invalid }
        return try await client.storage.from("receipts").createSignedURL(path: path, expiresIn: 60)
    }
}
