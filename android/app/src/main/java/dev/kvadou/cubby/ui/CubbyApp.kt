package dev.kvadou.cubby.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import dev.kvadou.cubby.Session

@Composable
fun CubbyApp(session: Session) {
    if (session.signedIn) MainTabs(session) else SignInScreen(session)
}

private enum class Tab(val label: String, val selected: ImageVector, val unselected: ImageVector) {
    Today("Today", Icons.Filled.WbSunny, Icons.Outlined.WbSunny),
    Messages("Messages", Icons.Filled.ChatBubble, Icons.Outlined.ChatBubbleOutline),
    Billing("Billing", Icons.Filled.CreditCard, Icons.Outlined.CreditCard),
}

@Composable
private fun MainTabs(session: Session) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var unread by rememberSaveable { mutableIntStateOf(0) }

    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { entry ->
                    val selected = tab == entry.ordinal
                    NavigationBarItem(
                        selected = selected,
                        onClick = { tab = entry.ordinal },
                        label = { Text(entry.label) },
                        modifier = Modifier.testTag("tab-${entry.name}"),
                        icon = {
                            val icon = if (selected) entry.selected else entry.unselected
                            if (entry == Tab.Messages && unread > 0) {
                                BadgedBox(badge = {
                                    Badge(Modifier.semantics { contentDescription = "$unread unread" }) { Text("$unread") }
                                }) { Icon(icon, contentDescription = null) }
                            } else {
                                Icon(icon, contentDescription = null)
                            }
                        },
                    )
                }
            }
        },
    ) { padding ->
        // Each tab draws its own top bar under the status bar; only the navigation bar's height applies here.
        val content = Modifier.padding(bottom = padding.calculateBottomPadding())
        when (Tab.entries[tab]) {
            Tab.Today -> TodayScreen(session, onUnread = { unread = it }, modifier = content)
            Tab.Messages -> MessagesScreen(session, onUnread = { unread = it }, modifier = content)
            Tab.Billing -> BillingScreen(session, modifier = content)
        }
    }
}
