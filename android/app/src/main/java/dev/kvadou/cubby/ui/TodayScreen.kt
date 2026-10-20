package dev.kvadou.cubby.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.ChildCare
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import dev.kvadou.cubby.Session
import dev.kvadou.cubby.api.AttendanceDay
import dev.kvadou.cubby.api.FamilyHome
import kotlinx.coroutines.launch

private val CheckedIn = Color(0xFF2E7D4F)

/** Each child's day: whether they're checked in now, then the last two weeks. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodayScreen(session: Session, onUnread: (Int) -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var history by remember { mutableStateOf<Map<Int, List<AttendanceDay>>>(emptyMap()) }
    val home = rememberLoader(session) { it.home() }

    // Attendance follows the home screen so a refresh updates both.
    val loaded = (home.state as? Loadable.Loaded)?.value
    LaunchedEffect(loaded) {
        loaded ?: return@LaunchedEffect
        onUnread(loaded.unreadMessages)
        history = loaded.children.associate { child ->
            child.id to (runCatching { session.client.attendance(child.id) }.getOrNull() ?: emptyList())
        }
    }

    val firstName = loaded?.family?.guardianName?.substringBefore(' ')
    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = { TopAppBar(title = { Text(firstName?.let { "Hi, $it" } ?: "Today") }) },
    ) { padding ->
        LoadingContent(home) { data ->
            PullToRefreshBox(
                isRefreshing = home.refreshing,
                onRefresh = { scope.launch { home.load() } },
                modifier = Modifier.fillMaxSize(),
            ) {
                TodayList(data, history, padding, onSignOut = { scope.launch { session.signOut() } })
            }
        }
    }
}

@Composable
private fun TodayList(
    home: FamilyHome,
    history: Map<Int, List<AttendanceDay>>,
    padding: PaddingValues,
    onSignOut: () -> Unit,
) {
    val clock = CenterClock(home.center.timezone)
    LazyColumn(contentPadding = padding, verticalArrangement = Arrangement.spacedBy(0.dp), modifier = Modifier.fillMaxSize()) {
        if (home.children.isEmpty()) {
            item {
                EmptyState(Icons.Outlined.ChildCare, "No children yet", "${home.center.name} hasn't added your children.")
            }
        }
        home.children.forEach { child ->
            val days = history[child.id].orEmpty()
            section(
                key = "child-${child.id}",
                title = child.firstName,
                rows = listOf<Any>(child) + days,
                footer = if (days.isEmpty()) "No check-ins in the last two weeks." else null,
            ) { row ->
                when (row) {
                    is FamilyHome.Child -> ChildTodayRow(row, clock)
                    is AttendanceDay -> AttendanceRow(row, clock, isToday = row.on == home.today)
                }
            }
        }
        section(key = "center", title = null, rows = listOf("Center" to home.center.name, "Director" to home.center.directorName)) {
            ListItem(
                headlineContent = { Text(it.first) },
                trailingContent = { Text(it.second, style = MaterialTheme.typography.bodyLarge) },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
        }
        item(key = "sign-out") {
            TextButton(
                onClick = onSignOut,
                modifier = Modifier.heightIn(min = 48.dp).testTag("signOut").padding(horizontal = 16.dp, vertical = 16.dp),
            ) {
                Text("Sign out", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun ChildTodayRow(child: FamilyHome.Child, clock: CenterClock) {
    val day = child.today
    val (icon, tint, headline) = when {
        day != null && day.checkedOutAt == null -> Triple(Icons.Filled.CheckCircle, CheckedIn, "Checked in")
        day != null -> Triple(Icons.Filled.Home, MaterialTheme.colorScheme.onSurfaceVariant, "Picked up")
        child.status == "waitlisted" -> Triple(Icons.Outlined.Bedtime, MaterialTheme.colorScheme.onSurfaceVariant, "On the waitlist")
        else -> Triple(Icons.Outlined.Bedtime, MaterialTheme.colorScheme.onSurfaceVariant, "Not checked in today")
    }
    val detail = when {
        day == null -> child.classroom?.let { "$it classroom" } ?: "No classroom yet"
        day.checkedOutAt == null -> "Arrived ${clock.time(day.checkedInAt)} · ${child.classroom.orEmpty()}"
        else -> "Arrived ${clock.time(day.checkedInAt)} · Left ${clock.time(day.checkedOutAt)}"
    }
    ListItem(
        leadingContent = { Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(32.dp)) },
        headlineContent = { Text(headline, style = MaterialTheme.typography.titleMedium) },
        supportingContent = { Text(detail) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.semantics(mergeDescendants = true) {},
    )
}

@Composable
private fun AttendanceRow(day: AttendanceDay, clock: CenterClock, isToday: Boolean) {
    val range = "${clock.time(day.checkedInAt)} – ${day.checkedOutAt?.let(clock::time) ?: "now"}"
    val label = if (isToday) "Today" else day.on.shortLabel
    ListItem(
        headlineContent = { Text(label) },
        trailingContent = { Text(range, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "$label, $range" },
    )
}
