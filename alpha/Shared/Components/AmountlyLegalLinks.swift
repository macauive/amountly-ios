import SwiftUI

struct AmountlyLegalLinks: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Amountly by Mac Digital").foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Link("Privacy", destination: AmountlyLinks.privacy)
                Link("Terms", destination: AmountlyLinks.terms)
                Link("Support", destination: AmountlyLinks.support)
            }
        }.font(.caption)
    }
}
