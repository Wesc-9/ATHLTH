# Azure Speech F0 voice preview pilot — ATHLTH v1.8.3

This pilot is OFF until configured. Quick Train Audio Coach remains opt-in; live coaching uses the selected local Apple voice, even offline. Azure only reads a fixed Norwegian sample phrase, never health, GPS, or user-entered text.

## Setup (without automatic paid requests)

1. Create Azure AI Speech as tier **F0**, not S0. Confirm the free tier in Azure Portal and set a billing alert.
2. Store secrets in Supabase Edge Functions only (never GitHub or iPhone): AZURE_SPEECH_KEY and AZURE_SPEECH_REGION (Azure resource region code).
3. Apply the GitHub migration supabase/migrations/20261019010000_azure_tts_preview_free_budget.sql. It reserves a global hard cap of **400,000 characters per UTC calendar month**, below the F0 published 500,000 character allowance, using an atomic RPC. It fails closed.
4. Deploy Supabase Edge Function azure-coach-voice from supabase/functions/azure-coach-voice/index.ts with its dependency supabase/functions/_shared/ai-request-budget.ts. Keep verify_jwt enabled.
5. Enable ATHLTH_AZURE_TTS_ENABLED=true in the Supabase secret settings **last**, after F0 tier and all services are verified. Keep unset/false otherwise.
6. To disable immediately, set ATHLTH_AZURE_TTS_ENABLED=false. An F0 Azure resource cannot be guaranteed free if other Azure resources outside ATHLTH incur charges; confirm billing separately.

## iPhone

Open Audio Coach settings and select one of the fixed Azure Norwegian voice previews: Finn, Iselin or Pernille. The sample is not generated from workout/health data. If provider, network, authentication, or free quota is unavailable, playback fails safely and live workouts continue with offline Apple voices.

## Scope

Preview-only pilot: NOT a replacement for live coach speech. Connecting Azure to live workouts requires separately designed and verified provider selection, consent/privacy handling, latency guarantees, Spotify ducking, Watch voice routing and offline fallback. No TestFlight upload has been performed.

References:
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support