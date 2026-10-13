import SwiftUI

struct AIConsentControl: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var consent = AIConsentStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI is optional. Amountly sends the text, receipt files, and selected financial record details used by AI features to OpenAI for processing. These may include personal information. Review suggestions before applying them.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Read the privacy policy", destination: AmountlyLinks.privacy)
                .font(.caption)
            if consent.allows(userID: appState.currentUser?.id, sessionGeneration: AmountlyPlatform.transport.generation) {
                Button("Turn off AI data sharing") { consent.revoke() }
                    .accessibilityIdentifier("ai.consent.revoke")
                Text("Turning sharing off stops future AI requests. Information already sent is subject to OpenAI's applicable terms and data controls.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Allow AI for this session") {
                    guard let id = appState.currentUser?.id, appState.isAuthenticated else { return }
                    consent.allow(userID: id, sessionGeneration: AmountlyPlatform.transport.generation)
                }
                .accessibilityIdentifier("ai.consent.allow")
                Text("You can keep using manual entry without enabling AI. Turn sharing off here or in Settings → AI Privacy. Permission resets when you sign out or close the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.buttonStyle(.borderless)
    }
}
