import Foundation
import Combine

// Consent stays in memory and belongs to one signed-in session. A new account,
// sign-out, app restart, or withdrawal requires a fresh explicit choice.
@MainActor
final class AIConsentStore: ObservableObject {
    static let shared = AIConsentStore()
    @Published private(set) var revision = UUID()
    private var userID: UUID?
    private var sessionGeneration: UUID?

    func allow(userID: String, sessionGeneration: UUID) {
        guard let id = UUID(uuidString: userID) else { return }
        self.userID = id
        self.sessionGeneration = sessionGeneration
        revision = UUID()
    }

    func revoke() {
        userID = nil
        sessionGeneration = nil
        revision = UUID()
    }

    func allows(userID: String?, sessionGeneration: UUID) -> Bool {
        guard let raw = userID, let id = UUID(uuidString: raw) else { return false }
        return self.userID == id && self.sessionGeneration == sessionGeneration
    }

    func authorization(sessionGeneration: UUID) throws -> UUID {
        guard userID != nil, self.sessionGeneration == sessionGeneration else { throw PlatformError.consent }
        return revision
    }

    func validate(_ authorization: UUID, sessionGeneration: UUID) throws {
        guard try self.authorization(sessionGeneration: sessionGeneration) == authorization else { throw PlatformError.consent }
    }
}
