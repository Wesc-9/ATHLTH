import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// Single-use offer claim gate. The app does not create or price any offer.
// Apple offer codes must first be generated in App Store Connect and imported
// server-side. No code is revealed until the athlete taps "Claim" within 15m.
const json = (data: Record<string, unknown>, status = 200) =>
  Response.json(data, {
    status, headers: { "Cache-Control": "no-store" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ status: "unavailable" }, 405);
  if (Deno.env.get("ATHLTH_POST_TRIAL_OFFER_ENABLED") !== "true")
    return json({ status: "unavailable" });

  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !service) return json({ status: "unavailable" }, 503);
  const jwt = req.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!jwt) return json({ status: "unavailable" }, 401);

  let body: unknown;
  try {
    if (Number(req.headers.get("Content-Length") || "0") > 512)
      return json({ status: "unavailable" }, 413);
    const raw = await req.text();
    if (raw.length > 512) return json({ status: "unavailable" }, 413);
    body = JSON.parse(raw);
  } catch { return json({ status: "unavailable" }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body))
    return json({ status: "unavailable" }, 400);
  const action = (body as Record<string, unknown>).action;
  if (action !== "present" && action !== "claim")
    return json({ status: "unavailable" }, 400);

  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await admin.auth.getUser(jwt);
  if (!user || authError) return json({ status: "unavailable" }, 401);

  // The user's ID is taken from the authenticated token, never from input.
  const { data, error } = await admin.rpc(
    action === "present"
      ? "start_athlth_post_trial_offer"
      : "claim_athlth_post_trial_offer",
    { p_user_id: user.id },
  );
  if (error) {
    console.warn("[post-trial-offer] claim RPC unavailable", action);
    return json({ status: "unavailable" }, 503);
  }
  // Output contains only a status, deadline and (after claim) one Apple code.
  return json(data ?? { status: "unavailable" });
});
