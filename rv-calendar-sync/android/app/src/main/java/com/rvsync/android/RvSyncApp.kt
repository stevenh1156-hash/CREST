package com.rvsync.android

import android.app.Application
import com.rvsync.android.data.ApiClient
import com.rvsync.android.data.SettingsRepository

class RvSyncApp : Application() {
    lateinit var settings: SettingsRepository
        private set
    lateinit var apiClient: ApiClient
        private set

    override fun onCreate() {
        super.onCreate()
        settings = SettingsRepository(this)
        apiClient = ApiClient(settings)
    }
}
