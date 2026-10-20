package dev.kvadou.cubby.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import dev.kvadou.cubby.Session
import dev.kvadou.cubby.api.FamilyMessage
import kotlinx.coroutines.launch

/** What the center sent: approved by a director in the web app, delivered here. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessagesScreen(session: Session, onUnread: (Int) -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val messages = rememberLoader(session) { it.messages() }
    var open by remember { mutableStateOf<FamilyMessage?>(null) }

    val list = (messages.state as? Loadable.Loaded)?.value
    LaunchedEffect(list) { list?.let { all -> onUnread(all.count { it.isUnread }) } }

    fun read(message: FamilyMessage) {
        open = message
        if (!message.isUnread || list == null) return
        scope.launch {
            val updated = runCatching { session.client.markRead(message.id) }.getOrNull() ?: return@launch
            messages.replace(list.map { if (it.id == updated.id) updated else it })
        }
    }

    val reading = open
    if (reading != null) {
        BackHandler { open = null }
        MessageDetail(reading, onBack = { open = null }, modifier = modifier)
    } else {
        MessageList(messages, onOpen = ::read, modifier = modifier)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MessageList(messages: Loader<List<FamilyMessage>>, onOpen: (FamilyMessage) -> Unit, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = { TopAppBar(title = { Text("Messages") }) },
    ) { padding ->
        LoadingContent(messages, Modifier.padding(padding)) { all ->
            PullToRefreshBox(
                isRefreshing = messages.refreshing,
                onRefresh = { scope.launch { messages.load() } },
                modifier = Modifier.fillMaxSize().padding(padding),
            ) {
                if (all.isEmpty()) {
                    EmptyState(Icons.Outlined.Inbox, "No messages yet", "Messages from your center will appear here.")
                } else {
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(all, key = { it.id }) { message ->
                            MessageRow(message, onClick = { onOpen(message) })
                            HorizontalDivider(Modifier.padding(start = 40.dp), color = MaterialTheme.colorScheme.outlineVariant)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MessageRow(message: FamilyMessage, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 14.dp)
            .semantics(mergeDescendants = true) { if (message.isUnread) stateDescription = "Unread" }
            .testTag("message-${message.id}"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier
                .padding(top = 6.dp)
                .size(10.dp)
                .clip(CircleShape)
                .background(if (message.isUnread) MaterialTheme.colorScheme.primary else Color.Transparent),
        )
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    message.subject,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = if (message.isUnread) FontWeight.SemiBold else FontWeight.Normal,
                    modifier = Modifier.weight(1f),
                )
                Text(relative(message.sentAt), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                message.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MessageDetail(message: FamilyMessage, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack, modifier = Modifier.testTag("back")) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back to messages")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(message.subject, style = MaterialTheme.typography.headlineSmall)
            Text(
                "From ${message.from} · ${CenterClock(java.time.ZoneId.systemDefault().id).dayAndTime(message.sentAt)}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SelectionContainer { Text(message.body, style = MaterialTheme.typography.bodyLarge) }
        }
    }
}
