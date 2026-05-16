# rv-sync-android

Android front end for [rv-calendar-sync](../README.md). Connects to the FastAPI backend over HTTP, lets you manage RVs / platform connections / bookings, and triggers sync.

## Stack

- Kotlin 2.1, Jetpack Compose (Material 3)
- Single Activity + Navigation Compose
- Retrofit 2 + kotlinx.serialization
- DataStore Preferences for server URL + admin token
- minSdk 26 (Android 8.0), targetSdk 35

## Screens

1. **Settings** — server base URL and admin bearer token (stored in DataStore, excluded from Auto Backup).
2. **Properties (RVs)** — list and create.
3. **Property detail** — two tabs:
   - **Bookings** — chronological list, color-coded by source platform, manual entries deletable. Manual deletion → hard delete. External booking deletion → CANCELLED status (so the cancellation propagates via the next iCal feed read).
   - **Sources** — list connected platforms, per-source "Sync now" and a "Feed URL" dialog with copy-to-clipboard.
   - **Sync toolbar button** triggers a property-wide sync and shows a summary banner.
3. **Add booking** — date pickers for start/end, status (blocked/confirmed/tentative), summary, guest name. Saves to the `MANUAL` source.
4. **Add source** — pick a platform (Booking.com / RVshare / Outdoorsy / Wix Hotels), enter a name and iCal export URL. Wix Hotels gets a dedicated `room_type_id` field for direct REST API push.

## Build

This project requires the Android SDK. The two supported paths:

### Option A — Android Studio (recommended)

1. Install Android Studio (Iguana or later).
2. **File → Open** the `rv-calendar-sync/android/` folder.
3. Studio will install the matching Gradle wrapper, Android SDK, and dependencies.
4. Run on an emulator or device.

### Option B — Command line

Requires `ANDROID_HOME` set and the matching SDK platform + build tools installed.

```bash
cd rv-calendar-sync/android
gradle wrapper                  # generates ./gradlew (one-time)
./gradlew :app:assembleDebug    # APK at app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:installDebug     # install on a connected device
```

## Pointing the app at your server

The backend's default port is `8000`. After installing the app, the Settings screen accepts a base URL. Common values:

| Where the backend runs       | What to enter in the app                    |
|-------------------------------|---------------------------------------------|
| Android emulator → host       | `http://10.0.2.2:8000`                      |
| Physical phone on same WiFi   | `http://<host-lan-ip>:8000`                 |
| Remote / tunneled (ngrok etc) | `https://<your-tunnel>.ngrok-free.app`      |

The admin token is the `RV_SYNC_ADMIN_TOKEN` from the backend's `.env`.

> **Security note:** the app's `network_security_config.xml` permits cleartext HTTP because the user picks the host at runtime. For production deployment of the backend, terminate TLS in front of FastAPI (Caddy, nginx, Cloudflare Tunnel) and use the `https://` URL.

## Module layout

```
app/src/main/java/com/rvsync/android/
├── RvSyncApp.kt              # Application: holds SettingsRepository + ApiClient singletons
├── MainActivity.kt           # Compose host
├── data/
│   ├── Models.kt             # @Serializable mirrors of backend Pydantic models
│   ├── SettingsRepository.kt # DataStore Preferences wrapper
│   ├── ApiService.kt         # Retrofit interface
│   └── ApiClient.kt          # Per-call Retrofit builder (re-reads settings every call
│                             #   so URL/token changes apply immediately)
└── ui/
    ├── Theme.kt              # Material 3 + platform color mapping
    ├── AppNav.kt             # NavHost + routes
    └── screens/
        ├── SettingsScreen.kt
        ├── PropertiesScreen.kt
        ├── PropertyDetailScreen.kt
        ├── AddBookingScreen.kt
        └── AddSourceScreen.kt
```

## License

MIT.
