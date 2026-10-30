package com.wesc9.athlth.community

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.wesc9.athlth.auth.ATHLTHAuth
import com.wesc9.athlth.ui.PremiumHero

private val repo = ATHLTHCommunityRepository()
private val quiet = Color(0xFF77716A)
private val gold = Color(0xFF997A45)

@Composable
fun CommunityScreen() {
    val user = ATHLTHAuth.userId()
    var clubs by remember(user) { mutableStateOf<List<ClubPreview>>(emptyList()) }
    var challenges by remember(user) { mutableStateOf<List<ChallengePreview>>(emptyList()) }
    var events by remember(user) { mutableStateOf<List<CommunityEventPreview>>(emptyList()) }
    var error by remember(user) { mutableStateOf(false) }

    LaunchedEffect(user) {
        if (user == null) return@LaunchedEffect
        try {
            clubs = repo.clubs()
            challenges = repo.challenges()
            events = repo.events()
        } catch (_: Exception) {
            error = true
        }
    }

    PremiumHero("CommunityHero.jpg", "Together, stronger")
    Text("COMMUNITY", fontWeight = FontWeight.Bold,
        style = MaterialTheme.typography.headlineMedium)
    if (user == null) {
        Text("Logg inn for å se klubber, utfordringer og arrangementer.",
            color = quiet)
        return
    }
    if (error) Text("Kunne ikke hente Community nå.", color = Color(0xFFA43C30))
    Text("Klubber", style = MaterialTheme.typography.titleLarge, color = gold)
    if (clubs.isEmpty() && !error) Text("Ingen klubber tilgjengelig.", color = quiet)
    clubs.forEach { club ->
        DataCard(club.name, listOfNotNull(club.location, club.summary).joinToString(" · "))
    }
    Text("Ukens utfordringer", style = MaterialTheme.typography.titleLarge, color = gold)
    challenges.take(5).forEach { item -> DataCard(item.title, item.subtitle) }
    Text("Arrangementer", style = MaterialTheme.typography.titleLarge, color = gold)
    events.take(5).forEach { item -> DataCard(item.title, item.summary) }
    Text("Klubbadministrasjon, Arena-konkurranser og påmelding kommer i senere Android-iterasjoner.",
        color = quiet, style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun DataCard(heading: String, detail: String) {
    Card(
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(heading, fontWeight = FontWeight.SemiBold)
            if (detail.isNotBlank()) Text(detail, color = quiet)
        }
    }
}
