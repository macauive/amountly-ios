import UIKit

// Native document renderer: wraps long text and starts a page before overflow.
final class InvoicePDFGenerator {
    func generatePDF(for invoice: Invoice, organization: Organization?) -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            var y: CGFloat = 48
            var page = 0
            func startPage() {
                context.beginPage(); page += 1; y = 48
                let footer = "\(invoice.invoiceNumber) · Page \(page)"
                footer.draw(at: CGPoint(x: 48, y: 755), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            }
            func line(_ text: String, size: CGFloat = 11, bold: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black]
                // Draw in bounded paragraph fragments so even a very long note paginates.
                for paragraph in text.components(separatedBy: .newlines) {
                    var remainder = paragraph
                    repeat {
                        var count = min(remainder.count, 300)
                        var fragment = String(remainder.prefix(count))
                        var height = (fragment as NSString).boundingRect(with: CGSize(width: 516, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil).height + 6
                        while height > 650 && count > 1 {
                            count /= 2; fragment = String(remainder.prefix(count))
                            height = (fragment as NSString).boundingRect(with: CGSize(width: 516, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil).height + 6
                        }
                        if y + height > 725 { startPage() }
                        (fragment as NSString).draw(in: CGRect(x: 48, y: y, width: 516, height: height), withAttributes: attrs)
                        y += height
                        remainder = String(remainder.dropFirst(count))
                    } while !remainder.isEmpty
                }
            }
            func money(_ amount: Double) -> String { amount.formatted(.currency(code: invoice.currency)) }
            startPage()
            line(organization?.name ?? "Amountly", size: 22, bold: true)
            line("INVOICE \(invoice.invoiceNumber)", size: 18, bold: true)
            line(invoice.displayStatus.displayName)
            line("Issued: \(RecordCoding.day(invoice.issueDate))   Due: \(RecordCoding.day(invoice.dueDate))")
            line("Bill to", size: 14, bold: true)
            line(invoice.displayClientName ?? "Client")
            if let email = invoice.displayClientEmail { line(email) }
            if let address = invoice.displayClientAddress { line(address) }
            line("Description · Quantity × Rate · Amount", bold: true)
            for item in (invoice.issuedSnapshot?.lines ?? invoice.lineItems ?? []).sorted(by: { $0.order < $1.order }) {
                line(item.description, bold: true)
                line("\(item.quantity.formatted()) × \(money(item.rate)) = \(money(item.amount))")
            }
            line("Subtotal: \(money(invoice.subtotal))")
            line("Tax (\((invoice.taxRate ?? 0).formatted())%): \(money(invoice.taxAmount ?? 0))")
            line("Total: \(money(invoice.total))", size: 16, bold: true)
            line("Recorded payments: \(money(invoice.amountPaid))")
            line("Balance due: \(money(invoice.balanceDue))", bold: true)
            if invoice.needsLegacyReview { line("Historical Paid status has no recorded payment evidence.") }
            if let notes = invoice.notes, !notes.isEmpty { line("Notes", bold: true); line(notes) }
        }
    }
    func savePDF(_ data: Data, filename: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let safe = String(filename.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }.prefix(80))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(safe.isEmpty ? "invoice" : safe).pdf")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch { return nil }
    }
}
