package com.rvsync.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
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
import com.rvsync.android.data.BookingCreate
import com.rvsync.android.data.BookingStatus
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddBookingScreen(propertyId: String, onBack: () -> Unit) {
    val app = LocalContext.current.applicationContext as RvSyncApp
    val scope = rememberCoroutineScope()

    var startDate by remember { mutableStateOf<LocalDate?>(null) }
    var endDate by remember { mutableStateOf<LocalDate?>(null) }
    var showStartPicker by remember { mutableStateOf(false) }
    var showEndPicker by remember { mutableStateOf(false) }
    var summary by remember { mutableStateOf("") }
    var guestName by remember { mutableStateOf("") }
    var status by remember { mutableStateOf(BookingStatus.BLOCKED) }
    var statusOpen by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var submitting by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New manual booking") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding: PaddingValues ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(16.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Manual entries block dates across every connected platform via the hosted iCal feeds.",
            )

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = { showStartPicker = true },
                    modifier = Modifier.weight(1f),
                ) {
                    Text(startDate?.toString() ?: "Start date")
                }
                OutlinedButton(
                    onClick = { showEndPicker = true },
                    modifier = Modifier.weight(1f),
                ) {
                    Text(endDate?.toString() ?: "End date (excl.)")
                }
            }

            ExposedDropdownMenuBox(expanded = statusOpen, onExpandedChange = { statusOpen = it }) {
                OutlinedTextField(
                    value = status.name.lowercase(),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Status") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(statusOpen) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                DropdownMenu(expanded = statusOpen, onDismissRequest = { statusOpen = false }) {
                    listOf(
                        BookingStatus.BLOCKED,
                        BookingStatus.CONFIRMED,
                        BookingStatus.TENTATIVE,
                    ).forEach { s ->
                        DropdownMenuItem(
                            text = { Text(s.name.lowercase()) },
                            onClick = { status = s; statusOpen = false },
                        )
                    }
                }
            }

            OutlinedTextField(
                value = summary,
                onValueChange = { summary = it },
                label = { Text("Summary (e.g. \"Owner trip\")") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = guestName,
                onValueChange = { guestName = it },
                label = { Text("Guest name (optional)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            error?.let { Text(it) }

            Button(
                enabled = !submitting,
                onClick = {
                    val s = startDate
                    val e = endDate
                    if (s == null || e == null) {
                        error = "Pick start and end dates"
                        return@Button
                    }
                    if (!e.isAfter(s)) {
                        error = "End date must be after start date"
                        return@Button
                    }
                    error = null
                    submitting = true
                    scope.launch {
                        try {
                            app.apiClient.service().createBooking(
                                propertyId = propertyId,
                                payload = BookingCreate(
                                    propertyId = propertyId,
                                    start = s.toString(),
                                    end = e.toString(),
                                    status = status,
                                    summary = summary.ifBlank { null },
                                    guestName = guestName.ifBlank { null },
                                ),
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
            ) {
                Text("Save")
            }
        }
    }

    if (showStartPicker) {
        DatePickerSheet(
            initial = startDate,
            onDismiss = { showStartPicker = false },
            onPick = { startDate = it; showStartPicker = false },
        )
    }
    if (showEndPicker) {
        DatePickerSheet(
            initial = endDate ?: startDate?.plusDays(1),
            onDismiss = { showEndPicker = false },
            onPick = { endDate = it; showEndPicker = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DatePickerSheet(
    initial: LocalDate?,
    onDismiss: () -> Unit,
    onPick: (LocalDate) -> Unit,
) {
    val state = rememberDatePickerState(
        initialSelectedDateMillis = initial
            ?.atStartOfDay(ZoneOffset.UTC)
            ?.toInstant()
            ?.toEpochMilli(),
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val ms = state.selectedDateMillis
                if (ms != null) {
                    val d = Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).toLocalDate()
                    onPick(d)
                } else onDismiss()
            }) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    ) {
        DatePicker(state = state)
    }
}
