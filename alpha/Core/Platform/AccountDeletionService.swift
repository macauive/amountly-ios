import Foundation

@MainActor
struct AccountDeletionService {
    let transport: AmountlyTransport

    // No client-supplied user ID: the server derives ownership from the session.
    func request() async throws {
        _ = try transport.cookieHeader()
        let (data, response) = try await transport.request(path: "/api/account/deletion-request", method: "POST", body: Data("{}".utf8), limit: 1024)
        try AmountlyTransport.check(response)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["requested"] else { throw PlatformError.response }
        struct Confirmation: Decodable { let requested: Bool }
        guard let confirmation = try? JSONDecoder().decode(Confirmation.self, from: data), confirmation.requested else { throw PlatformError.response }
    }
}
