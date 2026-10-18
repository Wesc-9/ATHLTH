import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// No client-controlled sender, recipient, or user identity is accepted.
// Requires RESEND_API_KEY and a verified SUPPORT_FROM_EMAIL secret.
const DESTINATION = "contact@athlth.com";
const json = (data: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const bearer = request.headers.get("Authorization");
  if (!bearer?.startsWith("Bearer ")) {
    return json({ error: "Sign-in required" }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const sender = Deno.env.get("SUPPORT_FROM_EMAIL");
  if (!supabaseURL || !serviceKey) {
    return json({ error: "Support service unavailable" }, 503);
  }
  if (!resendKey || !sender) {
    // Do not accept a request or claim delivery before email is configured.
    return json({ error: "Email delivery is not configured" }, 503);
  }

  const supabase = createClient(supabaseURL, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: authError } =
    await supabase.auth.getUser(bearer.slice(7).trim());
  if (authError || !user || user.is_anonymous === true) {
    return json({ error: "Invalid session" }, 401);
  }

  let payload: unknown;
  try {
    const raw = await request.text();
    if (raw.length > 16000) return json({ error: "Request too large" }, 413);
    payload = JSON.parse(raw);
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  const input = payload && typeof payload === "object"
    ? payload as Record<string, unknown> : {};
  const subject = typeof input.subject === "string"
    ? input.subject.replace(/[\r\n\u0000-\u001f\u007f]/g, " ").trim() : "";
  const message = typeof input.message === "string" ? input.message.trim() : "";
  const allowReply = input.allow_reply === true;
  if (subject.length < 4 || subject.length > 120 ||
      message.length < 12 || message.length > 5000) {
    return json({ error: "Subject or message length is invalid" }, 422);
  }

  // Read the identity from the server database instead of trusting an
  // arbitrary username included in the request body.
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("username, display_name")
    .eq("id", user.id)
    .maybeSingle();
  if (profileError) return json({ error: "Could not verify profile" }, 503);
  const username = typeof profile?.username === "string"
    ? profile.username.trim() : "";
  if (!username) return json({ error: "Username is required" }, 409);
  const displayName = typeof profile?.display_name === "string"
    ? profile.display_name.slice(0, 80) : "";

  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count, error: rateError } = await supabase
    .from("support_contact_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", oneHourAgo);
  if (rateError) return json({ error: "Support is temporarily unavailable" }, 503);
  if ((count ?? 0) >= 3) {
    return json({ error: "Too many messages. Try again later." }, 429);
  }

  // Reserve an attempt before sending to constrain email spam.
  // No message contents or user email address are stored in this table.
  const { data: attempt, error: reserveError } = await supabase
    .from("support_contact_attempts")
    .insert({ user_id: user.id, status: "attempted" })
    .select("id")
    .single();
  if (reserveError || !attempt?.id) {
    return json({ error: "Support is temporarily unavailable" }, 503);
  }

  const replyTo = allowReply && typeof user.email === "string"
    && user.email.includes("@") ? user.email : undefined;
  const mailBody = [
    "New ATHLTH support request",
    "",
    `Username: @${username}`,
    `Display name: ${displayName || "Not set"}`,
    `User ID: ${user.id}`,
    `Reply permission: ${replyTo ? "Yes" : "No"}`,
    `Contact: ${replyTo ?? "No reply address shared"}`,
    "",
    `Subject: ${subject}`,
    "",
    message,
  ].join("\n");

  let providerResponse: Response;
  try {
    providerResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": attempt.id,
      },
      body: JSON.stringify({
        from: sender,
        to: [DESTINATION],
        subject: `[ATHLTH] ${subject}`,
        text: mailBody,
        ...(replyTo ? { reply_to: replyTo } : {}),
      }),
      signal: AbortSignal.timeout(12000),
    });
  } catch {
    await supabase.from("support_contact_attempts")
      .update({ status: "failed" }).eq("id", attempt.id);
    return json({ error: "Email provider is unreachable" }, 502);
  }

  let receipt: Record<string, unknown> = {};
  try { receipt = await providerResponse.json(); } catch { /* invalid provider payload */ }

  if (!providerResponse.ok || typeof receipt.id !== "string" ||
      receipt.id.length === 0) {
    await supabase.from("support_contact_attempts")
      .update({ status: "failed" }).eq("id", attempt.id);
    return json({ error: "Email provider rejected the request" }, 502);
  }

  await supabase.from("support_contact_attempts")
    .update({ status: "sent" }).eq("id", attempt.id);
  // "sent" means accepted for delivery by Resend, not guaranteed inbox receipt.
  return json({ sent: true });
});
