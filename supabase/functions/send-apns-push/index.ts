import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type InboxEvent = {
  id: string;
  recipient_id: string;
  actor_id: string | null;
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
  language_code: "en" | "nb" | null;
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
  if (event.entity_type === "community_event" && event.entity_id) {
    return `community_event:${event.entity_id}`;
  }

  if (event.actor_id) {
    return `person:${event.actor_id}`;
  }

  if (event.entity_type && event.entity_id) {
    return `${event.entity_type}:${event.entity_id}`;
  }

  return event.kind;
}

function localizedAlert(
  event: InboxEvent,
  languageCode: string | null | undefined,
  actorName?: string | null,
  actorUnreadCount = 1,
): { title: string; body: string } {
  const isCommunityEventCancellation =
    event.entity_type === "community_event" &&
    event.title === "Event cancelled";

  if (actorName && actorUnreadCount > 1 && !isCommunityEventCancellation) {
    if (languageCode === "nb") {
      return {
        title: actorName,
        body: `${actorName} sendte deg ${actorUnreadCount} nye ting.`,
      };
    }

    return {
      title: actorName,
      body: `${actorName} sent you ${actorUnreadCount} new items.`,
    };
  }
  if (languageCode !== "nb") {
    return {
      title: event.title,
      body: event.message,
    };
  }

  const kind = event.kind.toLowerCase();
  let title = event.title;
  let body = event.message;

  const replaceSuffix = (
    value: string,
    english: string,
    norwegian: string,
  ) => value.endsWith(english)
    ? value.slice(0, -english.length) + norwegian
    : value;

  switch (kind) {
    case "friend_request":
    case "follow_request":
      title = "Ny følgeforespørsel";
      body = replaceSuffix(
        body,
        " wants to follow you on ATHLTH.",
        " vil følge deg på ATHLTH.",
      );
      break;

    case "friend_accepted":
    case "follow_accepted":
      title = "Følgeforespørsel godkjent";
      body = replaceSuffix(
        body,
        " accepted your follow request.",
        " godkjente følgeforespørselen din.",
      );
      break;

    case "challenge_invite":
      title = "Ny challenge";
      body = body.replace(
        " challenged you: ",
        " utfordret deg: ",
      );
      break;

    case "challenge_accepted":
      title = "Challenge godtatt";
      body = body.replace(
        " accepted ",
        " godtok ",
      );
      break;

    case "challenge_declined":
      title = "Challenge avslått";
      body = body.replace(
        " declined ",
        " avslo ",
      );
      break;

    case "challenge_withdrawn":
      title = "Challenge trukket tilbake";
      body = body.replace(
        " withdrew ",
        " trakk tilbake ",
      );
      break;

    case "challenge_result": {
      title = "Nytt challenge-resultat";
      const match = body.match(
        /^(.+?) posted (.+) in (.+)\.$/,
      );
      if (match) {
        body = `${match[1]} registrerte ${match[2]} i ${match[3]}.`;
      }
      break;
    }

    case "reaction":
      title = "Ny reaksjon";
      body = replaceSuffix(
        body,
        " reacted to your ATHLTH activity.",
        " reagerte på ATHLTH-aktiviteten din.",
      );
      break;

    case "workout_invite":
      title = "Tren sammen";
      body = body.replace(
        " invited you to train together: ",
        " inviterte deg til å trene sammen: ",
      );
      break;

    case "workout_invite_accepted":
      if (event.title === "Workout starting") {
        title = "Økten starter";
        body = "Tren sammen-økten din starter nå.";
      } else {
        title = "Treningspartner ble med";
        body = body.replace(
          " accepted your invite for ",
          " godtok invitasjonen din til ",
        );
      }
      break;

    case "message":
      if (body === "Shared something with you") {
        body = "Delte noe med deg";
      }
      break;

    case "message_request":
      if (title.startsWith("Message request from ")) {
        title = `Meldingsforespørsel fra ${title.slice(
          "Message request from ".length,
        )}`;
      } else {
        title = "Meldingsforespørsel";
      }
      if (body === "Shared something with you") {
        body = "Delte noe med deg";
      }
      break;

    case "message_request_accepted":
      title = "Meldingsforespørsel godtatt";
      body = replaceSuffix(
        body,
        " accepted your message request.",
        " godtok meldingsforespørselen din.",
      );
      break;

    case "mention":
      title = "Du ble nevnt";
      body = body
        .replace(
          " mentioned you in a message.",
          " nevnte deg i en melding.",
        )
        .replace(
          " mentioned you in ",
          " nevnte deg i ",
        );
      break;

    case "group_message":
      // The title is the Club name and the body contains user-authored text.
      break;

    case "group_update":
      if (title.endsWith(" update")) {
        title = `Oppdatering · ${title.slice(0, -" update".length)}`;
      }
      // Announcement text is user-authored and should not be translated.
      break;

    case "group_event":
      if (title.startsWith("New event in ")) {
        title = `Nytt event i ${title.slice("New event in ".length)}`;
      } else if (title === "Event cancelled") {
        title = "Arrangement avlyst";

        const cancelled = body.match(
          /^(.+) has been cancelled\.$/,
        );
        if (cancelled) {
          body = `${cancelled[1]} er avlyst.`;
        }
      } else if (title === "Event updated") {
        title = "Event oppdatert";
      } else if (title === "You have a spot") {
        title = "Du har fått plass";
      }

      body = replaceSuffix(
        body,
        " has important changes.",
        " har viktige endringer.",
      );

      {
        const match = body.match(
          /^A spot opened up for (.+)\. You are now going\.$/,
        );
        if (match) {
          body = `Det ble ledig plass på ${match[1]}. Du er nå påmeldt.`;
        }
      }
      break;

    case "group_challenge":
      if (title.startsWith("New challenge in ")) {
        title = `Ny challenge i ${title.slice("New challenge in ".length)}`;
      } else if (title === "Challenge cancelled") {
        title = "Challenge avlyst";
      } else if (title === "Challenge updated") {
        title = "Challenge oppdatert";
      }

      body = replaceSuffix(
        body,
        " has important changes.",
        " har viktige endringer.",
      );
      break;

    case "group_invite":
      title = "Gruppeinvitasjon";
      if (
        body.startsWith("You were invited to ") &&
        body.endsWith(".")
      ) {
        body = `Du ble invitert til ${body.slice(
          "You were invited to ".length,
        )}`;
      }
      break;

    case "group_join_request":
      title = "Ny forespørsel om medlemskap";
      body = replaceSuffix(
        body,
        " has a new membership request.",
        " har en ny forespørsel om medlemskap.",
      );
      break;

    case "group_join_approved":
      if (title.startsWith("You joined ")) {
        title = `Du ble med i ${title.slice("You joined ".length)}`;
      }
      if (body === "Your membership request was approved.") {
        body = "Forespørselen om medlemskap ble godkjent.";
      }
      break;

    default:
      break;
  }

  return { title, body };
}

async function sendToDevice(
  device: NotificationDevice,
  event: InboxEvent,
  unreadCount: number,
  authToken: string,
  actorName?: string | null,
  actorUnreadCount = 1,
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

  const alert = localizedAlert(
    event,
    device.language_code,
    actorName,
    actorUnreadCount,
  );

  const payload = {
    aps: {
      alert,
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
        "apns-collapse-id": event.actor_id ?? event.id,
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

  // These are Apple Developer identifiers, not secrets. Keeping them
  // explicit prevents a stale/mismatched environment value from producing
  // an invalid APNs provider token. The private .p8 key remains secret.
  const keyID = "AUYD5QP5AN";
  const teamID = "D3AX7B6RMW";
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

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
      "id,recipient_id,actor_id,kind,title,message,entity_type,entity_id,push_notified_at",
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

  const mandatoryCommunityEventCancellation =
    event.entity_type === "community_event" &&
    event.title === "Event cancelled";

  if (
    !mandatoryCommunityEventCancellation &&
    !preferenceAllows(event.kind, preferences ?? null)
  ) {
    await admin
      .from("social_inbox_events")
      .update({ push_notified_at: new Date().toISOString() })
      .eq("id", event.id);

    return json({ ok: true, skipped: "user_preference" });
  }

  let actorUnreadCount = 1;
  let actorName: string | null = null;

  if (event.actor_id) {
    const [{ count: sameActorCount }, { data: actorProfile }] =
      await Promise.all([
        admin
          .from("social_inbox_events")
          .select("id", { count: "exact", head: true })
          .eq("recipient_id", event.recipient_id)
          .eq("actor_id", event.actor_id)
          .is("read_at", null),
        admin
          .from("social_profile_cards")
          .select("display_name,username")
          .eq("user_id", event.actor_id)
          .maybeSingle<{ display_name: string | null; username: string | null }>(),
      ]);

    actorUnreadCount = Math.max(sameActorCount ?? 1, 1);
    actorName =
      actorProfile?.display_name?.trim() ||
      actorProfile?.username?.trim() ||
      null;
  }

  const { data: devices, error: deviceError } = await admin
    .from("notification_devices")
    .select("id,app_bundle_id,apns_environment,apns_token,language_code")
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
        actorName,
        actorUnreadCount,
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
