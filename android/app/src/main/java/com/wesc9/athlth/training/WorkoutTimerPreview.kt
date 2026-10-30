package com.wesc9.athlth.training

import android.os.SystemClock
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/** An interactive local workout timeline preview, not a Health Connect session. */
@Composable
fun WorkoutTimerPreview() {
    var choice by remember { mutableStateOf("4×4") }
    var generation by remember { mutableIntStateOf(0) }
    val timeline = remember(choice, generation) {
        WorkoutTimeline(if (choice == "4×4") SampleWorkouts.runningFourByFour()
            else SampleWorkouts.strength())
    }
    var repaint by remember(choice, generation) { mutableIntStateOf(0) }
    val running = timeline.snapshot.running

    LaunchedEffect(choice, generation, running) {
        while (timeline.snapshot.running) {
            delay(250L)
            timeline.tick(SystemClock.elapsedRealtime())
            repaint++
        }
    }
    @Suppress("UNUSED_VARIABLE")
    val observed = repaint
    val state = timeline.snapshot
    val segment = timeline.segments[state.index]
    val remaining = state.remainingMs?.let {
        val seconds = (it + 999L) / 1000L
        "%02d:%02d".format(seconds / 60, seconds % 60)
    } ?: "Manuelt sett"

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF191A19))
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("ØKTMOTOR · TESTVISNING",
                color = Color(0xFFCEB884), fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("4×4", "Styrke").forEach { name ->
                    OutlinedButton(onClick = {
                        choice = name
                        generation++
                    }) { Text(name, color = Color.White) }
                }
            }
            Text(segment.label, color = Color.White,
                style = MaterialTheme.typography.titleLarge)
            Text(if (state.finished) "Ferdig" else remaining, color = Color.White,
                style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            if (segment.heartRateZone != null)
                Text("Mål: Z${segment.heartRateZone}", color = Color(0xFFCEB884))
            Text("${state.completedCount} av ${timeline.segments.size} deler",
                color = Color.LightGray)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!state.finished) {
                    Button(onClick = {
                        if (state.running) timeline.pause()
                        else timeline.start(SystemClock.elapsedRealtime())
                        repaint++
                    }) { Text(if (state.running) "Pause" else "Start / fortsett") }
                    OutlinedButton(onClick = {
                        timeline.advance(SystemClock.elapsedRealtime())
                        repaint++
                    }) { Text("Neste") }
                }
                OutlinedButton(onClick = { generation++ }) {
                    Text("Nullstill", color = Color.White)
                }
            }
            Text("Kun lokal forhåndsvisning. Ingen økt lagres eller sendes til Health Connect.",
                color = Color.LightGray, style = MaterialTheme.typography.bodySmall)
        }
    }
}
