import Foundation
import Testing
@testable import Cubby

/// Serves canned responses so the client is tested without a server.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let (status, body) = Self.handler?(request) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct APIClientTests {
    private func client(token: String? = "t0ken", _ handler: @escaping (URLRequest) -> (Int, String)) -> APIClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "http://localhost:3000")!, token: token, session: URLSession(configuration: config))
    }

    @Test func sendsTheBearerTokenAndDecodesTheHome() async throws {
        let api = client { _ in
            (200, """
            {"family":{"id":1,"name":"Russel family","guardian_name":"Vaughn Russel"},
             "center":{"name":"Little Oaks","city":"Minneapolis","timezone":"America/Chicago","director_name":"Renee Albright"},
             "today":"2026-10-19","unread_messages":2,
             "children":[{"id":7,"first_name":"Meryl","classroom":"Maples","status":"enrolled",
                          "today":{"checked_in_at":"2026-10-19T07:45:00-05:00","checked_out_at":null}}]}
            """)
        }
        let home = try await api.home()
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
        #expect(StubProtocol.lastRequest?.url?.path == "/api/v1/family")
        #expect(home.today == CalendarDay(year: 2026, month: 10, day: 19))
        #expect(home.children.first?.today?.checkedOutAt == nil)
        let clock = CenterClock(identifier: home.center.timezone)
        #expect(clock.time(home.children[0].today!.checkedInAt).contains("7:45"))
    }

    @Test func decodesInvoicesWithDateOnlyFields() async throws {
        let api = client { _ in
            (200, """
            [{"id":3,"number":"LO-1","amount_cents":145000,"period_start":"2026-09-01","period_end":"2026-09-30",
              "due_on":"2026-09-05","status":"open","days_past_due":44,"paid_at":null}]
            """)
        }
        let invoice = try #require(try await api.invoices().first)
        #expect(invoice.isPastDue)
        #expect(invoice.amount == Decimal(1450))
        #expect(invoice.dueOn.mediumLabel.contains("5"))
    }

    @Test func mapsErrorsTheAppHandles() async throws {
        await #expect(throws: APIError.unauthorized) {
            try await client { _ in (401, #"{"error":"unauthenticated"}"#) }.messages()
        }
        await #expect(throws: APIError.invalidLogin("That email and password don't match.")) {
            try await client(token: nil) { _ in (401, #"{"error":"invalid_login","message":"That email and password don't match."}"#) }
                .signIn(email: "a@b.test", password: "x")
        }
        await #expect(throws: APIError.offline) {
            try await client { _ in (503, #"{"error":"offline","message":"The demo is offline."}"#) }.home()
        }
        await #expect(throws: APIError.notFound) {
            try await client { _ in (404, #"{"error":"not_found"}"#) }.attendance(childID: 99)
        }
    }

    @Test func signOutAcceptsNoContent() async throws {
        let api = client { _ in (204, "") }
        try await api.signOut()
        #expect(StubProtocol.lastRequest?.httpMethod == "DELETE")
        #expect(StubProtocol.lastRequest?.url?.path == "/api/v1/tokens/current")
    }

    @Test func sendsSignInAsJSONWithoutAToken() async throws {
        let api = client(token: nil) { _ in
            (201, #"{"token":"abc","user":{"id":1,"name":"Vaughn","email_address":"p@x.test"},"centers":[],"families":[{"id":1,"name":"Russel family","center_name":"Little Oaks"}],"expires_at":"2026-11-18T00:00:00Z"}"#)
        }
        let response = try await api.signIn(email: "p@x.test", password: "secret")
        #expect(response.token == "abc")
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
