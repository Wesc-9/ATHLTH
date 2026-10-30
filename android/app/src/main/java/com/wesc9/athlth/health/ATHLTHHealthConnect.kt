package com.wesc9.athlth.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

enum class ConnectAvailability { AVAILABLE, NEEDS_PROVIDER, UNAVAILABLE }

data class HealthOverview(
    val stepsToday: Long? = null,
    val workoutsLastSevenDays: Int? = null,
    val latestHeartRateBpm: Long? = null,
    val sleepMinutesLastNight: Long? = null
)

/** Health Connect is an on-device, user-controlled data exchange, not a sensor. */
class ATHLTHHealthConnect(private val context: Context) {
    companion object {
        const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"
        val basicPermissions: Set<String> = setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getReadPermission(ExerciseSessionRecord::class)
        )
        val optionalPermissions: Set<String> = setOf(
            HealthPermission.getReadPermission(HeartRateRecord::class),
            HealthPermission.getReadPermission(SleepSessionRecord::class)
        )
        val permissionContract get() =
            PermissionController.createRequestPermissionResultContract()
    }

    fun availability(): ConnectAvailability =
        when (HealthConnectClient.getSdkStatus(context, PROVIDER_PACKAGE)) {
            HealthConnectClient.SDK_AVAILABLE -> ConnectAvailability.AVAILABLE
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                ConnectAvailability.NEEDS_PROVIDER
            else -> ConnectAvailability.UNAVAILABLE
        }

    private fun client(): HealthConnectClient {
        check(availability() == ConnectAvailability.AVAILABLE) {
            "Health Connect is not available on this device"
        }
        return HealthConnectClient.getOrCreate(context)
    }

    suspend fun grantedPermissions(): Set<String> =
        if (availability() == ConnectAvailability.AVAILABLE) {
            client().permissionController.getGrantedPermissions()
        } else emptySet()

    suspend fun overview(): HealthOverview {
        val granted = grantedPermissions()
        if (granted.isEmpty()) return HealthOverview()
        val hc = client()
        val now = Instant.now()
        val startToday = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant()

        // Null means no permission or unavailable data; zero is a real aggregate result.
        val steps = if (granted.contains(HealthPermission.getReadPermission(StepsRecord::class))) {
            hc.aggregate(
                AggregateRequest(
                    metrics = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter = TimeRangeFilter.between(startToday, now)
                )
            )[StepsRecord.COUNT_TOTAL]
        } else null

        // Imported records are displayed only; ATHLTH does NOT automatically
        // store/re-upload them or create extra ATHLTH workouts.
        val sessions = if (granted.contains(HealthPermission.getReadPermission(ExerciseSessionRecord::class))) {
            hc.readRecords(
                ReadRecordsRequest(
                    recordType = ExerciseSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(now.minus(7, ChronoUnit.DAYS), now),
                    pageSize = 100
                )
            ).records.size
        } else null

        val heartRate = if (granted.contains(HealthPermission.getReadPermission(HeartRateRecord::class))) {
            hc.readRecords(
                ReadRecordsRequest(
                    recordType = HeartRateRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(now.minus(24, ChronoUnit.HOURS), now),
                    pageSize = 100
                )
            ).records.flatMap { it.samples }.maxByOrNull { it.time }?.beatsPerMinute
        } else null

        val sleep = if (granted.contains(HealthPermission.getReadPermission(SleepSessionRecord::class))) {
            hc.readRecords(
                ReadRecordsRequest(
                    recordType = SleepSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(now.minus(36, ChronoUnit.HOURS), now),
                    pageSize = 100
                )
            ).records.maxByOrNull { it.endTime }?.let {
                ChronoUnit.MINUTES.between(it.startTime, it.endTime)
            }
        } else null

        return HealthOverview(
            stepsToday = steps,
            workoutsLastSevenDays = sessions,
            latestHeartRateBpm = heartRate,
            sleepMinutesLastNight = sleep
        )
    }
}
