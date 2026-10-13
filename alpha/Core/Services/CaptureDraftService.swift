import Foundation

enum CaptureError: LocalizedError {
    case conflict, full, invalid, unavailable
    var errorDescription: String? {
        switch self {
        case .conflict: "This capture changed elsewhere. Close and reopen it before saving."
        case .full: "Capture storage is full. Finish or discard an existing capture first."
        case .invalid: "Check the capture fields and receipt before keeping it."
        case .unavailable: "Could not confirm the capture. Your form is still available; retry the original request."
        }
    }
}
@MainActor
final class CaptureDraftService {
    private let transport: AmountlyTransport
    private let authenticate: () async throws -> Void
    init(transport: AmountlyTransport? = nil, authenticate: (() async throws -> Void)? = nil) {
        self.transport = transport ?? AmountlyPlatform.transport
        self.authenticate = authenticate ?? {
#if DEBUG
            guard SupabaseClientManager.shared.client.localClient == nil else { throw PlatformError.signIn }
#endif
            _ = try await SupabaseClientManager.shared.client.auth.session
        }
    }
    private func check(_ response: HTTPURLResponse) throws {
        if response.statusCode == 409 { throw CaptureError.conflict }
        if response.statusCode == 413 { throw CaptureError.full }
        try AmountlyTransport.check(response, mime: response.statusCode == 204 ? nil : "application/json")
    }
    func list() async throws -> [CaptureDraft] {
        try await authenticate()
        let (data, response) = try await transport.request(path: "/api/capture-drafts", limit: 700000)
        try check(response)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.count <= 10 else { throw CaptureError.invalid }
        return try rows.map { try CaptureDraft.decode(JSONSerialization.data(withJSONObject: $0)) }
    }
    func keep(id: UUID, revision: Int, payload: CapturePayload, file: URL?, originalName: String? = nil) async throws -> CaptureDraft {
        guard (0...2147483646).contains(revision) else { throw CaptureError.invalid }
        try payload.validate()
        struct Write: Encodable { let id: UUID; let revision: Int; let payload: CapturePayload }
        let metadata = try JSONEncoder().encode(Write(id: id, revision: revision, payload: payload))
        guard metadata.count <= 32768 else { throw CaptureError.invalid }
        let boundary = "Amountly-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n".utf8)
        body.append(metadata); body.append(Data("\r\n".utf8))
        if let file {
            let receipt = try ReceiptStorage.read(url: file)
            let filename = String((originalName ?? file.lastPathComponent).prefix(200)).replacingOccurrences(of: #"[\x00-\x1f\x7f/\\\"]"#, with: "_", options: .regularExpression)
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename.isEmpty ? "receipt" : filename)\"\r\nContent-Type: \(receipt.mime)\r\n\r\n".utf8))
            body.append(receipt.data); body.append(Data("\r\n".utf8))
        } else if payload.extraction != nil { throw CaptureError.invalid }
        body.append(Data("--\(boundary)--\r\n".utf8))
        try await authenticate()
        let (data, response) = try await transport.request(path: "/api/capture-drafts", method: "PUT", body: body, mime: "multipart/form-data; boundary=\(boundary)", limit: 70000)
        try check(response)
        let draft = try CaptureDraft.decode(data)
        guard draft.id == id, draft.revision == revision + 1 else { throw CaptureError.invalid }
        return draft
    }
    func original(_ draft: CaptureDraft) async throws -> URL? {
        guard let mime = draft.content_type else { return nil }
        guard let ext = ["image/jpeg":"jpg", "image/png":"png", "image/webp":"webp", "application/pdf":"pdf"][mime], (1...2147483647).contains(draft.revision) else { throw CaptureError.invalid }
        try await authenticate()
        let (data, response) = try await transport.request(path: "/api/capture-drafts?id=\(draft.id.uuidString)&file=1&revision=\(draft.revision)", limit: ReceiptRules.maxBytes)
        try AmountlyTransport.check(response, mime: mime)
        guard ReceiptRules.mimeType(extension: ext, data: data) == mime else { throw CaptureError.invalid }
        return try PrivateDocument.write(data, extension: ext, prefix: "receipt")
    }
    func discard(_ draft: CaptureDraft) async throws {
        guard (1...2147483647).contains(draft.revision) else { throw CaptureError.invalid }
        struct Remove: Encodable { let id: UUID; let revision: Int }
        try await authenticate()
        let (_, response) = try await transport.request(path: "/api/capture-drafts", method: "DELETE", body: JSONEncoder().encode(Remove(id: draft.id, revision: draft.revision)), limit: 2048)
        try check(response)
        guard response.statusCode == 204 else { throw CaptureError.invalid }
    }
}
