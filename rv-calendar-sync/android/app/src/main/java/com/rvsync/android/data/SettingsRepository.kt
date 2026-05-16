package com.rvsync.android.data

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "rv_sync_settings")

data class Settings(
    val baseUrl: String,
    val adminToken: String,
) {
    val isConfigured: Boolean get() = baseUrl.isNotBlank() && adminToken.isNotBlank()
}

class SettingsRepository(private val context: Context) {

    private val baseUrlKey = stringPreferencesKey("base_url")
    private val tokenKey = stringPreferencesKey("admin_token")

    val settings: Flow<Settings> = context.dataStore.data.map { prefs ->
        Settings(
            baseUrl = prefs[baseUrlKey].orEmpty().trim().trimEnd('/'),
            adminToken = prefs[tokenKey].orEmpty(),
        )
    }

    suspend fun update(baseUrl: String, adminToken: String) {
        context.dataStore.edit { prefs: Preferences.MutablePreferences ->
            prefs[baseUrlKey] = baseUrl.trim().trimEnd('/')
            prefs[tokenKey] = adminToken
        }
    }

    suspend fun current(): Settings = settings.first()
}
