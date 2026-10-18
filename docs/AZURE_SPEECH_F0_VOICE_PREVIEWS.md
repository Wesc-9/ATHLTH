# Azure Speech F0 — ATHLTH+ live Norwegian coach (v1.8.3)

Azure neural voices **Finn, Iselin, Pernille** are optional and require an ACTIVE ATHLTH+ subscription, checked server-side on every synthesis request. They work for Quick Train on iPhone (strength, running, walking), and mirrored Apple Watch sessions when the iPhone owns speech. The Watch itself always speaks using its best available installed Apple voice. The user must explicitly turn on Audio Coach for each fresh Quick Train workout.

## F0 cost protection and requirements

- Azure Speech resource must remain on F0 (Free), never S0, and should have billing alerts. Creating a free resource alone is insufficient; deployment secrets must match that resource. Other Azure usage on the account is outside this app's controls.
- Supabase function secrets: AZURE_SPEECH_KEY, AZURE_SPEECH_REGION, ATHLTH_AZURE_TTS_ENABLED=true. NEVER store the key in iOS or GitHub.
- Supabase Edge Function azure-coach-voice verifies a signed-in user AND a valid ATHLTH+ trial or active subscription; otherwise 401/403 and no Azure call.
- Monthly fail-closed server quota is 400,000 total characters per UTC calendar month (Azure F0 includes 500,000 Neural TTS characters). Speech cannot exceed the cap because monthly reservations are atomic. Preview mode also consumes existing per-user AI budget.
- Apply both migrations: supabase/migrations/20261019010000_azure_tts_preview_free_budget.sql and supabase/migrations/20261019022000_azure_live_coach_athlth_plus_quota.sql.
- Live mode has separate subscriber fair-use limits (4 requests per minute, 100 per UTC day), shares the same monthly 400k cap. The provider's own F0 standard voice limit is 20 requests/60s across the resource; Azure 429s fall back locally.
- Kill switch: set ATHLTH_AZURE_TTS_ENABLED=false to block ALL new Azure speech requests. No outgoing call when secrets or quota RPC are unavailable.

## Usage and personal information

Audio Coach > Stemme > ATHLTH+ norske stemmer. Enable the explicit Microsoft Azure workout speech data toggle, choose Finn, Iselin or Pernille; preview each using a fixed, non-personal sample. It is possible to return to a local voice in the normal voice menu. Revoking consent removes the Azure selection.

Live coaching messages can include **pace, distance, elapsed time, and heart rate**. This selected spoken message is sent to Azure Speech through the authenticated Supabase Edge Function, with SSML metacharacters escaped and length limited to 220 characters. This function does not log or persist those messages, and does not send GPS traces or medical history. Confirm Azure/Microsoft data-processing commitments separately before launching to end users.

Live iPhone synthesis is best-effort: if service is unavailable, network delays longer than 3.5s, free-budget exhausted or subscriber entitlement not valid, workout capture continues and local Apple TTS takes over. Azure is disabled for the remainder of that workout after a provider failure to prevent repeated slow requests. Spotify is not intentionally paused; spoken-audio ducking follows the normal app setting. Watch fallback remains entirely local.

## Test gate before TestFlight

- Confirm F0 tier, correct Azure secret region and enabled flag. Verify function response and that usage counts grow only on an ATHLTH+ account.
- Verify **non-subscriber cannot preview or synthesize** with forged Azure voice request, and quota exhaustion cannot reach Azure.
- Confirm all three Norwegian voice samples, selecting voice in settings, live speech in strength, running/walking and mirrored Watch workouts, pause/stop/resume/replay, AirPods/Spotify ducking and Watch connectivity loss.
- Confirm consent revocation switches to Apple voice, airplane mode falls back under 3.5s and workout continues, and that a previously active workout stays healthy after closing Audio Coach UI.
- Confirm iPhone, iPad, watchOS builds and backend regression jobs are green. Do NOT upload TestFlight without explicit user instruction.

References:
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits
- https://azure.microsoft.com/en-gb/pricing/details/speech/