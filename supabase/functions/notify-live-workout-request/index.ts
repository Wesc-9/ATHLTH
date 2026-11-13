import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// The only supported effect is a brief APNs alert to the athlete's OWN
// registered iPhone. No workout title, health metric, location or consent
// grant is ever sent by this function.
const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const encoder = new TextEncoder();

function base64URL(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

function privateKeyBytes(pem: string): Uint8Array {
  const normalized = pem.replaceAll("\\n", "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0));
}

let cachedProvider: { token: string; createdAt: number } | null = null;
async function apnsProviderToken(privateKey: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedProvider && now - cachedProvider.createdAt < 45 * 60) {
    return cachedProvider.token;
  }
  // Same active APNs signing identity used by send-apns-push.
  const input = base64URL(JSON.stringify({ alg: "ES256", kid: "AUYD5QP5AN" }))
    + "." + base64URL(JSON.stringify({ iss: "D3AX7B6RMW", iat: now }));
  const key = await crypto.subtle.importKey(
    "pkcs8", privateKeyBytes(privateKey),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const signed = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input),
    ),
  );
  const token = input + "." + base64URL(signed);
  cachedProvider = { token, createdAt: now };
  return token;
}

type Device = {
  id: string;
  apns_token: string;
  apns_environment: "sandbox" | "production";
  app_bundle_id: string;
  language_code: string | null;
};

async function send(device: Device, authToken: string, requestID: string) {
  const norwegian = device.language_code === "nb";
  const host = device.apns_environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const payload = {
    aps: {
      alert: {
        title: norwegian ? "Liveøkt på iPad" : "Live workout on iPad",
        body: norwegian
          ? "Åpne ATHLTH for å godkjenne forespørselen om visning av denne økten."
          : "Open ATHLTH to approve viewing this workout on your iPad.",
      },
      sound: "default",
      "thread-id": "athlth-live-view",
      "interruption-level": "active",
    },
    athlth_kind: "live_workout_view_request",
    athlth_request_id: requestID,
  };
  const res = await fetch(host + "/3/device/" + encodeURIComponent(device.apns_token), {
    method: "POST",
    headers: {
      authorization: "bearer " + authToken,
      "apns-topic": device.app_bundle_id,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 90),
      "apns-collapse-id": "athlth-live-view-" + requestID,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  return res.ok;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRole) return json({ queued: false, reason: "unavailable" }, 503);
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ queued: false, reason: "unauthorized" }, 401);
  }
  const suppliedToken = authorization.slice(7).trim();

  let requestID: string;
  try {
    const body = await req.json();
    requestID = typeof body?.request_id === "string" ? body.request_id : "";
  } catch {
    return json({ queued: false, reason: "invalid_payload" }, 400);
  }
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(requestID)) {
    return json({ queued: false, reason: "invalid_request_id" }, 400);
  }

  const admin = createClient(url, serviceRole, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  // Verify the actual Auth user. Do not trust user IDs in request bodies.
  const { data: auth, error: authError } = await admin.auth.getUser(suppliedToken);
  const userID = auth?.user?.id;
  if (authError || !userID) return json({ queued: false, reason: "unauthorized" }, 401);

  const { data: row, error: rowError } = await admin
    .from("private_live_view_requests")
    .select("request_id,status,expires_at,push_notified_at")
    .eq("user_id", userID)
    .eq("request_id", requestID)
    .maybeSingle();
  if (rowError || !row || row.status !== "pending" ||
      new Date(row.expires_at).getTime() <= Date.now()) {
    return json({ queued: false, reason: "request_not_pending" }, 409);
  }

  const { data: presence } = await admin
    .from("private_active_workout_presence")
    .select("updated_at")
    .eq("user_id", userID)
    .maybeSingle();
  // A recently active source is required. A stopped workout must not generate
  // a surprise approval notification, even if an old request is still pending.
  if (!presence ||
      Date.now() - new Date(presence.updated_at).getTime() > 120_000) {
    return json({ queued: false, reason: "workout_not_active" });
  }

  const { data: devices, error: devicesError } = await admin
    .from("notification_devices")
    .select("id,apns_token,apns_environment,app_bundle_id,language_code")
    .eq("user_id", userID)
    .eq("platform", "ios")
    .eq("device_family", "iphone")
    .limit(5);
  if (devicesError || !devices?.length) {
    return json({ queued: false, reason: "no_registered_iphone" });
  }

  const now = new Date();
  const threshold = new Date(now.getTime() - 30_000).toISOString();
  const { data: claimed, error: claimError } = await admin
    .from("private_live_view_requests")
    .update({ push_notified_at: now.toISOString() })
    .eq("user_id", userID)
    .eq("request_id", requestID)
    .eq("status", "pending")
    .gt("expires_at", now.toISOString())
    .or("push_notified_at.is.null,push_notified_at.lt." + threshold)
    .select("request_id");
  if (claimError || !claimed?.length) {
    return json({ queued: false, reason: "already_notified" });
  }

  const key = Deno.env.get("APNS_PRIVATE_KEY");
  if (!key) return json({ queued: false, reason: "push_not_configured" }, 503);
  let provider: string;
  try { provider = await apnsProviderToken(key); }
  catch { return json({ queued: false, reason: "push_unavailable" }, 503); }

  const results = await Promise.all(
    (devices as Device[]).map((device) =>
      send(device, provider, requestID).catch(() => false)
    ),
  );
  return json({ queued: results.some(Boolean),
                reason: results.some(Boolean) ? "sent" : "delivery_failed" });
});
