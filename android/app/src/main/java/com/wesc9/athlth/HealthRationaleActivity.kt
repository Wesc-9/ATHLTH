package com.wesc9.athlth

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Required entry point for the Health Connect permission rationale intent. */
class HealthRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp)
                ) {
                    Text("ATHLTH · Personvern", style = MaterialTheme.typography.headlineMedium)
                    Text(
                        "ATHLTH ber om tilgang til aktivitet, treningsøkter og eventuelt puls " +
                            "og søvn for å vise dine egne helse- og treningsmålinger."
                    )
                    Text(
                        "Du kan avslå eller trekke tilbake Health Connect-tilgang i Android-innstillingene. " +
                            "Det blir ikke opprettet ATHLTH-økter automatisk fra eksterne kilder."
                    )
                    Text(
                        "Helsedata overføres ikke til ATHLTHs skylagring eller AI-tjenester " +
                            "gjennom denne første Android-integrasjonen."
                    )
                    Text("Kontakt: contact@athlth.com")
                    Text(
                        "Før Play-publisering må denne teksten samsvare med en offentlig " +
                            "personvernerklæring oppgitt i Google Play.",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
    }
}
