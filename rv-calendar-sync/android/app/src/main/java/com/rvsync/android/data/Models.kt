package com.rvsync.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class Platform {
    @SerialName("booking") BOOKING,
    @SerialName("rvshare") RVSHARE,
    @SerialName("outdoorsy") OUTDOORSY,
    @SerialName("wix_hotels") WIX_HOTELS,
    @SerialName("manual") MANUAL;

    val label: String
        get() = when (this) {
            BOOKING -> "Booking.com"
            RVSHARE -> "RVshare"
            OUTDOORSY -> "Outdoorsy"
            WIX_HOTELS -> "Wix Hotels"
            MANUAL -> "Manual"
        }

    val apiValue: String
        get() = when (this) {
            BOOKING -> "booking"
            RVSHARE -> "rvshare"
            OUTDOORSY -> "outdoorsy"
            WIX_HOTELS -> "wix_hotels"
            MANUAL -> "manual"
        }
}

@Serializable
enum class BookingStatus {
    @SerialName("confirmed") CONFIRMED,
    @SerialName("tentative") TENTATIVE,
    @SerialName("cancelled") CANCELLED,
    @SerialName("blocked") BLOCKED;

    val apiValue: String
        get() = when (this) {
            CONFIRMED -> "confirmed"
            TENTATIVE -> "tentative"
            CANCELLED -> "cancelled"
            BLOCKED -> "blocked"
        }
}

@Serializable
data class Property(
    val id: String,
    val name: String,
    @SerialName("created_at") val createdAt: String,
)

@Serializable
data class Source(
    val id: String,
    @SerialName("property_id") val propertyId: String,
    val platform: Platform,
    val name: String,
    @SerialName("ical_read_url") val icalReadUrl: String? = null,
    @SerialName("ical_feed_token") val icalFeedToken: String,
    @SerialName("api_credentials") val apiCredentials: Map<String, String> = emptyMap(),
    @SerialName("last_synced_at") val lastSyncedAt: String? = null,
    @SerialName("last_pushed_at") val lastPushedAt: String? = null,
    val enabled: Boolean = true,
)

@Serializable
data class Booking(
    val id: String,
    @SerialName("property_id") val propertyId: String,
    val source: Platform,
    @SerialName("source_uid") val sourceUid: String,
    val start: String,
    val end: String,
    val status: BookingStatus,
    val summary: String? = null,
    @SerialName("guest_name") val guestName: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class BookingCreate(
    @SerialName("property_id") val propertyId: String,
    val start: String,
    val end: String,
    val status: BookingStatus = BookingStatus.BLOCKED,
    val summary: String? = null,
    @SerialName("guest_name") val guestName: String? = null,
)

@Serializable
data class SyncResult(
    @SerialName("source_id") val sourceId: String,
    val platform: Platform,
    val fetched: Int = 0,
    val created: Int = 0,
    val updated: Int = 0,
    val cancelled: Int = 0,
    val pushed: Int = 0,
    val errors: List<String> = emptyList(),
)

@Serializable
data class FeedUrlResponse(
    val url: String,
    val instructions: String,
)
