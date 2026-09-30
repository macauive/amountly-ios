import UIKit
import Vision
import VisionKit

// OCR only. Financial interpretation uses the shared, validated AI receipt task.
enum ReceiptScanner {
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }
    nonisolated static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.input }
            return text
        }.value
    }
}
