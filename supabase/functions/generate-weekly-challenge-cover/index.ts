import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type CoverRequest = {
  challengeId?: string;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function visualDirection(kind: string): string {
  switch (kind) {
    case "sessions":
      return "Show a small group of generic adult runners and walkers preparing for or finishing a training session, conveying repeat participation and consistency.";
    case "minutes":
      return "Show sustained outdoor movement with one or two generic adult runners or walkers in a flowing, energetic scene that communicates time spent moving.";
    case "streak":
      return "Show a calm but motivating dawn or early-evening run/walk scene that communicates daily consistency and momentum.";
    case "distance":
    default:
      return "Show one or two generic adult runners or walkers moving through an aspirational outdoor route, clearly communicating distance and forward progress.";
  }
}

function cleanText(value: unknown, maxLength: number): string {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Missing authenticated user." }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const openAIKey = Deno.env.get("OPENAI_API_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "ATHLTH backend is unavailable." }, 503);
  }

  const token = authorization.slice(7).trim();
  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: userError } = await admin.auth.getUser(token);
  if (userError || !user) {
    return json({ error: "Your sign-in session is no longer valid." }, 401);
  }

  const { data: roleRow, error: roleError } = await admin
    .from("account_roles")
    .select("role")
    .eq("user_id", user.id)
    .maybeSingle();

  if (roleError || !roleRow || !["admin", "owner"].includes(roleRow.role)) {
    return json({ error: "Admin access required." }, 403);
  }

  let body: CoverRequest = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const challengeId = cleanText(body.challengeId, 64);
  if (!challengeId) {
    return json({ error: "Missing challenge ID." }, 400);
  }

  const { data: challenge, error: challengeError } = await admin
    .from("official_weekly_challenges")
    .select("id,title,subtitle,kind,target_value,hero_asset")
    .eq("id", challengeId)
    .maybeSingle();

  if (challengeError) {
    console.error("Unable to load challenge for cover generation", {
      message: challengeError.message,
      challengeId,
      userID: user.id,
    });
    return json({ error: "Unable to load the challenge." }, 500);
  }

  if (!challenge) {
    return json({ error: "Challenge not found." }, 404);
  }

  // Image generation is optional infrastructure. Never make creating or
  // editing a weekly challenge depend on it.
  if (!openAIKey) {
    console.warn("Weekly challenge cover skipped: OPENAI_API_KEY is not configured.", {
      challengeId,
    });
    return json({
      generated: false,
      reason: "image_ai_not_configured",
    });
  }

  const title = cleanText(challenge.title, 120);
  const subtitle = cleanText(challenge.subtitle, 240);
  const target = Number(challenge.target_value);
  const targetLabel = Number.isFinite(target)
    ? `${target} ${challenge.kind === "distance" ? "kilometres" : challenge.kind === "minutes" ? "minutes" : challenge.kind === "sessions" ? "sessions" : "days"}`
    : "the weekly target";

  const prompt = `
Create one premium editorial fitness cover photograph for the ATHLTH app's official weekly community challenge.

Challenge:
- Title concept: ${title}
- Description: ${subtitle}
- Challenge type: ${challenge.kind}
- Target concept: ${targetLabel}

Visual direction:
${visualDirection(challenge.kind)}

Brand/art direction:
- Bright, premium, modern Scandinavian wellness and fitness aesthetic.
- Natural-looking photography, soft daylight, sophisticated neutral palette with gentle warmth.
- Aspirational but believable, inclusive generic adult athletes, no celebrities or recognizable public figures.
- Wide landscape composition for a mobile card.
- Keep useful negative space on the left/top-left so ATHLTH can overlay title and challenge information.
- The image itself must contain NO words, letters, typography, numbers, logos, brand marks, UI, badges, borders, watermarks, charts, or route labels.
- Do not visually show unsafe maximal effort, injury, medical treatment, or extreme weather.
- Do not copy the Community tab hero artwork; this cover must feel unique to this challenge.
`.trim();

  const imageResponse = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_IMAGE_MODEL") ?? "gpt-image-2.5-sunburst",
      prompt,
      size: "1536x1024",
      quality: "low",
    }),
  });

  if (!imageResponse.ok) {
    const failure = await imageResponse.text();
    console.error("Weekly challenge image generation failed", {
      challengeId,
      status: imageResponse.status,
      body: failure.slice(0, 1200),
      userID: user.id,
    });

    return json({
      generated: false,
      reason: "image_generation_failed",
    });
  }

  const imagePayload = await imageResponse.json();
  const base64Image = imagePayload?.data?.[0]?.b64_json;

  if (typeof base64Image !== "string" || base64Image.length < 100) {
    console.error("Weekly challenge image response had no usable image.", {
      challengeId,
      userID: user.id,
    });
    return json({
      generated: false,
      reason: "image_generation_empty",
    });
  }

  const imageBytes = decodeBase64(base64Image);
  const bucket = "official-weekly-challenge-covers";
  const objectPath = `${challenge.id}/${Date.now()}-${crypto.randomUUID()}.png`;

  const { error: uploadError } = await admin.storage
    .from(bucket)
    .upload(objectPath, imageBytes, {
      contentType: "image/png",
      cacheControl: "31536000",
      upsert: false,
    });

  if (uploadError) {
    console.error("Weekly challenge cover upload failed", {
      challengeId,
      message: uploadError.message,
    });
    return json({
      generated: false,
      reason: "cover_upload_failed",
    });
  }

  const { data: publicURLData } = admin.storage
    .from(bucket)
    .getPublicUrl(objectPath);

  const heroAsset = publicURLData.publicUrl;

  const { error: updateError } = await admin
    .from("official_weekly_challenges")
    .update({
      hero_asset: heroAsset,
      updated_at: new Date().toISOString(),
    })
    .eq("id", challenge.id);

  if (updateError) {
    await admin.storage.from(bucket).remove([objectPath]);

    console.error("Weekly challenge cover URL update failed", {
      challengeId,
      message: updateError.message,
    });
    return json({
      generated: false,
      reason: "challenge_update_failed",
    });
  }

  const previousHero = cleanText(challenge.hero_asset, 2000);
  const marker = `/storage/v1/object/public/${bucket}/`;
  const markerIndex = previousHero.indexOf(marker);

  if (markerIndex >= 0 && previousHero !== heroAsset) {
    const previousPath = decodeURIComponent(
      previousHero.slice(markerIndex + marker.length).split("?")[0],
    );
    if (previousPath) {
      const { error: cleanupError } = await admin.storage
        .from(bucket)
        .remove([previousPath]);
      if (cleanupError) {
        console.warn("Unable to remove previous weekly challenge cover", {
          challengeId,
          message: cleanupError.message,
        });
      }
    }
  }

  return json({
    generated: true,
    heroAsset,
  });
});
