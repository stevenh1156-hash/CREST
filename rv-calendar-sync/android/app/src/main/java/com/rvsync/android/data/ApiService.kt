package com.rvsync.android.data

import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface ApiService {

    @GET("api/properties")
    suspend fun listProperties(): List<Property>

    @POST("api/properties")
    suspend fun createProperty(@Query("name") name: String): Property

    @GET("api/properties/{propertyId}/sources")
    suspend fun listSources(@Path("propertyId") propertyId: String): List<Source>

    @POST("api/properties/{propertyId}/sources")
    suspend fun createSource(
        @Path("propertyId") propertyId: String,
        @Query("platform") platform: String,
        @Query("name") name: String,
        @Query("ical_read_url") icalReadUrl: String? = null,
        @Body apiCredentials: Map<String, String> = emptyMap(),
    ): Source

    @GET("api/properties/{propertyId}/sources/{sourceId}/feed-url")
    suspend fun getFeedUrl(
        @Path("propertyId") propertyId: String,
        @Path("sourceId") sourceId: String,
    ): FeedUrlResponse

    @GET("api/properties/{propertyId}/bookings")
    suspend fun listBookings(
        @Path("propertyId") propertyId: String,
        @Query("include_cancelled") includeCancelled: Boolean = false,
    ): List<Booking>

    @POST("api/properties/{propertyId}/bookings")
    suspend fun createBooking(
        @Path("propertyId") propertyId: String,
        @Body payload: BookingCreate,
    ): Booking

    @DELETE("api/bookings/{bookingId}")
    suspend fun deleteBooking(@Path("bookingId") bookingId: String)

    @POST("api/sync")
    suspend fun syncAll(@Query("property_id") propertyId: String? = null): List<SyncResult>

    @POST("api/sources/{sourceId}/sync")
    suspend fun syncSource(@Path("sourceId") sourceId: String): SyncResult
}
