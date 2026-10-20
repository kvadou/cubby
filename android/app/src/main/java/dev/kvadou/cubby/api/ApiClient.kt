package dev.kvadou.cubby.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

sealed class ApiError(override val message: String) : Exception(message) {
    /** The token is missing, expired, or revoked: sign in again. */
    data object Unauthorized : ApiError("Your session ended. Please sign in again.")
    data class InvalidLogin(val text: String) : ApiError(text)
    data class RateLimited(val text: String) : ApiError(text)
    /** The deployed demo is switched off (CloudFront answers 503 "offline"). */
    data object Offline : ApiError("Cubby's demo servers are switched off right now. Try again later.")
    data object NotFound : ApiError("That isn't available anymore.")
    data class Server(val status: Int, val text: String?) :
        ApiError(text ?: "Something went wrong on Cubby's side. Try again in a moment.")
    data object Network : ApiError("Couldn't reach Cubby. Check your connection and try again.")
}

/**
 * Talks to the Rails API with a bearer token. Bearer requests are exempt from the API's same-origin
 * check, which only applies to browser cookie sessions.
 */
class ApiClient(
    baseUrl: String,
    val token: String? = null,
    private val http: OkHttpClient = defaultHttp,
) {
    private val base = baseUrl.trimEnd('/').toHttpUrl()

    fun withToken(token: String?) = ApiClient(base.toString(), token, http)

    suspend fun signIn(email: String, password: String): TokenResponse =
        send("POST", "/api/v1/tokens", buildJsonObject {
            put("email_address", email)
            put("password", password)
        }.toString().toRequestBody(JSON))

    suspend fun signOut() {
        send<Unit>("DELETE", "/api/v1/tokens/current")
    }

    suspend fun home(): FamilyHome = send("GET", "/api/v1/family")
    suspend fun messages(): List<FamilyMessage> = send("GET", "/api/v1/family/messages")
    suspend fun invoices(): List<Invoice> = send("GET", "/api/v1/family/invoices")
    suspend fun attendance(childId: Int, days: Int = 14): List<AttendanceDay> =
        send("GET", "/api/v1/family/children/$childId/attendance?days=$days")
    suspend fun markRead(messageId: Int): FamilyMessage =
        send("POST", "/api/v1/family/messages/$messageId/read", EMPTY)

    private suspend inline fun <reified T> send(method: String, path: String, body: RequestBody? = null): T {
        val request = Request.Builder()
            .url(base.resolve(path) ?: throw ApiError.NotFound)
            .method(method, body)
            .header("Accept", "application/json")
            .apply { token?.let { header("Authorization", "Bearer $it") } }
            .build()

        val (status, text) = withContext(Dispatchers.IO) {
            try {
                http.newCall(request).execute().use { it.code to it.body.string() }
            } catch (_: IOException) {
                throw ApiError.Network
            }
        }
        return when {
            status == 204 && T::class == Unit::class -> Unit as T
            status in 200..299 -> CubbyJson.decodeFromString<T>(text)
            else -> throw errorFor(status, runCatching { CubbyJson.decodeFromString<ErrorBody>(text) }.getOrNull())
        }
    }

    companion object {
        private val JSON = "application/json".toMediaType()
        private val EMPTY = ByteArray(0).toRequestBody(null)
        private val defaultHttp = OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build()

        internal fun errorFor(status: Int, body: ErrorBody?): ApiError = when {
            status == 401 && body?.error == "invalid_login" ->
                ApiError.InvalidLogin(body.message ?: "That email and password don't match.")
            status == 401 -> ApiError.Unauthorized
            status == 404 -> ApiError.NotFound
            status == 429 -> ApiError.RateLimited(body?.message ?: "Too many attempts. Try again in a few minutes.")
            status == 503 && body?.error == "offline" -> ApiError.Offline
            else -> ApiError.Server(status, body?.message)
        }
    }
}
