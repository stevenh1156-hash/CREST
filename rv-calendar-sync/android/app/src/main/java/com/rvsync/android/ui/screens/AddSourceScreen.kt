package com.rvsync.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.rvsync.android.RvSyncApp
import com.rvsync.android.data.Platform
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddSourceScreen(propertyId: String, onBack: () -> Unit) {
    val app = LocalContext.current.applicationContext as RvSyncApp
    val scope = rememberCoroutineScope()

    val platforms = listOf(
        Platform.BOOKING,
        Platform.RVSHARE,
        Platform.OUTDOORSY,
        Platform.WIX_HOTELS,
    )
    var platform by remember { mutableStateOf(Platform.RVSHARE) }
    var platformOpen by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var icalUrl by remember { mutableStateOf("") }
    var wixRoomTypeId by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var submitting by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Connect a platform") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding: PaddingValues ->
        Column(
            modifier = Modifier.padding(padding).padding(16.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ExposedDropdownMenuBox(
                expanded = platformOpen,
                onExpandedChange = { platformOpen = it },
            ) {
                OutlinedTextField(
                    value = platform.label,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Platform") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(platformOpen) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                androidx.compose.material3.DropdownMenu(
                    expanded = platformOpen,
                    onDismissRequest = { platformOpen = false },
                ) {
                    platforms.forEach { p ->
                        DropdownMenuItem(
                            text = { Text(p.label) },
                            onClick = { platform = p; platformOpen = false },
                        )
                    }
                }
            }

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Connection name") },
                placeholder = { Text("e.g. \"RVshare main listing\"") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            when (platform) {
                Platform.WIX_HOTELS -> {
                    OutlinedTextField(
                        value = wixRoomTypeId,
                        onValueChange = { wixRoomTypeId = it },
                        label = { Text("Wix room type id") },
                        placeholder = { Text("e.g. rt_abc123") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = icalUrl,
                        onValueChange = { icalUrl = it },
                        label = { Text("iCal export URL (fallback, optional)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                else -> {
                    OutlinedTextField(
                        value = icalUrl,
                        onValueChange = { icalUrl = it },
                        label = { Text("iCal export URL") },
                        placeholder = { Text("From the platform's calendar settings") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            Text(
                helperText(platform),
                style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
            )

            error?.let { Text(it) }

            Button(
                enabled = !submitting,
                onClick = {
                    if (name.isBlank()) { error = "Name required"; return@Button }
                    if (platform != Platform.WIX_HOTELS && icalUrl.isBlank()) {
                        error = "iCal URL required for ${platform.label}"
                        return@Button
                    }
                    submitting = true
                    error = null
                    scope.launch {
                        try {
                            val creds = if (platform == Platform.WIX_HOTELS && wixRoomTypeId.isNotBlank()) {
                                mapOf("room_type_id" to wixRoomTypeId)
                            } else emptyMap()
                            app.apiClient.service().createSource(
                                propertyId = propertyId,
                                platform = platform.apiValue,
                                name = name,
                                icalReadUrl = icalUrl.ifBlank { null },
                                apiCredentials = creds,
                            )
                            onBack()
                        } catch (t: Throwable) {
                            error = t.message ?: t.toString()
                        } finally {
                            submitting = false
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Connect") }
        }
    }
}

private fun helperText(p: Platform): String = when (p) {
    Platform.BOOKING ->
        "Booking.com Extranet → Property → Calendar & Pricing → Sync calendars → Export calendar."
    Platform.RVSHARE ->
        "Owner dashboard → Listings → Calendar → Sync external calendars → Export."
    Platform.OUTDOORSY ->
        "Dashboard → RV → Calendar → Sync → Export."
    Platform.WIX_HOTELS ->
        "Set WIX_API_KEY/SITE_ID/ACCOUNT_ID on the server. Room type id is the Wix Hotels identifier for this RV."
    Platform.MANUAL -> ""
}
