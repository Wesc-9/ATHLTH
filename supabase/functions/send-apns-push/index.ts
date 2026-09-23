import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type InboxEvent = {
  id: string;
  recipient_id: string;
  kind: string;
  title: string;
  message: string;
  entity_type: string | null;
  entity_id: string | null;
  push_notified_at: string | null;
};

type NotificationDevice = {
  id: string;
  app_bundle_id: string;
  apns_environment: "sandbox" | "production";
  apns_token: string;
};

type UserPreferences = {
  friend_activity_notifications_enabled: boolean;
  challenge_notifications_enabled: boolean;
  message_notifications_enabled: boolean;
};

const encoder = new TextEncoder();

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

function base64URL(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? encoder.encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);

  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
}

function pemToBytes(pem: string): Uint8Array {
  const normalized = pem.replaceAll("\\n", "\n");
  const base64 = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");

  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

let cachedProviderToken:
  | { value: string; generatedAt: number; keyID: string; teamID: string }
  | null = null;

async function providerToken(
  keyID: string,
  teamID: string,
  privateKeyPEM: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  if (
    cachedProviderToken &&
    cachedProviderToken.keyID === keyID &&
    cachedProviderToken.teamID === teamID &&
    now - cachedProviderToken.generatedAt < 50 * 60
  ) {
    return cachedProviderToken.value;
  }

  const header = base64URL(
    JSON.stringify({ alg: "ES256", kid: keyID }),
  );
  const claims = base64URL(
    JSON.stringify({ iss: teamID, iat: now }),
  );
  const signingInput = `${header}.${claims}`;

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(privateKeyPEM),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      cryptoKey,
      encoder.encode(signingInput),
    ),
  );

  const token = `${signingInput}.${base64URL(signature)}`;
  cachedProviderToken = {
    value: token,
    generatedAt: now,
    keyID,
    teamID,
  };
  return token;
}

function preferenceAllows(
  kind: string,
  preferences: UserPreferences | null,
): boolean {
  if (!preferences) return true;

  const normalized = kind.toLowerCase();

  if (
    normalized.includes("message") ||
    normalized.includes("dm")
  ) {
    return preferences.message_notifications_enabled;
  }

  if (normalized.includes("challenge")) {
    return preferences.challenge_notifications_enabled;
  }

  return preferences.friend_activity_notifications_enabled;
}

function threadID(event: InboxEvent): string {
  if (event.entity_type && event.entity_id) {
    return `${event.entity_type}:${event.entity_id}`;
  }
  return event.kind;
}

async function sendToDevice(
  device: NotificationDevice,
  event: InboxEvent,
  unreadCount: number,
  authToken: string,
): Promise<{
  deviceID: string;
  ok: boolean;
  status: number;
  reason?: string;
  shouldDelete: boolean;
}> {
  const host = device.apns_environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";

  const payload = {
    aps: {
      alert: {
        title: event.title,
        body: event.message,
      },
      sound: "default",
      badge: unreadCount,
      "thread-id": threadID(event),
      "interruption-level": "active",
    },
    athlth_event_id: event.id,
    athlth_kind: event.kind,
    athlth_entity_type: event.entity_type,
    athlth_entity_id: event.entity_id,
  };

  const response = await fetch(
    `${host}/3/device/${encodeURIComponent(device.apns_token)}`,
    {
      method: "POST",
      headers: {
        authorization: `bearer ${authToken}`,
        "apns-topic": device.app_bundle_id,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": "0",
        "apns-collapse-id": event.id,
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    },
  );

  let reason: string | undefined;
  if (!response.ok) {
    try {
      const body = await response.json();
      reason = typeof body?.reason === "string"
        ? body.reason
        : undefined;
    } catch {
      reason = undefined;
    }
  }

  const shouldDelete =
    response.status === 410 ||
    reason === "BadDeviceToken" ||
    reason === "DeviceTokenNotForTopic" ||
    reason === "Unregistered";

  return {
    deviceID: device.id,
    ok: response.ok,
    status: response.status,
    reason,
    shouldDelete,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const teamID =
    Deno.env.get("APNS_TEAM_ID") ?? "D3AX7B6RMW";

  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "ATHLTH backend is unavailable." }, 503);
  }

  if (!keyID || !privateKey) {
    return json({
      error: "APNs credentials are not configured.",
      code: "APNS_NOT_CONFIGURED",
    }, 503);
  }

  let eventID: string | null = null;
  try {
    const body = await req.json();
    eventID =
      typeof body?.event_id === "string"
        ? body.event_id
        : typeof body?.record?.id === "string"
        ? body.record.id
        : null;
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  if (!eventID) {
    return json({ error: "Missing event_id." }, 400);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: event, error: eventError } = await admin
    .from("social_inbox_events")
    .select(
      "id,recipient_id,kind,title,message,entity_type,entity_id,push_notified_at",
    )
    .eq("id", eventID)
    .maybeSingle<InboxEvent>();

  if (eventError) {
    console.error("Unable to load push event", eventError);
    return json({ error: "Unable to load notification event." }, 500);
  }

  if (!event) {
    return json({ error: "Notification event not found." }, 404);
  }

  if (event.push_notified_at) {
    return json({ ok: true, alreadyDelivered: true });
  }

  const { data: preferences } = await admin
    .from("user_preferences")
    .select(
      "friend_activity_notifications_enabled,challenge_notifications_enabled,message_notifications_enabled",
    )
    .eq("user_id", event.recipient_id)
    .maybeSingle<UserPreferences>();

  if (!preferenceAllows(event.kind, preferences ?? null)) {
    await admin
      .from("social_inbox_events")
      .update({ push_notified_at: new Date().toISOString() })
      .eq("id", event.id);

    return json({ ok: true, skipped: "user_preference" });
  }

  const { data: devices, error: deviceError } = await admin
    .from("notification_devices")
    .select("id,app_bundle_id,apns_environment,apns_token")
    .eq("user_id", event.recipient_id)
    .eq("platform", "ios")
    .returns<NotificationDevice[]>();

  if (deviceError) {
    console.error("Unable to load APNs devices", deviceError);
    return json({ error: "Unable to load notification devices." }, 500);
  }

  if (!devices || devices.length === 0) {
    return json({ ok: true, delivered: 0, reason: "no_devices" });
  }

  const { count } = await admin
    .from("social_inbox_events")
    .select("id", { count: "exact", head: true })
    .eq("recipient_id", event.recipient_id)
    .is("read_at", null);

  let token: string;
  try {
    token = await providerToken(keyID, teamID, privateKey);
  } catch (error) {
    console.error("Unable to create APNs provider token", error);
    return json({
      error: "APNs provider authentication failed.",
      code: "APNS_AUTH_FAILED",
    }, 503);
  }

  const results = await Promise.all(
    devices.map((device) =>
      sendToDevice(
        device,
        event,
        Math.max(count ?? 1, 1),
        token,
      )
    ),
  );

  const invalidDeviceIDs = results
    .filter((result) => result.shouldDelete)
    .map((result) => result.deviceID);

  if (invalidDeviceIDs.length > 0) {
    await admin
      .from("notification_devices")
      .delete()
      .in("id", invalidDeviceIDs);
  }

  const delivered = results.filter((result) => result.ok).length;

  if (delivered > 0) {
    await admin
      .from("social_inbox_events")
      .update({ push_notified_at: new Date().toISOString() })
      .eq("id", event.id);
  }

  for (const result of results.filter((result) => !result.ok)) {
    console.error("APNs delivery failed", {
      eventID: event.id,
      deviceID: result.deviceID,
      status: result.status,
      reason: result.reason,
    });
  }

  return json({
    ok: delivered > 0,
    delivered,
    attempted: results.length,
    invalidDevicesRemoved: invalidDeviceIDs.length,
  }, delivered > 0 ? 200 : 502);
});
