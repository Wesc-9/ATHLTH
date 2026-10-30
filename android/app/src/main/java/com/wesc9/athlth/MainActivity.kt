package com.wesc9.athlth

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.wesc9.athlth.auth.ATHLTHAuth
import com.wesc9.athlth.health.ATHLTHHealthConnect
import com.wesc9.athlth.health.ConnectAvailability
import com.wesc9.athlth.health.HealthOverview
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

private val Ink = Color(0xFF171716)
private val Gold = Color(0xFF9A783E)
private val Paper = Color(0xFFF8F7F4)
private val Muted = Color(0xFF64645F)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { ATHLTHApp() }
    }
}

private enum class Tab(val title: String) {
    HOME("Hjem"), TRAIN("Trening"), PROFILE("Profil")
}

@Composable
private fun ATHLTHApp() {
    val context = LocalContext.current
    val health = remember(context) { ATHLTHHealthConnect(context.applicationContext) }
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(Tab.HOME) }
    var permissions by remember { mutableStateOf(emptySet<String>()) }
    var overview by remember { mutableStateOf(HealthOverview()) }
    var healthError by remember { mutableStateOf<String?>(null) }

    suspend fun refreshHealth() {
        if (health.availability() != ConnectAvailability.AVAILABLE) return
        try {
            permissions = health.grantedPermissions()
            overview = health.overview()
            healthError = null
        } catch (_: SecurityException) {
            // A grant may have been revoked while reading. Refresh immediately.
            permissions = runCatching { health.grantedPermissions() }.getOrDefault(emptySet())
            overview = HealthOverview()
            healthError = "Tilgangen ble endret. Prøv igjen."
        } catch (_: Exception) {
            healthError = "Kunne ikke hente helsedata nå."
        }
    }

    val requestPermissions = rememberLauncherForActivityResult(
        contract = ATHLTHHealthConnect.permissionContract
    ) {
        scope.launch { refreshHealth() } // Partial grants are handled, not rejected.
    }

    LaunchedEffect(Unit) { refreshHealth() }

    val scheme = lightColorScheme(
        primary = Gold,
        onPrimary = Color.White,
        background = Paper,
        onBackground = Ink,
        surface = Color.White,
        onSurface = Ink
    )

    MaterialTheme(colorScheme = scheme) {
        Scaffold(
            containerColor = Paper,
            bottomBar = {
                NavigationBar(containerColor = Color.White) {
                    Tab.entries.forEach { item ->
                        NavigationBarItem(
                            selected = tab == item,
                            onClick = { tab = item },
                            icon = { Text(if (tab == item) "●" else "○") },
                            label = { Text(item.title) }
                        )
                    }
                }
            }
        ) { inner ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(inner)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text("ATHLTH", style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.Bold, color = Ink)
                Text("YOUR BODY. YOUR DATA. YOUR PROGRESS.",
                    style = MaterialTheme.typography.labelMedium, color = Gold)

                when (tab) {
                    Tab.HOME -> HomeScreen(
                        availability = health.availability(),
                        permissions = permissions,
                        overview = overview,
                        error = healthError,
                        onRefresh = { scope.launch { refreshHealth() } },
                        onConnect = {
                            scope.launch {
                                try {
                                    val missing = ATHLTHHealthConnect.basicPermissions -
                                        health.grantedPermissions()
                                    if (missing.isNotEmpty()) requestPermissions.launch(missing)
                                    else refreshHealth()
                                } catch (_: Exception) {
                                    healthError = "Kunne ikke åpne Health Connect."
                                }
                            }
                        },
                        onMoreData = {
                            scope.launch {
                                try {
                                    val missing = ATHLTHHealthConnect.optionalPermissions -
                                        health.grantedPermissions()
                                    if (missing.isNotEmpty()) requestPermissions.launch(missing)
                                    else refreshHealth()
                                } catch (_: Exception) {
                                    healthError = "Kunne ikke åpne Health Connect."
                                }
                            }
                        }
                    )
                    Tab.TRAIN -> TrainScreen()
                    Tab.PROFILE -> ProfileScreen()
                }
            }
        }
    }
}

@Composable
private fun HomeScreen(
    availability: ConnectAvailability,
    permissions: Set<String>,
    overview: HealthOverview,
    error: String?,
    onRefresh: () -> Unit,
    onConnect: () -> Unit,
    onMoreData: () -> Unit
) {
    TitleAndSubtitle("Dagens oversikt", "Helseinformasjon blir på enheten.")
    ATHLTHCard {
        when (availability) {
            ConnectAvailability.UNAVAILABLE ->
                Text("Health Connect støttes ikke av denne enheten.")
            ConnectAvailability.NEEDS_PROVIDER ->
                Text("Installer eller oppdater Health Connect via Google Play.")
            ConnectAvailability.AVAILABLE -> {
                Text(
                    if (permissions.containsAll(ATHLTHHealthConnect.basicPermissions))
                        "Health Connect er koblet til"
                    else "Koble til Androids Health Connect",
                    fontWeight = FontWeight.SemiBold
                )
                Text("Du bestemmer selv hvilke helsedata ATHLTH får lese.",
                    color = Muted)
                if (!permissions.containsAll(ATHLTHHealthConnect.basicPermissions)) {
                    Button(onClick = onConnect) { Text("Gi tilgang til aktivitet") }
                } else {
                    OutlinedButton(onClick = onRefresh) { Text("Oppdater data") }
                }
                if (permissions.containsAll(ATHLTHHealthConnect.basicPermissions) &&
                    !permissions.containsAll(ATHLTHHealthConnect.optionalPermissions)) {
                    OutlinedButton(onClick = onMoreData) {
                        Text("Valgfritt: puls og søvn")
                    }
                }
            }
        }
        if (error != null) Text(error, color = Color(0xFFAA3B2C))
    }

    ATHLTHCard {
        Text("I DAG", color = Gold, fontWeight = FontWeight.Bold)
        MetricRow("Skritt", overview.stepsToday?.toString() ?: "Ikke tilgjengelig")
        MetricRow("Treningsøkter (siste 7 dager)",
            overview.workoutsLastSevenDays?.toString() ?: "Ikke tilgjengelig")
        MetricRow("Siste puls (24 timer)",
            overview.latestHeartRateBpm?.let { "$it bpm" } ?: "Ikke tilgjengelig")
        MetricRow("Siste søvnperiode (36 timer)",
            overview.sleepMinutesLastNight?.let { "$it min (periode)" } ?: "Ikke tilgjengelig")
    }
    Text(
        "ATHLTH importerer ikke økter automatisk. Eventuell import og lagring krever en egen gjennomgang.",
        color = Muted, style = MaterialTheme.typography.bodySmall
    )
}

@Composable
private fun TrainScreen() {
    com.wesc9.athlth.catalog.TrainingCatalogScreen()
}

@Composable
private fun ProfileScreen() {
    val scope = rememberCoroutineScope()
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var signedIn by remember { mutableStateOf(ATHLTHAuth.signedInEmail()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // Reflect sessions restored from secure SDK storage, not only manual sign-in.
    LaunchedEffect(Unit) {
        ATHLTHAuth.sessionStatus.collect {
            signedIn = ATHLTHAuth.signedInEmail()
        }
    }

    TitleAndSubtitle("ATHLTH-konto", "Samme konto som på iPhone.")
    ATHLTHCard {
        if (signedIn != null) {
            Text("Logget inn", fontWeight = FontWeight.SemiBold)
            Text(signedIn ?: "", color = Muted)
            OutlinedButton(enabled = !busy, onClick = {
                scope.launch {
                    busy = true
                    try {
                        ATHLTHAuth.signOut()
                        signedIn = null
                    } catch (_: Exception) {
                        error = "Utlogging mislyktes."
                    } finally {
                        busy = false
                    }
                }
            }) { Text("Logg ut") }
        } else {
            OutlinedTextField(
                value = email, onValueChange = { email = it },
                label = { Text("E-post") }, modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
            OutlinedTextField(
                value = password, onValueChange = { password = it },
                label = { Text("Passord") }, modifier = Modifier.fillMaxWidth(),
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true
            )
            Button(
                enabled = !busy && email.isNotBlank() && password.isNotBlank(),
                colors = ButtonDefaults.buttonColors(containerColor = Ink),
                onClick = {
                    scope.launch {
                        busy = true
                        error = null
                        try {
                            ATHLTHAuth.signIn(email, password)
                            signedIn = ATHLTHAuth.signedInEmail()
                            password = ""
                        } catch (_: Exception) {
                            error = "Innlogging mislyktes. Kontroller e-post og passord."
                        } finally {
                            busy = false
                        }
                    }
                }
            ) { Text(if (busy) "Logger inn…" else "Logg inn") }
            Text(
                "Bruk en eksisterende ATHLTH-konto med e-post og passord. " +
                    "Google-/Apple-innlogging og nyregistrering kommer senere.",
                color = Muted, style = MaterialTheme.typography.bodySmall
            )
        }
        if (error != null) Text(error ?: "", color = Color(0xFFAA3B2C))
    }
    com.wesc9.athlth.catalog.ProfileCloudPanel(signedIn)
}

@Composable
private fun TitleAndSubtitle(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.headlineMedium, color = Ink,
            fontWeight = FontWeight.SemiBold)
        Text(subtitle, color = Muted)
    }
}

@Composable
private fun ATHLTHCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content
        )
    }
}

@Composable
private fun MetricRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = Muted, modifier = Modifier.weight(1f))
        Text(value, color = Ink, fontWeight = FontWeight.SemiBold)
    }
}
