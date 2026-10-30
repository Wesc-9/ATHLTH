package com.wesc9.athlth.catalog

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.wesc9.athlth.auth.ATHLTHAuth
import kotlinx.coroutines.launch

private val gold = Color(0xFF997A45)
private val secondary = Color(0xFF77716A)
private val repository = ATHLTHCatalogRepository()

@Composable
fun TrainingCatalogScreen() {
    val account = ATHLTHAuth.userId()
    var plans by remember(account) { mutableStateOf<List<TrainingPlanCatalogItem>>(emptyList()) }
    var workouts by remember(account) { mutableStateOf<List<WorkoutTemplateCatalogItem>>(emptyList()) }
    var loading by remember(account) { mutableStateOf(false) }
    var failed by remember(account) { mutableStateOf(false) }
    var selection by remember { mutableStateOf("Planer") }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        if (account == null) return
        loading = true
        failed = false
        try {
            plans = repository.trainingPlans()
            workouts = repository.workoutTemplates()
        } catch (_: Exception) {
            failed = true
        } finally {
            loading = false
        }
    }

    LaunchedEffect(account) { refresh() }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        com.wesc9.athlth.ui.PremiumHero("TrainHero.jpg", "Din trening")
        com.wesc9.athlth.training.WorkoutTimerPreview()
        Text("TRAIN", style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold)
        Text("Tren smartere, med samme ATHLTH-bibliotek som på iPhone.",
            color = secondary)
        if (account == null) {
            PremiumPanel {
                Text("Logg inn på Profil for å åpne treningsbiblioteket.",
                    fontWeight = FontWeight.SemiBold)
            }
            return@Column
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Planer", "Økter").forEach { title ->
                OutlinedButton(
                    onClick = { selection = title },
                    border = BorderStroke(1.dp, if (selection == title) gold else Color.LightGray)
                ) { Text(title, color = if (selection == title) gold else secondary) }
            }
        }

        if (failed) PremiumPanel {
            Text("Kunne ikke hente biblioteket.", color = Color(0xFFAA3B2C))
            Button(onClick = { scope.launch { refresh() } }) { Text("Prøv igjen") }
        }
        if (loading) Text("Henter ATHLTH-innhold…", color = secondary)

        if (selection == "Planer") {
            plans.forEach { plan ->
                PremiumPanel {
                    Text(plan.title, fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.titleMedium)
                    if (plan.summary.isNotBlank()) Text(plan.summary, color = secondary)
                    Text("${plan.durationWeeks} uker · ${plan.sessionsPerWeek} økter per uke · ${plan.level}",
                        color = gold, style = MaterialTheme.typography.bodySmall)
                    Text("Planmal – aktivering kommer med personlig plansynkronisering.",
                        color = secondary, style = MaterialTheme.typography.labelSmall)
                }
            }
        } else {
            workouts.forEach { workout ->
                PremiumPanel {
                    Text(workout.title, fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.titleMedium)
                    if (workout.summary.isNotBlank()) Text(workout.summary, color = secondary)
                    Text("${workout.difficulty} · ${workout.estimatedDurationMinutes ?: "–"} min",
                        color = gold, style = MaterialTheme.typography.bodySmall)
                    Text("Øktmal – ingen treningsøkt startes automatisk.",
                        color = secondary, style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        if (!loading && !failed && selection == "Planer" && plans.isEmpty()) {
            Text("Ingen publiserte planer tilgjengelig.", color = secondary)
        }
        if (!loading && !failed && selection == "Økter" && workouts.isEmpty()) {
            Text("Ingen publiserte økter tilgjengelig.", color = secondary)
        }
    }
}

@Composable
fun ProfileCloudPanel(signedIn: String?) {
    var profile by remember(signedIn) { mutableStateOf<ATHLTHProfile?>(null) }
    var backup by remember(signedIn) { mutableStateOf<TrainingBackupConsent?>(null) }
    var failed by remember(signedIn) { mutableStateOf(false) }
    LaunchedEffect(signedIn) {
        if (signedIn == null) return@LaunchedEffect
        try {
            profile = repository.myProfile()
            backup = repository.backupConsent()
        } catch (_: Exception) { failed = true }
    }
    if (signedIn != null) PremiumPanel {
        Text("Min ATHLTH-profil", fontWeight = FontWeight.SemiBold)
        Text(profile?.displayName ?: "ATHLTH-bruker",
            style = MaterialTheme.typography.titleLarge)
        if (profile?.username != null) Text("@${profile?.username}", color = gold)
        Text(
            if (backup?.enabled == true) "iOS-sikkerhetskopi: samtykke er aktivt"
            else "iOS-sikkerhetskopi: ikke aktivert",
            color = secondary, style = MaterialTheme.typography.bodySmall
        )
        Text("Sikkerhetskopier er ikke automatisk toveis synkronisering.",
            color = secondary, style = MaterialTheme.typography.bodySmall)
        if (failed) Text("Noen kontodetaljer kunne ikke hentes.", color = Color(0xFFAA3B2C))
    }
}

@Composable
private fun PremiumPanel(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Card(
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content
        )
    }
}
