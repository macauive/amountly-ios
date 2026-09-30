import SwiftUI
import VisionKit

struct ReceiptScannerView: UIViewControllerRepresentable {
    let onScanComplete: (String) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ReceiptScannerView
        private var recognition: Task<Void, Never>?
        init(_ parent: ReceiptScannerView) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard (1...10).contains(scan.pageCount) else { parent.onError("Scan between 1 and 10 pages."); parent.dismiss(); return }
            recognition = Task {
                do {
                    var pages: [String] = []
                    for index in 0..<scan.pageCount {
                        try Task.checkCancellation()
                        guard let image = scan.imageOfPage(at: index).cgImage else { throw AIError.input }
                        pages.append(try await ReceiptScanner.recognize(image))
                        guard pages.joined(separator: "\n").utf16.count <= 12000 else { throw AIError.input }
                    }
                    try Task.checkCancellation()
                    parent.onScanComplete(pages.joined(separator: "\n"))
                } catch is CancellationError { }
                catch { parent.onError("Could not read this receipt. Try fewer pages or paste its text into Receipt/document extraction.") }
                parent.dismiss()
            }
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { recognition?.cancel(); parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            recognition?.cancel(); parent.onError("The camera could not scan the receipt. Try again or paste receipt text."); parent.dismiss()
        }
        func cancel() { recognition?.cancel() }
    }
    static func dismantleUIViewController(_ controller: VNDocumentCameraViewController, coordinator: Coordinator) { coordinator.cancel() }
}
