# ATHLTH Live AI Coach — phase 1 security foundation

**Status (phase 2):** Added an opt-in live-workout conversation view and an initial native AVAudioEngine/WebSocket transport for iPhone. Microphone handling, PCM audio and response playback are implemented in source, but **hardware validation, latency testing, billing approval and deployment are still outstanding**. The new server function remains **disabled by default**. Standard offline Audio Coach continues without AI.

## Safeguards before enabling

- Supabase function `create-audio-coach-session` defaults to **off** and fails closed unless `ATHLTH_LIVE_AI_COACH_ENABLED=true` is configured.
- Long-lived `OPENAI_API_KEY` must be a Supabase secret; never place it in `project.yml`, iOS bundle, Watch app, or source control.
- A signed-in user must explicitly agree to both microphone access and third-party AI audio processing. iOS must separately request microphone permission via a visible, reversible control. **Consent is not inferred from the Audio Coach enabled toggle.**
- Only active/trialing ATHLTH+ users may create a token, subject to the existing atomic `consume_ai_request_budget` RPC (new feature name `audio-coach-realtime`). Reconcile feature allowance and budget **before** deployment; if not configured, token requests are rejected.
- A short-lived provider secret (120 seconds to begin the conversation) is returned after auth. The upstream API key never leaves the backend.
- No HealthKit/route/location metrics are submitted to OpenAI by this phase. Do not describe this as a live data-aware coach yet.
- Validate audio session lifetime/spending, interruption rules, offline fallback, AirPods/Spotify ducking, microphone stop, and app foreground/background behavior before exposing it.
- Phase 2 uses native WebSocket streaming with PCM16 24 kHz, explicitly started/stopped by the user; the app resumes its prior offline Audio Coach mute state when conversation ends. Assess WebRTC before production release for more robust network jitter handling, audio playback interruption and AirPods/mixed-audio behavior.
- Apple Watch should act as a remote controller first; keep the iPhone as audio host. Do not put a long-lived provider key or session token in WatchConnectivity payloads.
- Add a real live-status tool only when it can return fresh, user-consented telemetry, explicitly identified as unverified when no fresh measurements are available.
- iPhone conversation screen is only reachable from an active workout, requests both consent toggles and native microphone permission, stops on dismissal/background, and limits conversations to five minutes on the client.
- A client time limit is **not** a server-enforced usage cap. Confirm backend provider spending controls and server-side session termination/accounting before enabling the feature for customers.
- Apple Watch can now send a fresh, interactive request to **open the iPhone consent UI** when the iPhone is reachable and the mirrored workout is displayed. The Watch does **not** activate the microphone or persist requests. The iPhone remains the only AI audio host. Never imply that voice capture on Watch or automatic remote mic activation is supported.

## Environment

```text
ATHLTH_LIVE_AI_COACH_ENABLED=false
OPENAI_API_KEY=<secret managed in Supabase>
OPENAI_REALTIME_MODEL=gpt-realtime-2.1
```

The model and API availability must be checked against the provider account before activation. Also configure billing/spending caps. The ephemeral endpoint alone is not a functioning AI conversation.

## Quick policy tests

```sh
deno test supabase/functions/create-audio-coach-session/policy.test.ts
```
