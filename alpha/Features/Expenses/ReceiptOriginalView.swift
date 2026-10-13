import SwiftUI
import PDFKit
import ImageIO

// Render originals as pixels. PDF links, forms and scripts have no interactive
// surface; page count and bitmap size stay bounded while pinch zoom is native.
struct ReceiptOriginalView: View {
    let url: URL
    @State private var page = 0
    @State private var pages = 1
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 12) {
            if let error { Text(error).foregroundStyle(.red) }
            if let image { ReceiptZoomImage(image: image).frame(minHeight: 320).accessibilityLabel("Original receipt page \(page + 1)").accessibilityIdentifier("receipt.original.page") }
            if pages > 1 {
                HStack {
                    Button("Previous page") { page -= 1 }.disabled(page == 0)
                    Text("Page \(page + 1) of \(pages)")
                    Button("Next page") { page += 1 }.disabled(page + 1 == pages)
                }
            }
            Text("Pinch to zoom. Compare the original with the saved fields before confirming review.").font(.caption)
        }
        .task(id: page) { render() }
    }
    private func render() {
        do {
            let rendered = try Self.renderedPage(url: url, page: page)
            image = rendered.image; pages = rendered.pages
            error = nil
        } catch { image = nil; self.error = "This original cannot be displayed. Use Share original to inspect the downloaded file." }
    }
    static func renderedPage(url: URL, page: Int) throws -> (image: UIImage, pages: Int) {
        let file = try ReceiptStorage.read(url: url)
        if file.mime == "application/pdf" {
            guard let document = PDFDocument(data: file.data), (1...5).contains(document.pageCount), page >= 0, page < document.pageCount, let sheet = document.page(at: page) else { throw PlatformError.response }
            return (sheet.thumbnail(of: CGSize(width: 1600, height: 2000), for: .mediaBox), document.pageCount)
        }
        guard page == 0, let source = CGImageSourceCreateWithData(file.data as CFData, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceThumbnailMaxPixelSize:2048, kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { throw PlatformError.response }
        return (UIImage(cgImage: bitmap), 1)
    }
}
private struct ReceiptZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ReceiptZoomScroll { ReceiptZoomScroll() }
    func updateUIView(_ view: ReceiptZoomScroll, context: Context) {
        if view.picture.image !== image { view.zoomScale = 1; view.picture.image = image; view.setNeedsLayout() }
    }
}
private final class ReceiptZoomScroll: UIScrollView, UIScrollViewDelegate {
    let picture = UIImageView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
        picture.contentMode = .scaleAspectFit; addSubview(picture)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 { picture.frame = bounds; contentSize = bounds.size }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
}
struct SavedReceiptReviewSheet: View {
    let expense: Expense
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var original: URL?
    @State private var error: String?
    @State private var sharing = false
    @State private var visible = true
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(expense.description).font(.headline)
                    Text("\(expense.amountFormatted) · \(RecordCoding.day(expense.expenseDate)) · \(expense.category.displayName)")
                    if let merchant = expense.merchant { Text(merchant) }
                    if let original { ReceiptOriginalView(url: original); Button("Share original") { sharing = true } }
                    else if let error { Text(error).foregroundStyle(.red) }
                    else { ProgressView("Loading original…") }
                }.padding()
            }.navigationTitle("Original receipt")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            guard original == nil else { return }
            do { let url = try await ReceiptStorage().signedURL(for: expense); try Task.checkCancellation(); original = url }
            catch { self.error = "Could not display the original. Check access and reopen this record." }
        }
        .sheet(isPresented: $sharing, onDismiss: { if !visible, let original { try? FileManager.default.removeItem(at: original) } }) { if let original { ShareSheet(activityItems: [original]) } }
        .onAppear { visible = true }
        .onDisappear { visible = false; if !sharing, let original { try? FileManager.default.removeItem(at: original) } }
        .onChange(of: appState.currentUser?.id) { _, _ in original = nil; dismiss() }
    }
}
