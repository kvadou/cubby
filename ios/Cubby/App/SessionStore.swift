import Foundation
import Observation
import Security

/// The signed-in parent. The bearer token lives in the Keychain (this device only, readable after the
/// first unlock) so it never lands in backups or UserDefaults.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case signedOut
        case signedIn(name: String)
    }

    private(set) var state: State = .signedOut
    private(set) var client: APIClient

    init(baseURL: URL = SessionStore.configuredBaseURL) {
        client = APIClient(baseURL: baseURL, token: Keychain.read())
        if client.token != nil, let name = UserDefaults.standard.string(forKey: Self.nameKey) {
            state = .signedIn(name: name)
        }
    }

    func signIn(email: String, password: String) async throws {
        let response = try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        guard !response.families.isEmpty else {
            // A director account: revoke the token we just got, and point them at the web app.
            try? await APIClient(baseURL: client.baseURL, token: response.token).signOut()
            throw APIError.server(status: 403, message: "This app is for families. Directors use Cubby on the web.")
        }
        Keychain.save(response.token)
        client.token = response.token
        UserDefaults.standard.set(response.user.name, forKey: Self.nameKey)
        state = .signedIn(name: response.user.name)
    }

    /// Revokes the token on the server when it can, and always forgets it locally.
    func signOut() async {
        try? await client.signOut()
        endSession()
    }

    /// Called when the API says the token is no longer valid.
    func endSession() {
        Keychain.delete()
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        client.token = nil
        state = .signedOut
    }

    private static let nameKey = "cubby.signedInName"

    nonisolated static var configuredBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CubbyAPIURL") as? String
        return raw.flatMap(URL.init(string:)) ?? URL(string: "http://localhost:3000")!
    }
}

enum Keychain {
    private static let service = "dev.kvadou.cubby"
    private static let account = "api-token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ token: String) {
        delete()
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
