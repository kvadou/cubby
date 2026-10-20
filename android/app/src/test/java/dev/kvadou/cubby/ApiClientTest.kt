package dev.kvadou.cubby

import dev.kvadou.cubby.api.ApiClient
import dev.kvadou.cubby.api.ApiError
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.LocalDate

/** The client against canned responses, mirroring ios/CubbyTests/APIClientTests.swift. */
class ApiClientTest {
    private lateinit var server: MockWebServer

    @Before fun start() {
        server = MockWebServer().apply { start() }
    }

    @After fun stop() {
        server.close()
    }

    private fun client(token: String? = "t0ken") = ApiClient(server.url("/").toString(), token)

    private fun respond(status: Int, body: String) {
        server.enqueue(MockResponse.Builder().code(status).addHeader("Content-Type", "application/json").body(body).build())
    }

    @Test fun sendsTheBearerTokenAndDecodesTheHome() = runTest {
        respond(200, """
            {"family":{"id":1,"name":"Russel family","guardian_name":"Vaughn Russel"},
             "center":{"name":"Little Oaks","city":"Minneapolis","timezone":"America/Chicago","director_name":"Renee Albright"},
             "today":"2026-10-19","unread_messages":2,
             "children":[{"id":7,"first_name":"Meryl","classroom":"Maples","status":"enrolled",
                          "today":{"checked_in_at":"2026-10-19T07:45:00-05:00","checked_out_at":null}}]}
        """)
        val home = client().home()
        val request = server.takeRequest()
        assertEquals("Bearer t0ken", request.headers["Authorization"])
        assertEquals("/api/v1/family", request.url.encodedPath)
        assertEquals(LocalDate.of(2026, 10, 19), home.today)
        assertEquals(Instant.parse("2026-10-19T12:45:00Z"), home.children[0].today?.checkedInAt)
        assertNull(home.children[0].today?.checkedOutAt)
        assertEquals("Renee Albright", home.center.directorName)
    }

    @Test fun decodesInvoicesWithDateOnlyFields() = runTest {
        respond(200, """
            [{"id":3,"number":"LO-1","amount_cents":145000,"period_start":"2026-09-01","period_end":"2026-09-30",
              "due_on":"2026-09-05","status":"open","days_past_due":44,"paid_at":null,"added_later":true}]
        """)
        val invoice = client().invoices().single()
        assertTrue(invoice.isPastDue)
        assertEquals(145000L, invoice.amountCents)
        assertEquals(LocalDate.of(2026, 9, 5), invoice.dueOn)
    }

    @Test fun mapsErrorsTheAppHandles() = runTest {
        suspend fun expect(error: ApiError, status: Int, body: String, call: suspend ApiClient.() -> Unit) {
            respond(status, body)
            try {
                client().call()
                fail("expected $error")
            } catch (e: ApiError) {
                assertEquals(error, e)
            }
        }
        expect(ApiError.Unauthorized, 401, """{"error":"unauthenticated"}""") { messages() }
        expect(ApiError.InvalidLogin("That email and password don't match."), 401,
            """{"error":"invalid_login","message":"That email and password don't match."}""") { signIn("a@b.test", "x") }
        expect(ApiError.Offline, 503, """{"error":"offline","message":"The demo is offline."}""") { home() }
        expect(ApiError.NotFound, 404, """{"error":"not_found"}""") { attendance(99) }
        expect(ApiError.Server(500, null), 500, "<html>oops</html>") { invoices() }
    }

    @Test fun signOutAcceptsNoContent() = runTest {
        server.enqueue(MockResponse.Builder().code(204).build())
        client().signOut()
        val request = server.takeRequest()
        assertEquals("DELETE", request.method)
        assertEquals("/api/v1/tokens/current", request.url.encodedPath)
    }

    @Test fun sendsSignInAsJsonWithoutAToken() = runTest {
        respond(201, """{"token":"abc","user":{"id":1,"name":"Vaughn","email_address":"p@x.test"},"centers":[],
            "families":[{"id":1,"name":"Russel family","center_name":"Little Oaks"}],"expires_at":"2026-11-18T00:00:00Z"}""")
        val response = client(token = null).signIn("p@x.test", "se\"cret")
        val request = server.takeRequest()
        assertEquals("abc", response.token)
        assertNull(request.headers["Authorization"])
        assertTrue(request.headers["Content-Type"]!!.startsWith("application/json"))
        assertEquals("""{"email_address":"p@x.test","password":"se\"cret"}""", request.body!!.utf8())
    }
}
