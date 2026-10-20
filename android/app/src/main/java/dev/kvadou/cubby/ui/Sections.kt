package dev.kvadou.cubby.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** A titled group of rows on a card, the Material counterpart of an inset-grouped List section. */
fun <T> LazyListScope.section(
    key: String,
    title: String?,
    rows: List<T>,
    footer: String? = null,
    row: @Composable (T) -> Unit,
) {
    if (title != null) {
        item(key = "$key-title") {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 28.dp, end = 28.dp, top = 20.dp, bottom = 8.dp).semantics { heading() },
            )
        }
    }
    item(key = "$key-rows") {
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
            modifier = Modifier.padding(horizontal = 16.dp),
        ) {
            Column {
                rows.forEachIndexed { index, item ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
                    row(item)
                }
            }
        }
    }
    if (footer != null) {
        item(key = "$key-footer") {
            Text(
                footer,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 28.dp, end = 28.dp, top = 8.dp),
            )
        }
    }
}
