package com.wesc9.athlth.catalog

import com.wesc9.athlth.auth.ATHLTHAuth
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ATHLTHProfile(
    val id: String,
    val username: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarURL: String? = null
)

@Serializable
data class TrainingPlanCatalogItem(
    val id: String,
    val slug: String,
    val title: String,
    val summary: String = "",
    val category: String,
    val goal: String = "",
    val level: String = "",
    @SerialName("duration_weeks") val durationWeeks: Int,
    @SerialName("sessions_per_week") val sessionsPerWeek: Int
)

@Serializable
data class WorkoutTemplateCatalogItem(
    val id: String,
    val slug: String,
    val title: String,
    val summary: String = "",
    val category: String,
    val difficulty: String = "",
    @SerialName("estimated_duration_minutes") val estimatedDurationMinutes: Int? = null
)

@Serializable
data class TrainingBackupConsent(
    @SerialName("user_id") val userId: String,
    val enabled: Boolean = false,
    @SerialName("policy_version") val policyVersion: Int = 1
)

class ATHLTHCatalogRepository {
    private val db get() = ATHLTHAuth.client

    suspend fun myProfile(): ATHLTHProfile? {
        val userId = ATHLTHAuth.userId() ?: return null
        return db.from("profiles").select {
            filter { eq("id", userId) }
        }.decodeList<ATHLTHProfile>().firstOrNull()
    }

    suspend fun trainingPlans(): List<TrainingPlanCatalogItem> {
        check(ATHLTHAuth.userId() != null) { "Requires ATHLTH sign-in" }
        return db.from("training_plan_catalog").select {
            filter { eq("is_published", true) }
        }.decodeList<TrainingPlanCatalogItem>()
    }

    suspend fun workoutTemplates(): List<WorkoutTemplateCatalogItem> {
        check(ATHLTHAuth.userId() != null) { "Requires ATHLTH sign-in" }
        return db.from("workout_template_catalog").select {
            filter { eq("is_published", true) }
        }.decodeList<WorkoutTemplateCatalogItem>()
    }

    /** Existing iOS cloud backup opt-in is independent from two-way sync. */
    suspend fun backupConsent(): TrainingBackupConsent? {
        val userId = ATHLTHAuth.userId() ?: return null
        return db.from("training_backup_consent").select {
            filter { eq("user_id", userId) }
        }.decodeList<TrainingBackupConsent>().firstOrNull()
    }
}
