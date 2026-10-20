package dev.kvadou.cubby.ui

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.kvadou.cubby.Session
import dev.kvadou.cubby.api.Invoice
import kotlinx.coroutines.launch

/** Tuition invoices: what's due first, then what's paid. Payment happens with the center for now. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BillingScreen(session: Session, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val invoices = rememberLoader(session) { it.invoices() }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = { TopAppBar(title = { Text("Billing") }) },
    ) { padding ->
        LoadingContent(invoices, Modifier.padding(padding)) { all ->
            PullToRefreshBox(
                isRefreshing = invoices.refreshing,
                onRefresh = { scope.launch { invoices.load() } },
                modifier = Modifier.fillMaxSize().padding(padding),
            ) {
                if (all.isEmpty()) {
                    EmptyState(Icons.Outlined.Description, "No invoices", "Tuition invoices will show up here.")
                } else {
                    InvoiceList(all)
                }
            }
        }
    }
}

@Composable
private fun InvoiceList(all: List<Invoice>) {
    val open = all.filter { it.isOpen }
    val paid = all.filterNot { it.isOpen }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        if (open.isNotEmpty()) {
            section(
                key = "due",
                title = "Due",
                rows = open,
                footer = "Total due: ${dollars(open.sumOf { it.amountCents })}. Questions about a bill? Ask the front desk.",
            ) { InvoiceRow(it) }
        }
        if (paid.isNotEmpty()) {
            section(key = "paid", title = "Paid", rows = paid) { InvoiceRow(it) }
        }
    }
}

@Composable
private fun InvoiceRow(invoice: Invoice) {
    val status = when {
        invoice.isPastDue -> "Past due · ${invoice.daysPastDue} ${if (invoice.daysPastDue == 1) "day" else "days"} late"
        invoice.isOpen -> "Due ${invoice.dueOn.mediumLabel}"
        else -> "Paid · ${invoice.number}"
    }
    ListItem(
        headlineContent = { Text("${invoice.periodStart.monthName} tuition") },
        supportingContent = {
            Text(status, color = if (invoice.isPastDue) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
        },
        trailingContent = {
            Text(
                dollars(invoice.amountCents),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (invoice.isOpen) FontWeight.SemiBold else FontWeight.Normal,
                color = MaterialTheme.colorScheme.onSurface,
            )
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.semantics(mergeDescendants = true) {},
    )
}
