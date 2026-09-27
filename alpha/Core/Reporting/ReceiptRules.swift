import Foundation

// Reject mismatched types and oversized data before uploading private receipts.
enum ReceiptRules {
    nonisolated static let maxBytes = 10 * 1024 * 1024
    nonisolated static func mimeType(extension ext: String, data: Data) -> String? {
        guard !data.isEmpty, data.count <= maxBytes else { return nil }
        let bytes = [UInt8](data.prefix(12))
        switch ext.lowercased() {
        case "jpg", "jpeg": return bytes.starts(with: [0xff,0xd8,0xff]) ? "image/jpeg" : nil
        case "png": return bytes.starts(with: [137,80,78,71,13,10,26,10]) ? "image/png" : nil
        case "pdf": return bytes.starts(with: Array("%PDF-".utf8)) ? "application/pdf" : nil
        case "webp": return bytes.starts(with: Array("RIFF".utf8)) && Array(bytes.dropFirst(8)) == Array("WEBP".utf8) ? "image/webp" : nil
        default: return nil
        }
    }
}
