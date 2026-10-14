import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";
import {
  checkLiveCoachConsent,
  realtimeCoachSessionConfiguration,
} from "./policy.ts";

const headers = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

/**
 * Phase 1: authenticated, opt-in token issuer ONLY.
 * This function does not start a microphone, stream audio or read HealthKit.
 * Do not enable the feature until iPhone WebRTC, stop controls, usage metering
 * and physical audio testing have been implemented and reviewed.
 */
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (Deno.env.get("ATHLTH_LIVE_AI_COACH_ENABLED") !== "true") {
    return json({ error: "Live AI coach is not enabled", code: "NOT_AVAILABLE" }, 503);
  }

  const bearer = request.headers.get("Authorization");
  if (!bearer?.startsWith("Bearer ")) {
    return json({ error: "Sign-in required" }, 401);
  }

  let incoming: unknown;
  try {
    if (Number(request.headers.get("Content-Length") ?? "0") > 4096) {
      return json({ error: "Request too large" }, 413);
    }
    incoming = await request.json();
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
  const choices = checkLiveCoachConsent(incoming);
  if (!choices) {
    return json({
      error: "Explicit AI microphone consent is required",
      code: "CONSENT_REQUIRED",
    }, 400);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!apiKey || !url || !serviceRole) {
    return json({ error: "Voice provider is unavailable" }, 503);
  }

  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } =
    await admin.auth.getUser(bearer.slice(7).trim());
  if (authError || !user) {
    return json({ error: "Invalid session" }, 401);
  }

  const { data: plan, error: planError } = await admin
    .from("subscription_entitlements")
    .select("status,trial_ends_at,current_period_ends_at")
    .eq("user_id", user.id)
    .maybeSingle();

  if (planError) return json({ error: "Entitlement check unavailable" }, 503);
  const now = Date.now();
  const trial = plan?.status === "trialing" &&
    typeof plan.trial_ends_at === "string" && Date.parse(plan.trial_ends_at) > now;
  const paid = plan?.status === "active" &&
    (plan.current_period_ends_at == null ||
      (typeof plan.current_period_ends_at === "string" &&
        Date.parse(plan.current_period_ends_at) > now));
  if (!trial && !paid) {
    return json({ error: "ATHLTH+ required", code: "PREMIUM_REQUIRED" }, 403);
  }

  // Fail closed if the budget RPC does not recognize this new feature.
  const budget = await enforceAIRequestBudget(() =>
    admin.rpc("consume_ai_request_budget", {
      p_user_id: user.id,
      p_feature: "audio-coach-realtime",
    })
  );
  if (budget) return budget;

  const idBytes = new TextEncoder().encode(user.id);
  const digest = await crypto.subtle.digest("SHA-256", idBytes);
  const hashedID = Array.from(new Uint8Array(digest))
    .map((v) => v.toString(16).padStart(2, "0")).join("");

  const session = realtimeCoachSessionConfiguration(
    choices,
    Deno.env.get("OPENAI_REALTIME_MODEL") ?? "gpt-realtime-2.1",
  );

  let response: Response;
  try {
    response = await fetch(
      "https://api.openai.com/v1/realtime/client_secrets",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "OpenAI-Safety-Identifier": hashedID,
        },
        body: JSON.stringify({
          expires_after: { anchor: "created_at", seconds: 120 },
          session,
        }),
        signal: AbortSignal.timeout(10_000),
      }
    );
  } catch {
    return json({ error: "Voice provider could not be reached" }, 502);
  }
  if (!response.ok) {
    return json({ error: "Could not start a voice session" }, 502);
  }

  let token: unknown;
  try { token = await response.json(); } catch {
    return json({ error: "Invalid voice provider response" }, 502);
  }
  const secret = token as { value?: unknown; expires_at?: unknown };
  if (typeof secret?.value !== "string" ||
      !secret.value.startsWith("ek_") ||
      !Number.isFinite(secret.expires_at)) {
    return json({ error: "Invalid voice session token" }, 502);
  }

  // Never return the long-lived OpenAI key. Do not log or persist the token.
  return json({
    token: secret.value,
    expiresAt: secret.expires_at,
    model: session.model,
  });
});
