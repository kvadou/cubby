package dev.kvadou.cubby.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.WifiOff
import dev.kvadou.cubby.Session
import dev.kvadou.cubby.api.ApiClient
import dev.kvadou.cubby.api.ApiError
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

sealed interface Loadable<out T> {
    data object Loading : Loadable<Nothing>
    data class Loaded<T>(val value: T) : Loadable<T>
    data class Failed(val error: ApiError) : Loadable<Nothing>
}

/**
 * Loads a value from the API and handles the session ending, so each screen only describes its
 * content, empty, and error states (the counterpart of the iOS Loader).
 */
class Loader<T>(private val session: Session, private val fetch: suspend (ApiClient) -> T) {
    var state by mutableStateOf<Loadable<T>>(Loadable.Loading)
        private set
    var refreshing by mutableStateOf(false)
        private set

    suspend fun load() {
        refreshing = state is Loadable.Loaded
        state = try {
            Loadable.Loaded(fetch(session.client))
        } catch (_: ApiError.Unauthorized) {
            session.end()
            return
        } catch (e: ApiError) {
            Loadable.Failed(e)
        } catch (_: Exception) {
            Loadable.Failed(ApiError.Server(0, null))
        } finally {
            refreshing = false
        }
    }

    fun replace(value: T) {
        state = Loadable.Loaded(value)
    }
}

@Composable
fun <T> rememberLoader(session: Session, fetch: suspend (ApiClient) -> T): Loader<T> {
    val loader = remember(session) { Loader(session, fetch) }
    LaunchedEffect(loader) { loader.load() }
    return loader
}

/** Spinner, error, or content, the same way on every tab. */
@Composable
fun <T> LoadingContent(loader: Loader<T>, modifier: Modifier = Modifier, content: @Composable (T) -> Unit) {
    val scope = rememberCoroutineScope()
    when (val state = loader.state) {
        Loadable.Loading -> Column(modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
            CircularProgressIndicator()
        }
        is Loadable.Failed -> EmptyState(
            icon = if (state.error == ApiError.Offline) Icons.Outlined.Bedtime else Icons.Outlined.WifiOff,
            title = if (state.error == ApiError.Offline) "The demo is offline" else "Couldn't load this",
            message = state.error.message,
            modifier = modifier,
            action = "Try again" to { scope.launch { loader.load() } },
        )
        is Loadable.Loaded -> content(state.value)
    }
}

@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    action: Pair<String, () -> Unit>? = null,
) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, contentDescription = null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (action != null) {
            Spacer(Modifier.height(24.dp))
            Button(onClick = action.second) { Text(action.first) }
        }
    }
}

/** Shows times in the center's time zone, which is what a parent standing at the door sees. */
class CenterClock(timezone: String) {
    private val zone = runCatching { ZoneId.of(timezone) }.getOrDefault(ZoneId.systemDefault())
    private val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(zone)
    private val dayTime = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withZone(zone)

    fun time(instant: Instant): String = time.format(instant)
    fun dayAndTime(instant: Instant): String = dayTime.format(instant)
}

private val shortDay = DateTimeFormatter.ofPattern("EEE, MMM d")
private val mediumDay = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
private val monthFormat = DateTimeFormatter.ofPattern("MMMM")

/** "Mon, Oct 19". */
val LocalDate.shortLabel: String get() = shortDay.format(this)
val LocalDate.mediumLabel: String get() = mediumDay.format(this)
val LocalDate.monthName: String get() = monthFormat.format(this)

fun dollars(cents: Long): String = java.text.NumberFormat.getCurrencyInstance(java.util.Locale.US).format(cents / 100.0)

/** "3 hours ago", like the iOS relative date; under a minute is "Just now", not "0 minutes ago". */
fun relative(instant: Instant, now: Instant = Instant.now()): String =
    if (java.time.Duration.between(instant, now).abs().seconds < 60) "Just now" else android.text.format.DateUtils.getRelativeTimeSpanString(
        instant.toEpochMilli(), now.toEpochMilli(), android.text.format.DateUtils.MINUTE_IN_MILLIS,
    ).toString()
