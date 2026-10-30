package com.wesc9.athlth.contract

import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WorkoutPrescriptionTest {
    private val json = Json { ignoreUnknownKeys = false }

    @Test fun preservesIdentityAndIntervals() {
        val plan = WorkoutPrescription(
            sessionId = "ddcf9c2a-9090-4c48-b492-125aaa123456",
            name = "4 x 4",
            blocks = listOf(
                WorkoutBlock(id = "w", type = BlockType.RUN, phase = WorkoutPhase.WARMUP, durationSeconds = 600),
                WorkoutBlock(id = "1", type = BlockType.RUN, phase = WorkoutPhase.MAIN, durationSeconds = 240, targetHeartRateZone = 4),
                WorkoutBlock(id = "r", type = BlockType.REST, phase = WorkoutPhase.RECOVERY, durationSeconds = 120)
            )
        )
        assertEquals(plan, json.decodeFromString<WorkoutPrescription>(json.encodeToString(plan)))
    }

    @Test fun rejectsUnsupportedSchema() {
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutPrescription(schemaVersion = 2, sessionId = "stable-id", name = "Unknown", blocks = emptyList())
        }
    }

    @Test fun neverMixesMeasuredAndEstimated() {
        val measured = WorkoutMeasurement("a", "distance", 1000.0, "m",
            MeasurementOrigin.MEASURED, "com.example.tracker", "2026-10-30T10:00:00Z")
        val estimated = measured.copy(origin = MeasurementOrigin.ESTIMATED, sourcePackage = null)
        assertEquals(MeasurementOrigin.MEASURED, measured.origin)
        assertEquals(MeasurementOrigin.ESTIMATED, estimated.origin)
    }
}
