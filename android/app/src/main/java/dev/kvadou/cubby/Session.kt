package dev.kvadou.cubby

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import dev.kvadou.cubby.api.ApiClient
import dev.kvadou.cubby.api.ApiError

/** The signed-in parent, kept across launches by [TokenStore]. */
class Session(application: Application) : AndroidViewModel(application) {
    private val store = TokenStore(application)

    var client by mutableStateOf(ApiClient(BuildConfig.API_URL, store.read()))
        private set
    var name by mutableStateOf(store.name.takeIf { client.token != null })
        private set
    val signedIn: Boolean get() = client.token != null && name != null

    suspend fun signIn(email: String, password: String) {
        val response = client.signIn(email.trim(), password)
        if (response.families.isEmpty()) {
            // A director account: revoke the token we just got, and point them at the web app.
            runCatching { client.withToken(response.token).signOut() }
            throw ApiError.Server(403, "This app is for families. Directors use Cubby on the web.")
        }
        store.save(response.token, response.user.name)
        client = client.withToken(response.token)
        name = response.user.name
    }

    /** Revokes the token on the server when it can, and always forgets it locally. */
    suspend fun signOut() {
        runCatching { client.signOut() }
        end()
    }

    /** Called when the API says the token is no longer valid. */
    fun end() {
        store.clear()
        client = client.withToken(null)
        name = null
    }
}
