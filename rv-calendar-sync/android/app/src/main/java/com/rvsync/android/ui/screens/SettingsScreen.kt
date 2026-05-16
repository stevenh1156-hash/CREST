package com.rvsync.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.rvsync.android.RvSyncApp
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onSaved: () -> Unit) {
    val app = LocalContext.current.applicationContext as RvSyncApp
    val current by app.settings.settings.collectAsState(initial = null)
    val scope = rememberCoroutineScope()

    var baseUrl by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    var seeded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(current) {
        if (!seeded && current != null) {
            baseUrl = current!!.baseUrl
            token = current!!.adminToken
            seeded = true
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Server settings") }) },
    ) { padding: PaddingValues ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(16.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Configure your rv-calendar-sync server. The Android emulator should " +
                    "use http://10.0.2.2:<port> to reach a server running on the host machine.",
            )
            OutlinedTextField(
                value = baseUrl,
                onValueChange = { baseUrl = it; error = null },
                label = { Text("Server URL") },
                placeholder = { Text("http://10.0.2.2:8000") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = token,
                onValueChange = { token = it; error = null },
                label = { Text("Admin token") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            error?.let { Text(it) }
            Button(
                onClick = {
                    if (baseUrl.isBlank() || token.isBlank()) {
                        error = "Both fields are required"
                        return@Button
                    }
                    scope.launch {
                        app.settings.update(baseUrl, token)
                        onSaved()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Save")
            }
        }
    }
}
