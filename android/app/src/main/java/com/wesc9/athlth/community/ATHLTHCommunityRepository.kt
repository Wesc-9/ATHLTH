package com.wesc9.athlth.community

import com.wesc9.athlth.auth.ATHLTHAuth
import io.github.jan.supabase.postgrest.from
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ClubPreview(
    val id: String,
    val name: String,
    val summary: String = "",
    @SerialName("location_name") val location: String? = null
)

@Serializable
data class ChallengePreview(
    val id: String,
    val title: String,
    val subtitle: String = "",
    val kind: String
)

@Serializable
data class CommunityEventPreview(
    val id: String,
    val title: String,
    val summary: String,
    @SerialName("starts_at") val startsAt: String
)

/** Reads only content already visible under existing production RLS. */
class ATHLTHCommunityRepository {
    suspend fun clubs(): List<ClubPreview> = ATHLTHAuth.client
        .from("community_groups").select().decodeList()
    suspend fun challenges(): List<ChallengePreview> = ATHLTHAuth.client
        .from("official_weekly_challenges").select().decodeList()
    suspend fun events(): List<CommunityEventPreview> = ATHLTHAuth.client
        .from("community_events").select().decodeList()
}
