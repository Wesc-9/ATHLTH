# ATHLTH Live AI Coach — phase 1 security foundation

**Status:** Backend token issuer and iPhone token client code only. There is **no microphone connection, audio chat UI, WebRTC transport, deployment or TestFlight release** in this change. Standard offline Audio Coach continues without AI.

## Safeguards before enabling

- Supabase function `create-audio-coach-session` defaults to **off** and fails closed unless `ATHLTH_LIVE_AI_COACH_ENABLED=true` is configured.
- Long-lived `OPENAI_API_KEY` must be a Supabase secret; never place it in `project.yml`, iOS bundle, Watch app, or source control.
- A signed-in user must explicitly agree to both microphone access and third-party AI audio processing. iOS must separately request microphone permission via a visible, reversible control. **Consent is not inferred from the Audio Coach enabled toggle.**
- Only active/trialing ATHLTH+ users may create a token, subject to the existing atomic `consume_ai_request_budget` RPC (new feature name `audio-coach-realtime`). Reconcile feature allowance and budget **before** deployment; if not configured, token requests are rejected.
- A short-lived provider secret (120 seconds to begin the conversation) is returned after auth. The upstream API key never leaves the backend.
- No HealthKit/route/location metrics are submitted to OpenAI by this phase. Do not describe this as a live data-aware coach yet.
- Validate audio session lifetime/spending, interruption rules, offline fallback, AirPods/Spotify ducking, microphone stop, and app foreground/background behavior before exposing it.
- For future realtime voice transport use WebRTC on iOS with the ephemeral credential. Restore offline voice announcements when conversation is closed, so users do not hear two coaches.
- Apple Watch should act as a remote controller first; keep the iPhone as audio host. Do not put a long-lived provider key or session token in WatchConnectivity payloads.
- Add a real live-status tool only when it can return fresh, user-consented telemetry, explicitly identified as unverified when no fresh measurements are available.

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
