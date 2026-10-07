import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type RequestBody = {
  purpose?: string;
  entity_id?: string;
  parent_id?: string;
  group_id?: string;
  content_kind?: string;
  image_base64?: string;
};

type ModerationResult = {
  decision: "approved" | "rejected" | "review" | "unavailable";
  provider: string;
  categories: string[];
  reason?: string;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function cleanUUID(value: unknown): string | null {
  const text = String(value ?? "").trim().toLowerCase();
  return uuidPattern.test(text) ? text : null;
}

function base64ToBytes(raw: string): Uint8Array | null {
  try {
    const value = raw.includes(",") ? raw.split(",").pop() ?? "" : raw;
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
  }
  return btoa(binary);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

function isJPEG(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 4 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[bytes.length - 2] === 0xff &&
    bytes[bytes.length - 1] === 0xd9
  );
}

async function moderateWithOpenAI(
  dataURL: string,
): Promise<ModerationResult | null> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return null;

  const response = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "omni-moderation-latest",
      input: [
        {
          type: "image_url",
          image_url: { url: dataURL },
        },
      ],
    }),
  });

  if (!response.ok) {
    console.error("OpenAI image moderation failed", {
      status: response.status,
      body: (await response.text()).slice(0, 800),
    });
    return null;
  }

  const payload = await response.json();
  const result = payload?.results?.[0];
  if (!result) return null;

  const active = Object.entries(result.categories ?? {})
    .filter(([, value]) => value === true)
    .map(([key]) => key);

  if (!result.flagged) {
    return {
      decision: "approved",
      provider: "openai-omni-moderation",
      categories: [],
    };
  }

  const reject = new Set([
    "sexual",
    "sexual/minors",
    "violence/graphic",
    "self-harm/instructions",
    "self-harm/intent",
    "hate/threatening",
    "harassment/threatening",
  ]);

  const hardReject = active.some((category) => reject.has(category));

  return {
    decision: hardReject ? "rejected" : "review",
    provider: "openai-omni-moderation",
    categories: active,
    reason: hardReject ? "unsafe_public_image" : "uncertain_public_image",
  };
}

async function moderateWithGroq(
  dataURL: string,
): Promise<ModerationResult | null> {
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) return null;

  const prompt = `
You are a safety classifier for a public fitness/social app.
Analyze only the supplied image. Return JSON only.

Set each field to true only when the visual evidence supports it:
- explicit_sexual_or_nudity: explicit nudity, sexual activity, pornographic or strongly sexualized content.
- sexualized_minor_or_possible_minor: any sexualized person who is or may be under 18.
- graphic_gore: graphic wounds, gore, dismemberment, exposed organs, or similarly shocking injury imagery.
- self_harm: visible self-harm, suicide imagery, or imagery encouraging self-harm.
- hate_or_extremism: hateful symbols, extremist/terrorist propaganda, or content glorifying protected-class hatred.
- targeted_harassment: degrading or threatening imagery aimed at a specific person or protected group.
- illegal_goods_or_drug_sales: imagery clearly advertising illegal drugs, contraband, or prohibited weapon sales.
- uncertain: use true when the image is too ambiguous, obscured, low quality, or the age/context is uncertain in a way that affects safety.

Normal sportswear, swimwear, ordinary bare torso during exercise, tattoos, food, alcohol visible incidentally, medical equipment, non-graphic sports injuries, lawful outdoor activities, and standard fitness imagery are not violations by themselves.

Return exactly:
{
  "explicit_sexual_or_nudity": boolean,
  "sexualized_minor_or_possible_minor": boolean,
  "graphic_gore": boolean,
  "self_harm": boolean,
  "hate_or_extremism": boolean,
  "targeted_harassment": boolean,
  "illegal_goods_or_drug_sales": boolean,
  "uncertain": boolean,
  "confidence": number
}
`.trim();

  const response = await fetch(
    "https://api.groq.com/openai/v1/chat/completions",
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "qwen/qwen3.8-27b",
        temperature: 0,
        max_completion_tokens: 420,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              {
                type: "image_url",
                image_url: { url: dataURL },
              },
            ],
          },
        ],
      }),
    },
  );

  if (!response.ok) {
    console.error("Groq public-image moderation failed", {
      status: response.status,
      body: (await response.text()).slice(0, 800),
    });
    return null;
  }

  const payload = await response.json();
  const raw = payload?.choices?.[0]?.message?.content;
  if (typeof raw !== "string") return null;

  try {
    const parsed = JSON.parse(raw);
    const categories: string[] = [];
    const keys = [
      "explicit_sexual_or_nudity",
      "sexualized_minor_or_possible_minor",
      "graphic_gore",
      "self_harm",
      "hate_or_extremism",
      "targeted_harassment",
      "illegal_goods_or_drug_sales",
      "uncertain",
    ];
    for (const key of keys) {
      if (parsed?.[key] === true) categories.push(key);
    }

    const hardReject = [
      "explicit_sexual_or_nudity",
      "sexualized_minor_or_possible_minor",
      "graphic_gore",
      "self_harm",
      "hate_or_extremism",
    ].some((key) => categories.includes(key));

    const needsReview = [
      "targeted_harassment",
      "illegal_goods_or_drug_sales",
      "uncertain",
    ].some((key) => categories.includes(key));

    return {
      decision: hardReject ? "rejected" : needsReview ? "review" : "approved",
      provider: "groq-qwen-vision",
      categories,
      reason: hardReject
        ? "unsafe_public_image"
        : needsReview
          ? "uncertain_public_image"
          : undefined,
    };
  } catch {
    return null;
  }
}

async function authorizeGroupMember(
  admin: ReturnType<typeof createClient>,
  userID: string,
  groupID: string,
): Promise<boolean> {
  const { data: group } = await admin
    .from("community_groups")
    .select("creator_id")
    .eq("id", groupID)
    .maybeSingle();

  if (!group) return false;
  if (group.creator_id === userID) return true;

  const { data: membership } = await admin
    .from("community_group_members")
    .select("user_id")
    .eq("group_id", groupID)
    .eq("user_id", userID)
    .maybeSingle();

  return Boolean(membership);
}

async function authorizeGroup(
  admin: ReturnType<typeof createClient>,
  userID: string,
  groupID: string,
  allowContributor: boolean,
): Promise<boolean> {
  const { data: group } = await admin
    .from("community_groups")
    .select("creator_id,members_can_create_content")
    .eq("id", groupID)
    .maybeSingle();

  if (!group) return false;
  if (group.creator_id === userID) return true;

  const { data: membership } = await admin
    .from("community_group_members")
    .select("role")
    .eq("group_id", groupID)
    .eq("user_id", userID)
    .maybeSingle();

  const role = String(membership?.role ?? "");
  if (role === "owner" || role === "admin") return true;
  if (allowContributor && role === "contributor") return true;
  if (allowContributor && membership && group.members_can_create_content === true) {
    return true;
  }
  return false;
}

async function destinationFor(
  admin: ReturnType<typeof createClient>,
  userID: string,
  body: RequestBody,
): Promise<
  | { bucket: string; path: string; cacheControl: string }
  | null
> {
  const purpose = String(body.purpose ?? "");
  const entityID = cleanUUID(body.entity_id);
  const parentID = cleanUUID(body.parent_id);
  const groupID = cleanUUID(body.group_id);

  switch (purpose) {
    case "profile_avatar":
      return {
        bucket: "profile-avatars",
        path: `${userID}/avatar.jpg`,
        cacheControl: "3600",
      };
    case "profile_header":
      return {
        bucket: "profile-avatars",
        path: `${userID}/header.jpg`,
        cacheControl: "3600",
      };
    case "profile_gear":
      if (!entityID) return null;
      return {
        bucket: "profile-gear",
        path: `${userID}/${entityID}.jpg`,
        cacheControl: "3600",
      };
    case "workout_media":
      if (!entityID || !parentID) return null;
      return {
        bucket: "workout-media",
        path: `${userID}/${parentID}/${entityID}.jpg`,
        cacheControl: "60",
      };
    case "challenge_cover":
      if (!entityID) return null;
      return {
        bucket: "workout-media",
        path: `${userID}/challenge-covers/${entityID}.jpg`,
        cacheControl: "60",
      };
    case "event_cover":
      if (!entityID) return null;
      return {
        bucket: "workout-media",
        path: `${userID}/event-covers/${entityID}.jpg`,
        cacheControl: "60",
      };
    case "club_cover":
    case "club_header": {
      if (!groupID) return null;
      if (!(await authorizeGroup(admin, userID, groupID, false))) return null;
      return {
        bucket: "community-group-images",
        path: `${groupID}/${purpose === "club_cover" ? "cover.jpg" : "header.jpg"}`,
        cacheControl: "3600",
      };
    }
    case "club_content": {
      if (!groupID || !entityID) return null;
      const kind = String(body.content_kind ?? "");
      if (!["event", "events", "challenge", "challenges"].includes(kind)) {
        return null;
      }
      if (!(await authorizeGroup(admin, userID, groupID, true))) return null;
      return {
        bucket: "community-content-images",
        path: `${groupID}/${kind}/${entityID}/cover.jpg`,
        cacheControl: "3600",
      };
    }
    case "club_chat_message": {
      if (!groupID || !entityID) return null;
      if (!(await authorizeGroupMember(admin, userID, groupID))) return null;
      return {
        bucket: "community-content-images",
        path: `${groupID}/chat/${entityID}.jpg`,
        cacheControl: "3600",
      };
    }
    default:
      return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ status: "error", reason: "method_not_allowed" }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ status: "error", reason: "not_authenticated" }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return json({ status: "unavailable", reason: "backend_unavailable" });
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const token = authorization.slice(7).trim();
  const { data: { user }, error: userError } = await admin.auth.getUser(token);
  if (userError || !user) {
    return json({ status: "error", reason: "not_authenticated" }, 401);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ status: "error", reason: "invalid_body" }, 400);
  }

  const raw = String(body.image_base64 ?? "");
  const bytes = base64ToBytes(raw);
  if (!bytes || bytes.length === 0 || bytes.length > 8_000_000) {
    return json({ status: "rejected", reason: "invalid_image_size" });
  }
  if (!isJPEG(bytes)) {
    return json({ status: "rejected", reason: "invalid_image_format" });
  }

  const destination = await destinationFor(admin, user.id, body);
  if (!destination) {
    return json({ status: "error", reason: "not_authorized" }, 403);
  }

  const fifteenMinutesAgo = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count: recentCount } = await admin
    .from("public_media_moderation_events")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", fifteenMinutesAgo);

  if ((recentCount ?? 0) >= 30) {
    return json({ status: "review", reason: "rate_limited" });
  }

  const hash = await sha256Hex(bytes);
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const { data: cached } = await admin
    .from("public_media_moderation_events")
    .select("decision,provider,categories")
    .eq("user_id", user.id)
    .eq("image_hash", hash)
    .eq("decision", "approved")
    .gte("created_at", thirtyDaysAgo)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  let moderation: ModerationResult;
  if (cached) {
    moderation = {
      decision: "approved",
      provider: "cached",
      categories: Array.isArray(cached.categories) ? cached.categories : [],
    };
  } else {
    const dataURL = `data:image/jpeg;base64,${bytesToBase64(bytes)}`;
    moderation =
      (await moderateWithOpenAI(dataURL)) ??
      (await moderateWithGroq(dataURL)) ?? {
        decision: "unavailable",
        provider: "none",
        categories: [],
        reason: "moderation_unavailable",
      };

    await admin.from("public_media_moderation_events").insert({
      user_id: user.id,
      purpose: String(body.purpose ?? "").slice(0, 80),
      entity_id: body.entity_id ? String(body.entity_id).slice(0, 120) : null,
      image_hash: hash,
      decision: moderation.decision,
      provider: moderation.provider,
      categories: moderation.categories,
      reason: moderation.reason ?? null,
    });
  }

  if (moderation.decision !== "approved") {
    return json({
      status: moderation.decision,
      reason: moderation.reason ?? "image_not_approved",
    });
  }

  const { error: uploadError } = await admin.storage
    .from(destination.bucket)
    .upload(destination.path, bytes, {
      contentType: "image/jpeg",
      cacheControl: destination.cacheControl,
      upsert: true,
    });

  if (uploadError) {
    console.error("Approved public image upload failed", {
      userID: user.id,
      purpose: body.purpose,
      bucket: destination.bucket,
      path: destination.path,
      message: uploadError.message,
    });
    return json({ status: "unavailable", reason: "storage_failed" });
  }

  const { data } = admin.storage
    .from(destination.bucket)
    .getPublicUrl(destination.path);

  const baseURL = data.publicUrl;
  const separator = baseURL.includes("?") ? "&" : "?";

  return json({
    status: "published",
    url: `${baseURL}${separator}v=${Date.now()}`,
    storage_path: destination.path,
  });
});
