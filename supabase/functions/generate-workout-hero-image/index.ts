
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type WorkoutHeroRecipe = {
  palette: string;
  scene: string;
  light: string;
  motif: string;
  energy: string;
  variant: number;
};

type WorkoutHeroContext = {
  activity?: string;
  durationSeconds?: number;
  distanceMeters?: number | null;
  elevationGainMeters?: number | null;
  routePointCount?: number;
  startHour?: number;
};

type RequestBody = {
  workoutId?: string;
  context?: WorkoutHeroContext;
  recipe?: WorkoutHeroRecipe;
};

const MODEL = "@cf/black-forest-labs/flux-2-klein-4b";
const PROMPT_VERSION = "flux2-klein-v1";
const BUCKET = "workout-hero-images";
const SIGNED_URL_SECONDS = 60 * 60 * 24 * 7;

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

function cleanText(value: unknown, maxLength: number): string {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

function finiteNumber(value: unknown, min: number, max: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.max(min, Math.min(max, value));
}

function normalizeRecipe(recipe: WorkoutHeroRecipe | undefined): WorkoutHeroRecipe {
  const palettes = new Set(["sage", "ocean", "amber", "violet", "rose", "slate"]);
  const scenes = new Set(["coast", "forest", "city", "track", "mountain", "studio"]);
  const lights = new Set(["sunrise", "daylight", "golden_hour", "dusk"]);
  const motifs = new Set(["route", "waves", "steps", "pulse", "streak", "group"]);
  const energies = new Set(["calm", "steady", "energetic"]);

  return {
    palette: palettes.has(recipe?.palette ?? "") ? recipe!.palette : "sage",
    scene: scenes.has(recipe?.scene ?? "") ? recipe!.scene : "mountain",
    light: lights.has(recipe?.light ?? "") ? recipe!.light : "daylight",
    motif: motifs.has(recipe?.motif ?? "") ? recipe!.motif : "route",
    energy: energies.has(recipe?.energy ?? "") ? recipe!.energy : "steady",
    variant: Math.max(1, Math.min(4, Math.round(recipe?.variant ?? 1))),
  };
}

function normalizeContext(context: WorkoutHeroContext | undefined) {
  const source = context ?? {};
  return {
    activity: cleanText(source.activity, 40) || "outdoor workout",
    durationSeconds: finiteNumber(source.durationSeconds, 0, 86400) ?? 0,
    distanceMeters: finiteNumber(source.distanceMeters, 0, 500000),
    elevationGainMeters: finiteNumber(source.elevationGainMeters, 0, 20000),
    routePointCount: finiteNumber(source.routePointCount, 0, 200000) ?? 0,
    startHour: finiteNumber(source.startHour, 0, 23) ?? 12,
  };
}

function scenePhrase(recipe: WorkoutHeroRecipe): string {
  switch (recipe.scene) {
    case "coast":
      return "a dramatic Nordic lakeside or coastal trail with open water, natural terrain and distant mountains";
    case "forest":
      return "a premium Scandinavian forest trail with depth, soft vegetation, rolling terrain and distant hills";
    case "city":
      return "a clean modern Nordic city running environment with waterfront paths, restrained architecture and atmospheric depth";
    case "track":
      return "an elegant outdoor athletics environment with open landscape, subtle track geometry and distant natural scenery";
    case "studio":
      return "a refined contemporary athletic environment with premium architectural light and subtle training atmosphere";
    case "mountain":
    default:
      return "a cinematic Nordic mountain valley with a winding trail, layered ridgelines, lake or river details and atmospheric depth";
  }
}

function lightPhrase(light: string): string {
  switch (light) {
    case "sunrise":
      return "fresh early-morning sunrise light, cool air, warm low sun and soft mist";
    case "golden_hour":
      return "rich golden-hour light, long soft shadows and warm highlights";
    case "dusk":
      return "premium blue-hour dusk light with subtle warm horizon glow";
    case "daylight":
    default:
      return "bright natural daylight with soft directional sun and crisp but gentle contrast";
  }
}

function buildPrompt(
  context: ReturnType<typeof normalizeContext>,
  recipe: WorkoutHeroRecipe,
): string {
  const distance =
    context.distanceMeters != null
      ? `${(context.distanceMeters / 1000).toFixed(1)} km`
      : "an outdoor";

  const ascent =
    context.elevationGainMeters != null
      ? ` with about ${Math.round(context.elevationGainMeters)} metres of climbing`
      : "";

  const energy =
    recipe.energy === "energetic"
      ? "dynamic, athletic and energetic"
      : recipe.energy === "calm"
      ? "calm, controlled and spacious"
      : "steady, flowing and athletic";

  return [
    "Photorealistic premium editorial fitness landscape photograph.",
    `Scene: ${scenePhrase(recipe)}.`,
    `Lighting: ${lightPhrase(recipe.light)}.`,
    `It should visually fit a ${distance} ${context.activity}${ascent}.`,
    `Mood: ${energy}.`,
    "Compose for a luxury iOS workout activity card in a bright Scandinavian visual language.",
    "Keep the central and right-middle area visually open so a glowing GPS route ribbon can be overlaid later by the app.",
    "Use believable terrain, realistic depth, atmospheric perspective, natural textures and high-end outdoor photography.",
    "No map tiles, no map labels, no street names, no UI, no typography, no logos, no watermarks, no charts.",
    "No identifiable person as the main subject. If tiny distant people appear, they must be incidental and anonymous.",
    "Do not draw a route line; the real route is added by ATHLTH after generation.",
    "Avoid fantasy, surrealism, impossible geography and illustration aesthetics.",
    "Landscape orientation, polished but natural, suitable behind readable white and dark overlay text.",
  ].join(" ");
}

function seedFromWorkoutID(workoutID: string): number {
  let hash = 2166136261;
  for (let index = 0; index < workoutID.length; index += 1) {
    hash ^= workoutID.charCodeAt(index);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash % 2147483647;
}

function decodeBase64(base64: string): Uint8Array {
  const normalized = base64.includes(",")
    ? base64.split(",").pop() ?? ""
    : base64;
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function cloudflareImage(payload: any): string | null {
  if (typeof payload?.result?.image === "string") return payload.result.image;
  if (typeof payload?.result === "string") return payload.result;
  if (typeof payload?.image === "string") return payload.image;
  return null;
}

async function signedImageURL(
  admin: ReturnType<typeof createClient>,
  storagePath: string,
): Promise<string | null> {
  const { data, error } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(storagePath, SIGNED_URL_SECONDS);

  if (error) {
    console.error("Unable to sign workout hero", {
      storagePath,
      message: error.message,
    });
    return null;
  }

  return data?.signedUrl ?? null;
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

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const workoutID = cleanText(body.workoutId, 64);
  if (!/^[0-9a-fA-F-]{36}$/.test(workoutID)) {
    return json({ error: "Invalid workout ID." }, 400);
  }

  const context = normalizeContext(body.context);
  const recipe = normalizeRecipe(body.recipe);

  const { data: existing, error: existingError } = await admin
    .from("workout_hero_assets")
    .select("status,storage_path,updated_at,attempts")
    .eq("user_id", user.id)
    .eq("workout_id", workoutID)
    .maybeSingle();

  if (existingError) {
    console.error("Workout hero lookup failed", {
      workoutID,
      userID: user.id,
      message: existingError.message,
    });
  }

  if (existing?.status === "ready" && existing.storage_path) {
    const imageURL = await signedImageURL(admin, existing.storage_path);
    if (imageURL) {
      return json({ status: "ready", imageURL, cached: true });
    }
  }

  if (existing?.status === "generating" && existing.updated_at) {
    const age = Date.now() - new Date(existing.updated_at).getTime();
    if (Number.isFinite(age) && age >= 0 && age < 5 * 60 * 1000) {
      return json({ status: "processing", cached: false });
    }
  }

  if (!existing) {
    const utcDayStart =
      new Date();
    utcDayStart.setUTCHours(0, 0, 0, 0);

    const { count: userDailyCount } =
      await admin
        .from("workout_hero_assets")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq("user_id", user.id)
        .gte(
          "created_at",
          utcDayStart.toISOString(),
        );

    if ((userDailyCount ?? 0) >= 6) {
      return json(
        {
          status: "rate_limited",
          reason:
            "daily_user_generation_limit",
        },
        429,
      );
    }

    const { count: globalDailyCount } =
      await admin
        .from("workout_hero_assets")
        .select("id", {
          count: "exact",
          head: true,
        })
        .gte(
          "created_at",
          utcDayStart.toISOString(),
        );

    if ((globalDailyCount ?? 0) >= 80) {
      return json(
        {
          status: "rate_limited",
          reason:
            "daily_service_generation_limit",
        },
        429,
      );
    }
  }

  const cloudflareAccountID = Deno.env.get("CLOUDFLARE_ACCOUNT_ID");
  const cloudflareToken = Deno.env.get("CLOUDFLARE_API_TOKEN");

  if (!cloudflareAccountID || !cloudflareToken) {
    return json(
      {
        status: "unconfigured",
        reason: "cloudflare_credentials_missing",
      },
      503,
    );
  }

  const { error: claimError } = await admin
    .from("workout_hero_assets")
    .upsert(
      {
        user_id: user.id,
        workout_id: workoutID,
        status: "generating",
        model: MODEL,
        prompt_version: PROMPT_VERSION,
        recipe,
        attempts: (existing?.attempts ?? 0) + 1,
        last_error: null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,workout_id" },
    );

  if (claimError) {
    console.error("Unable to claim workout hero generation", {
      workoutID,
      userID: user.id,
      message: claimError.message,
    });
    return json({ status: "failed", reason: "generation_claim_failed" }, 500);
  }

  const prompt = buildPrompt(context, recipe);

  const form = new FormData();
  form.append("prompt", prompt);
  form.append("width", "1024");
  form.append("height", "768");
  form.append("guidance", "3.5");
  form.append("seed", String(seedFromWorkoutID(workoutID)));

  const endpoint =
    `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(
      cloudflareAccountID,
    )}/ai/run/${MODEL}`;

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${cloudflareToken}`,
      },
      body: form,
    });

    const payload = await response.json();

    if (!response.ok) {
      const message = JSON.stringify(payload).slice(0, 1200);
      console.error("Cloudflare workout hero failed", {
        workoutID,
        status: response.status,
        body: message,
      });

      await admin
        .from("workout_hero_assets")
        .update({
          status: "failed",
          last_error: `Cloudflare ${response.status}: ${message}`,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", user.id)
        .eq("workout_id", workoutID);

      return json({ status: "failed", reason: "image_generation_failed" }, 502);
    }

    const base64 = cloudflareImage(payload);
    if (!base64) {
      await admin
        .from("workout_hero_assets")
        .update({
          status: "failed",
          last_error: "Cloudflare response contained no image.",
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", user.id)
        .eq("workout_id", workoutID);

      return json({ status: "failed", reason: "image_missing_from_response" }, 502);
    }

    const imageBytes = decodeBase64(base64);
    const storagePath =
      `${user.id}/${workoutID}/${PROMPT_VERSION}.png`;

    const { error: uploadError } = await admin.storage
      .from(BUCKET)
      .upload(storagePath, imageBytes, {
        contentType: "image/png",
        cacheControl: "31536000",
        upsert: true,
      });

    if (uploadError) throw uploadError;

    const { error: readyError } = await admin
      .from("workout_hero_assets")
      .update({
        status: "ready",
        storage_path: storagePath,
        model: MODEL,
        prompt_version: PROMPT_VERSION,
        recipe,
        last_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", user.id)
      .eq("workout_id", workoutID);

    if (readyError) throw readyError;

    const imageURL = await signedImageURL(admin, storagePath);

    return json({
      status: "ready",
      imageURL,
      cached: false,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    console.error("Workout hero generation crashed", {
      workoutID,
      userID: user.id,
      message,
    });

    await admin
      .from("workout_hero_assets")
      .update({
        status: "failed",
        last_error: message.slice(0, 1200),
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", user.id)
      .eq("workout_id", workoutID);

    return json({ status: "failed", reason: "generation_error" }, 502);
  }
});
