import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";
import { validateTurn, coachPrompt, decodeWavBase64 } from "./policy.ts";

const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
function reply(data: Record<string, unknown>, code = 200) {
  return new Response(JSON.stringify(data), { status: code, headers });
}

// Push-to-talk pilot: Groq Whisper (NO/EN) + Groq chat. Apple local TTS.
// Every turn independently authenticates, checks entitlement and consumes
// the existing atomic AI budget. Nothing is stored by this function.
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  if (Deno.env.get("ATHLTH_GROQ_AUDIO_COACH_ENABLED") !== "true") {
    return reply({ error: "Groq voice pilot is disabled", code: "NOT_AVAILABLE" }, 503);
  }
  const token = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!token) return reply({ error: "Authentication required" }, 401);
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!supabaseURL || !serviceKey || !apiKey) {
    return reply({ error: "Voice provider is unavailable" }, 503);
  }

  let parsed: unknown;
  try {
    if (Number(request.headers.get("Content-Length") || "0") > 550_000) {
      return reply({ error: "Audio clip is too long" }, 413);
    }
    const raw = await request.text();
    if (raw.length > 550_000) return reply({ error: "Audio clip is too long" }, 413);
    parsed = JSON.parse(raw);
  } catch {
    return reply({ error: "Invalid request" }, 400);
  }
  const turn = validateTurn(parsed);
  if (!turn) return reply({ error: "Explicit voice processing consent and a valid audio clip or text are required" }, 400);

  const admin = createClient(supabaseURL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await admin.auth.getUser(token);
  if (authError || !user) return reply({ error: "Invalid authentication" }, 401);

  const { data: entitlement, error: entitlementError } = await admin
    .from("subscription_entitlements")
    .select("tier,status,trial_ends_at,current_period_ends_at")
    .eq("user_id", user.id).maybeSingle();
  if (entitlementError) return reply({ error: "Entitlement temporarily unavailable" }, 503);
  const now = Date.now();
  const validUntil = (value: unknown) => typeof value === "string" && Date.parse(value) > now;
  const subscribed = entitlement?.tier === "plus" &&
    ((entitlement.status === "active" &&
        (entitlement.current_period_ends_at == null || validUntil(entitlement.current_period_ends_at))) ||
      (entitlement.status === "trialing" && validUntil(entitlement.trial_ends_at)));
  if (!subscribed) return reply({ error: "ATHLTH+ required", code: "PREMIUM_REQUIRED" }, 403);

  // Existing production-enforced feature: 5 budget units per turn,
  // 10/minute and 100/day shared with other AI features. Fail closed.
  const budgetError = await enforceAIRequestBudget(() =>
    admin.rpc("consume_ai_request_budget", {
      p_user_id: user.id,
      p_feature: "generate-training-program",
    }));
  if (budgetError) return budgetError;

  let transcription = turn.text;
  if (turn.audioBase64) {
    const wav = decodeWavBase64(turn.audioBase64);
    if (!wav) return reply({ error: "Audio must be short PCM mono WAV, 16 kHz" }, 400);
    const form = new FormData();
    // Copy to a guaranteed ArrayBuffer-backed Uint8Array for Blob/File.
    const audioCopy = new Uint8Array(wav.byteLength);
    audioCopy.set(wav);
    form.append("file", new File([audioCopy.buffer], "question.wav", { type: "audio/wav" }));
    form.append("model", "whisper-large-v3-turbo");
    form.append("language", turn.language);
    form.append("response_format", "json");
    let stt: Response;
    try {
      stt = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}` },
        body: form, signal: AbortSignal.timeout(14_000),
      });
    } catch { return reply({ error: "Speech recognition unavailable" }, 502); }
    if (!stt.ok) {
      return reply({ error: stt.status === 429 ? "Groq rate limit reached" : "Speech recognition failed",
        code: stt.status === 429 ? "PROVIDER_RATE_LIMIT" : "TRANSCRIPTION_FAILED" },
        stt.status === 429 ? 429 : 502);
    }
    try {
      const result = await stt.json() as { text?: unknown };
      transcription = typeof result.text === "string" ? result.text.trim().slice(0, 450) : "";
    } catch { return reply({ error: "Invalid speech recognition response" }, 502); }
  }
  if (!transcription || transcription.length < 2) {
    return reply({ error: "I could not hear a question", code: "NO_SPEECH" }, 422);
  }

  // Deliberately NO workout telemetry in the pilot. The Groq DPA, transfers
  // and data retention must be verified before any health status can be shared.
  const messages = [
    { role: "system", content: coachPrompt(turn.language, turn.tone) },
    { role: "user", content: transcription },
  ];
  let ai: Response;
  try {
    ai = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("GROQ_AUDIO_COACH_MODEL") || "llama-3.3-70b-versatile",
        messages, temperature: 0.45, max_completion_tokens: 180,
        stream: false,
      }),
      signal: AbortSignal.timeout(16_000),
    });
  } catch { return reply({ error: "Coach is temporarily unavailable" }, 502); }
  if (!ai.ok) {
    return reply({
      error: ai.status === 429 ? "Groq rate limit reached" : "Coach response failed",
      code: ai.status === 429 ? "PROVIDER_RATE_LIMIT" : "MODEL_FAILED",
    }, ai.status === 429 ? 429 : 502);
  }
  let responseText = "";
  try {
    const data = await ai.json() as {
      choices?: { message?: { content?: unknown } }[];
    };
    const content = data.choices?.[0]?.message?.content;
    responseText = typeof content === "string" ? content.trim().slice(0, 900) : "";
  } catch { return reply({ error: "Invalid coach response" }, 502); }
  if (!responseText) return reply({ error: "Coach gave no reply" }, 502);
  return reply({ transcript: transcription, reply: responseText, provider: "groq", voice: "apple-system" });
});
