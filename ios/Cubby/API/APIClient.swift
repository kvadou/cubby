import Foundation

enum APIError: Error, Equatable, LocalizedError {
    /// The token is missing, expired, or revoked: sign in again.
    case unauthorized
    case invalidLogin(String)
    case rateLimited(String)
    /// The deployed demo is switched off (CloudFront answers 503 "offline").
    case offline
    case notFound
    case server(status: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Your session ended. Please sign in again."
        case .invalidLogin(let message), .rateLimited(let message): message
        case .offline: "Cubby's demo servers are switched off right now. Try again later."
        case .notFound: "That isn't available anymore."
        case .server(_, let message): message ?? "Something went wrong on Cubby's side. Try again in a moment."
        case .network: "Couldn't reach Cubby. Check your connection and try again."
        }
    }
}

/// Talks to the Rails API with a bearer token. Bearer requests are exempt from the API's
/// same-origin check, which only applies to browser cookie sessions.
struct APIClient: Sendable {
    let baseURL: URL
    var token: String?
    var session: URLSession = .shared

    private struct ErrorBody: Decodable {
        let error: String?
        let message: String?
    }

    func signIn(email: String, password: String) async throws -> TokenResponse {
        try await send("POST", "/api/v1/tokens", body: ["email_address": email, "password": password])
    }

    func signOut() async throws {
        let _: Empty = try await send("DELETE", "/api/v1/tokens/current")
    }

    func me() async throws -> Me { try await send("GET", "/api/v1/me") }
    func home() async throws -> FamilyHome { try await send("GET", "/api/v1/family") }
    func messages() async throws -> [FamilyMessage] { try await send("GET", "/api/v1/family/messages") }
    func invoices() async throws -> [Invoice] { try await send("GET", "/api/v1/family/invoices") }

    func attendance(childID: Int, days: Int = 14) async throws -> [AttendanceDay] {
        try await send("GET", "/api/v1/family/children/\(childID)/attendance?days=\(days)")
    }

    func markRead(_ messageID: Int) async throws -> FamilyMessage {
        try await send("POST", "/api/v1/family/messages/\(messageID)/read")
    }

    struct Empty: Decodable {}

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.notFound }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No HTTP response") }

        let decoder = JSONDecoder.cubby
        switch http.statusCode {
        case 204:
            if let empty = Empty() as? T { return empty }
            throw APIError.server(status: 204, message: nil)
        case 200..<300:
            return try decoder.decode(T.self, from: data)
        default:
            let error = try? decoder.decode(ErrorBody.self, from: data)
            throw Self.error(status: http.statusCode, body: error)
        }
    }

    private static func error(status: Int, body: ErrorBody?) -> APIError {
        switch (status, body?.error) {
        case (401, "invalid_login"): .invalidLogin(body?.message ?? "That email and password don't match.")
        case (401, _): .unauthorized
        case (404, _): .notFound
        case (429, _): .rateLimited(body?.message ?? "Too many attempts. Try again in a few minutes.")
        case (503, "offline"): .offline
        default: .server(status: status, message: body?.message)
        }
    }
}
