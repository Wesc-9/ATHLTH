# ATHLTH Groq Voice Coach — manual test pilot

- Uses existing `GROQ_API_KEY` in Supabase, **not** an OpenAI Realtime key.
- User starts each clip manually (maximum 10 s, PCM16 16 kHz, mono WAV). Clip sent to Supabase `audio-coach-groq-turn`, forwarded to Groq Whisper Turbo, then the resulting text goes to the Groq Llama chat model. Groq returns text; iPhone speaks it with the user's selected local Apple voice.
- The microphone never starts on opening the coach; it starts only after explicit consent and a tap. Input is not sent if the clip times out, is too short, is cancelled, or the sheet closes.
- No full-duplex, always-listening or seamless interruption handling; this first version is **push-to-talk**, not Realtime AI.
- The function defaults to **disabled** unless `ATHLTH_GROQ_AUDIO_COACH_ENABLED=true` is set as a server secret. API keys stay server-side.
- User must be signed in and ATHLTH+ (active/trial). Requests are bounded by the existing atomic shared AI budget via `generate-training-program` reservation (5 units = maximum 2 pilot turns/minute with an empty budget, 20/day if no other AI features use budget). A separate feature quota should be implemented before scaling.
- The pilot shares **no GPS, training location, history, pulse, recovery metrics or live training stats with Groq** even if the app has them. Do not enable auto-health sharing until DPA, provider retention, international transfer assessment, and explicit question-specific health disclosure have been checked.
- The old OpenAI Realtime implementation remains in source for reference but is **not reachable through the live workout button**.
- Enable the function only after successful Deno tests, review of active key and quotas, an API billing limit, and physical iPhone/Watch + AirPods testing. Free plan has limited rate quotas; not guaranteed unlimited free service.
- No TestFlight deployment is implied by committing this source.

Validation:
```sh
deno test supabase/functions/audio-coach-groq-turn/policy.test.ts
deno check supabase/functions/audio-coach-groq-turn/index.ts
```
