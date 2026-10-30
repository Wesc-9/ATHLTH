package com.wesc9.athlth.contract

import kotlinx.serialization.Serializable

/**
 * Draft cross-platform wire contract. This is NOT the existing Swift Codable
 * representation. Mapping/round-trip parity must be checked before sync.
 */
@Serializable
data class WorkoutPrescription(
    val schemaVersion: Int = 1,
    val sessionId: String,
    val name: String,
    val blocks: List<WorkoutBlock>
) {
    init {
        require(schemaVersion == 1) { "Unsupported workout schema version" }
        require(sessionId.isNotBlank()) { "Session ID must be stable" }
    }
}

@Serializable
data class WorkoutBlock(
    val id: String,
    val type: BlockType,
    val phase: WorkoutPhase,
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val targetPaceSecondsPerKm: Double? = null,
    val targetHeartRateZone: Int? = null,
    val exerciseId: String? = null,
    val reps: Int? = null,
    val weightKg: Double? = null,
    val restSeconds: Int? = null
)

@Serializable
enum class BlockType { RUN, STRENGTH, REST, INSTRUCTIONS }

@Serializable
enum class WorkoutPhase { WARMUP, MAIN, RECOVERY, COOLDOWN }

@Serializable
data class WorkoutMeasurement(
    val sessionId: String,
    val metric: String,
    val value: Double,
    val unit: String,
    val origin: MeasurementOrigin,
    val sourcePackage: String? = null,
    val recordedAt: String
)

@Serializable
enum class MeasurementOrigin { MEASURED, MANUAL, ESTIMATED }
