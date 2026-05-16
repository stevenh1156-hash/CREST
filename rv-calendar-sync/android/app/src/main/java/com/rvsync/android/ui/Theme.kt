package com.rvsync.android.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.rvsync.android.data.Platform

private val LightColors = lightColorScheme(
    primary = Color(0xFF2E7D32),
    secondary = Color(0xFF6F9F71),
)
private val DarkColors = darkColorScheme(
    primary = Color(0xFF7CC07F),
    secondary = Color(0xFF9DBFA0),
)

@Composable
fun RvSyncTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val ctx = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }
    MaterialTheme(colorScheme = colors, content = content)
}

fun platformColor(platform: Platform): Color = when (platform) {
    Platform.BOOKING -> Color(0xFF003580)     // booking.com blue
    Platform.RVSHARE -> Color(0xFFFF6A39)     // rvshare orange
    Platform.OUTDOORSY -> Color(0xFF2E7D32)   // outdoorsy green
    Platform.WIX_HOTELS -> Color(0xFF0A6ED1)  // wix-ish blue
    Platform.MANUAL -> Color(0xFF6750A4)      // purple
}
