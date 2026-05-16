package com.rvsync.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.rvsync.android.RvSyncApp
import com.rvsync.android.ui.screens.AddBookingScreen
import com.rvsync.android.ui.screens.AddSourceScreen
import com.rvsync.android.ui.screens.PropertiesScreen
import com.rvsync.android.ui.screens.PropertyDetailScreen
import com.rvsync.android.ui.screens.SettingsScreen

object Routes {
    const val PROPERTIES = "properties"
    const val PROPERTY_DETAIL = "property/{propertyId}"
    const val ADD_BOOKING = "property/{propertyId}/add-booking"
    const val ADD_SOURCE = "property/{propertyId}/add-source"
    const val SETTINGS = "settings"

    fun propertyDetail(id: String) = "property/$id"
    fun addBooking(id: String) = "property/$id/add-booking"
    fun addSource(id: String) = "property/$id/add-source"
}

@Composable
fun AppNav(nav: NavHostController) {
    val app = LocalContext.current.applicationContext as RvSyncApp
    val settings by app.settings.settings.collectAsState(initial = null)

    // Wait for the first DataStore emission before mounting NavHost, since
    // startDestination is captured once at composition time.
    val loaded = settings ?: run {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }
    val startDest = if (loaded.isConfigured) Routes.PROPERTIES else Routes.SETTINGS

    NavHost(navController = nav, startDestination = startDest) {
        composable(Routes.SETTINGS) {
            SettingsScreen(
                onSaved = {
                    nav.navigate(Routes.PROPERTIES) {
                        popUpTo(Routes.SETTINGS) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.PROPERTIES) {
            PropertiesScreen(
                onProperty = { id -> nav.navigate(Routes.propertyDetail(id)) },
                onSettings = { nav.navigate(Routes.SETTINGS) },
            )
        }
        composable(Routes.PROPERTY_DETAIL) { entry ->
            val id = entry.arguments?.getString("propertyId") ?: return@composable
            PropertyDetailScreen(
                propertyId = id,
                onBack = { nav.popBackStack() },
                onAddBooking = { nav.navigate(Routes.addBooking(id)) },
                onAddSource = { nav.navigate(Routes.addSource(id)) },
            )
        }
        composable(Routes.ADD_BOOKING) { entry ->
            val id = entry.arguments?.getString("propertyId") ?: return@composable
            AddBookingScreen(propertyId = id, onBack = { nav.popBackStack() })
        }
        composable(Routes.ADD_SOURCE) { entry ->
            val id = entry.arguments?.getString("propertyId") ?: return@composable
            AddSourceScreen(propertyId = id, onBack = { nav.popBackStack() })
        }
    }
}
