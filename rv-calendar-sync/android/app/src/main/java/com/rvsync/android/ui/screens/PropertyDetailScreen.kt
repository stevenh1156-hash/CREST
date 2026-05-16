package com.rvsync.android.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rvsync.android.RvSyncApp
import com.rvsync.android.data.Booking
import com.rvsync.android.data.Property
import com.rvsync.android.data.Source
import com.rvsync.android.data.SyncResult
import com.rvsync.android.ui.platformColor
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PropertyDetailScreen(
    propertyId: String,
    onBack: () -> Unit,
    onAddBooking: () -> Unit,
    onAddSource: () -> Unit,
) {
    val app = LocalContext.current.applicationContext as RvSyncApp
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    var property by remember { mutableStateOf<Property?>(null) }
    var bookings by remember { mutableStateOf<List<Booking>?>(null) }
    var sources by remember { mutableStateOf<List<Source>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var syncing by remember { mutableStateOf(false) }
    var lastSync by remember { mutableStateOf<List<SyncResult>?>(null) }
    var tab by remember { mutableStateOf(0) }
    var feedUrl by remember { mutableStateOf<Pair<Source, String>?>(null) }

    suspend fun reload() {
        error = null
        try {
            val svc = app.apiClient.service()
            property = svc.listProperties().firstOrNull { it.id == propertyId }
            bookings = svc.listBookings(propertyId)
            sources = svc.listSources(propertyId)
        } catch (t: Throwable) {
            error = t.message ?: t.toString()
        }
    }

    LaunchedEffect(Unit) { reload() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(property?.name ?: "Loading...") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        enabled = !syncing,
                        onClick = {
                            scope.launch {
                                syncing = true
                                try {
                                    lastSync = app.apiClient.service().syncAll(propertyId)
                                    reload()
                                } catch (t: Throwable) {
                                    error = t.message ?: t.toString()
                                } finally {
                                    syncing = false
                                }
                            }
                        },
                    ) {
                        if (syncing) CircularProgressIndicator(Modifier.size(20.dp))
                        else Icon(Icons.Default.Sync, contentDescription = "Sync now")
                    }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = if (tab == 0) onAddBooking else onAddSource,
                text = { Text(if (tab == 0) "Block dates" else "Add source") },
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
            )
        },
    ) { padding: PaddingValues ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            TabRow(selectedTabIndex = tab) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Bookings") })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Sources") })
            }
            error?.let {
                Text(
                    "Error: $it",
                    modifier = Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.error,
                )
            }
            lastSync?.let { syncResultsBanner(it) }
            when (tab) {
                0 -> BookingsList(
                    bookings = bookings,
                    onDelete = { id ->
                        scope.launch {
                            try {
                                app.apiClient.service().deleteBooking(id)
                                reload()
                            } catch (t: Throwable) {
                                error = t.message ?: t.toString()
                            }
                        }
                    },
                )
                1 -> SourcesList(
                    sources = sources,
                    onShowFeed = { src ->
                        scope.launch {
                            try {
                                val r = app.apiClient.service().getFeedUrl(propertyId, src.id)
                                feedUrl = src to r.url
                            } catch (t: Throwable) {
                                error = t.message ?: t.toString()
                            }
                        }
                    },
                    onSyncOne = { src ->
                        scope.launch {
                            syncing = true
                            try {
                                lastSync = listOf(app.apiClient.service().syncSource(src.id))
                                reload()
                            } catch (t: Throwable) {
                                error = t.message ?: t.toString()
                            } finally {
                                syncing = false
                            }
                        }
                    },
                )
            }
        }
    }

    feedUrl?.let { (src, url) ->
        AlertDialog(
            onDismissRequest = { feedUrl = null },
            title = { Text("Feed URL for ${src.platform.label}") },
            text = {
                Column {
                    Text(
                        "Paste this URL into ${src.platform.label}'s 'Import calendar' field. " +
                            "It contains bookings from every OTHER source so this platform can " +
                            "block the dates.",
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        url,
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Medium,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("feed url", url))
                    Toast.makeText(ctx, "Copied", Toast.LENGTH_SHORT).show()
                    feedUrl = null
                }) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Copy")
                }
            },
            dismissButton = {
                TextButton(onClick = { feedUrl = null }) { Text("Close") }
            },
        )
    }
}

@Composable
private fun BookingsList(bookings: List<Booking>?, onDelete: (String) -> Unit) {
    if (bookings == null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }
    if (bookings.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("No active bookings.")
        }
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(bookings, key = { it.id }) { b ->
            ElevatedCard {
                Row(
                    modifier = Modifier.padding(12.dp).fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .clip(CircleShape)
                            .background(platformColor(b.source)),
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("${b.start}  →  ${b.end}", fontWeight = FontWeight.SemiBold)
                        Text(
                            "${b.source.label} · ${b.status.name.lowercase()}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        b.summary?.takeIf { it.isNotBlank() }?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    TextButton(onClick = { onDelete(b.id) }) { Text("Remove") }
                }
            }
        }
    }
}

@Composable
private fun SourcesList(
    sources: List<Source>?,
    onShowFeed: (Source) -> Unit,
    onSyncOne: (Source) -> Unit,
) {
    if (sources == null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }
    if (sources.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("No sources yet. Tap + to connect a platform.")
        }
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(sources, key = { it.id }) { s ->
            ElevatedCard {
                Column(modifier = Modifier.padding(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(12.dp)
                                .clip(CircleShape)
                                .background(platformColor(s.platform)),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(s.platform.label, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.weight(1f))
                        AssistChip(
                            onClick = {},
                            label = { Text(if (s.enabled) "enabled" else "disabled") },
                            colors = AssistChipDefaults.assistChipColors(),
                        )
                    }
                    Text(s.name, style = MaterialTheme.typography.bodySmall)
                    s.lastSyncedAt?.let {
                        Text("Last synced: $it", style = MaterialTheme.typography.bodySmall)
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { onShowFeed(s) }) { Text("Feed URL") }
                        TextButton(onClick = { onSyncOne(s) }) { Text("Sync now") }
                    }
                }
            }
        }
    }
}

@Composable
private fun syncResultsBanner(results: List<SyncResult>) {
    val totals = results.fold(Triple(0, 0, 0)) { acc, r ->
        Triple(acc.first + r.created, acc.second + r.updated, acc.third + r.cancelled)
    }
    val errors = results.flatMap { it.errors }
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(
            "Last sync: +${totals.first} new, ~${totals.second} updated, -${totals.third} cancelled",
            style = MaterialTheme.typography.bodySmall,
        )
        if (errors.isNotEmpty()) {
            Text(
                "Errors: ${errors.size}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        HorizontalDivider(modifier = Modifier.padding(top = 8.dp))
    }
}
