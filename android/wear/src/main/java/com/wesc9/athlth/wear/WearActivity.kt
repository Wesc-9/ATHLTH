package com.wesc9.athlth.wear

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.health.services.client.HealthServices
import java.util.concurrent.Executor

/**
 * Wear OS foundation only. Checks Health Services availability without taking
 * ownership of an exercise or claiming live heart-rate permission.
 */
class WearActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(24, 20, 24, 20)
        }
        val title = TextView(this).apply {
            text = "ATHLTH · Watch"
            textSize = 21f
            gravity = Gravity.CENTER
        }
        val status = TextView(this).apply {
            text = "Klokkefunksjoner utvikles. Ingen økt startes her ennå."
            gravity = Gravity.CENTER
        }
        val button = Button(this).apply { text = "Kontroller Health Services" }
        layout.addView(title)
        layout.addView(status)
        layout.addView(button)
        setContentView(layout)
        button.setOnClickListener {
            button.isEnabled = false
            val future = HealthServices.getClient(this).exerciseClient.getCapabilitiesAsync()
            val executor = Executor { runnable -> runOnUiThread(runnable) }
            future.addListener({
                status.text = try {
                    future.get()
                    "Health Services er tilgjengelig på denne klokken."
                } catch (_: Exception) {
                    "Kunne ikke lese Health Services-kapasiteter."
                }
                button.isEnabled = true
            }, executor)
        }
    }
}
