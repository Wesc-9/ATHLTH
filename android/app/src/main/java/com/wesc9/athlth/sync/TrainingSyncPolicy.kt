package com.wesc9.athlth.sync

data class LocalPlan(
    val id: String,
    val content: String,
    val lastSyncedRevision: Long?,
    val hasUnsyncedChanges: Boolean
)

data class RemotePlan(
    val id: String,
    val content: String,
    val revision: Long,
    val schemaVersion: Int,
    val deleted: Boolean
)

enum class SyncDecision { BLOCKED, NO_CHANGE, UPLOAD, DOWNLOAD, CONFLICT }

/**
 * Only user-authored plans and workout templates can be synchronized.
 * Never allow HealthKit or Health Connect sensor records into this transport.
 * No upload happens without explicit consent.
 */
object TrainingSyncPolicy {
    fun decide(consent: Boolean, local: LocalPlan?, remote: RemotePlan?): SyncDecision {
        if (!consent) return SyncDecision.BLOCKED
        if (remote != null && remote.schemaVersion != 1) return SyncDecision.BLOCKED
        if (local == null && remote == null) return SyncDecision.NO_CHANGE
        if (remote == null) {
            return if (local?.lastSyncedRevision != null) SyncDecision.CONFLICT
                else SyncDecision.UPLOAD
        }
        if (local == null) return SyncDecision.DOWNLOAD
        if (local.id != remote.id) return SyncDecision.CONFLICT
        if (remote.deleted) {
            return if (local.hasUnsyncedChanges) SyncDecision.CONFLICT
                else SyncDecision.DOWNLOAD
        }
        if (local.content == remote.content) return SyncDecision.NO_CHANGE
        if (!local.hasUnsyncedChanges) return SyncDecision.DOWNLOAD
        return if (local.lastSyncedRevision == remote.revision) SyncDecision.UPLOAD
            else SyncDecision.CONFLICT
    }
}
