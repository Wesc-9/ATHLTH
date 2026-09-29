import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type WorkoutHeroContext = {
  activity?: string;
  durationSeconds?: number;
  distanceMeters?: number | null;
  elevationGainMeters?: number | null;
  routePointCount?: number;
  startHour?: number;
};

type WorkoutHeroRequest = {
  context?: WorkoutHeroContext;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

const recipeSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "palette",
    "scene",
    "light",
    "motif",
    "energy",
    "variant",
  ],
  properties: {
    palette: {
      type: "string",
      enum: ["sage", "ocean", "amber", "violet", "rose", "slate"],
    },
    scene: {
      type: "string",
      enum: ["coast", "forest", "city", "track", "mountain", "studio"],
    },
    light: {
      type: "string",
      enum: ["sunrise", "daylight", "golden_hour", "dusk"],
    },
    motif: {
      type: "string",
      enum: ["route", "waves", "steps", "pulse", "streak", "group"],
    },
    energy: {
      type: "string",
      enum: ["calm", "steady", "energetic"],
    },
    variant: {
      type: "integer",
      minimum: 1,
      maximum: 4,
    },
  },
};

function finiteNumber(
  value: unknown,
  min: number,
  max: number,
): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }

  return Math.max(min, Math.min(max, value));
}

function sanitizeContext(input: WorkoutHeroContext | undefined) {
  const source = input ?? {};

  return {
    activity: String(source.activity ?? "").slice(0, 40),
    durationSeconds:
      finiteNumber(source.durationSeconds, 0, 86400) ?? 0,
    distanceMeters:
      finiteNumber(source.distanceMeters, 0, 500000),
    elevationGainMeters:
      finiteNumber(source.elevationGainMeters, 0, 20000),
    routePointCount:
      finiteNumber(source.routePointCount, 0, 200000) ?? 0,
    startHour:
      finiteNumber(source.startHour, 0, 23) ?? 12,
  };
}

function fallbackRecipe(context: ReturnType<typeof sanitizeContext>) {
  const hour = context.startHour;

  const light =
    hour >= 5 && hour < 10
      ? "sunrise"
      : hour >= 10 && hour < 17
      ? "daylight"
      : hour >= 17 && hour < 22
      ? "golden_hour"
      : "dusk";

  const activity = context.activity.toLowerCase();

  let scene = "mountain";
  if (activity.includes("walk")) {
    scene = hour >= 17 || hour < 6 ? "city" : "forest";
  } else if (activity.includes("cycl")) {
    scene = "coast";
  } else if (activity.includes("hik")) {
    scene = "mountain";
  } else if (context.routePointCount < 2) {
    scene = "track";
  }

  const distance = context.distanceMeters ?? 0;
  const energy =
    distance >= 10000 || (context.elevationGainMeters ?? 0) >= 250
      ? "energetic"
      : distance >= 4000
      ? "steady"
      : "calm";

  const palette =
    light === "sunrise"
      ? "sage"
      : light === "golden_hour"
      ? "amber"
      : light === "dusk"
      ? "slate"
      : scene === "coast"
      ? "ocean"
      : "sage";

  return {
    palette,
    scene,
    light,
    motif: context.routePointCount >= 2 ? "route" : "pulse",
    energy,
    variant:
      Math.max(
        1,
        Math.min(
          4,
          ((Math.round(distance / 100) + hour) % 4) + 1,
        ),
      ),
  };
}

function extractOutputText(payload: any): string | null {
  if (typeof payload?.output_text === "string") {
    return payload.output_text;
  }

  for (const item of payload?.output ?? []) {
    for (const content of item?.content ?? []) {
      if (
        content?.type === "output_text" &&
        typeof content?.text === "string"
      ) {
        return content.text;
      }
    }
  }

  return null;
}

async function recordGroqQuota(
  response: Response,
  feature: string,
) {
  try {
    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseURL || !serviceRoleKey) return;

    const parseHeader = (name: string) => {
      const raw = response.headers.get(name);
      if (!raw) return null;

      const value = Number(raw);
      return Number.isFinite(value)
        ? Math.max(0, Math.round(value))
        : null;
    };

    const limitRequests =
      parseHeader("x-ratelimit-limit-requests");
    const remainingRequests =
      parseHeader("x-ratelimit-remaining-requests");
    const resetRequests =
      response.headers.get(
        "x-ratelimit-reset-requests",
      );

    if (
      limitRequests == null &&
      remainingRequests == null
    ) {
      return;
    }

    const admin = createClient(
      supabaseURL,
      serviceRoleKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    await admin
      .from("ai_provider_quota_snapshots")
      .upsert(
        {
          provider: "groq",
          model:
            Deno.env.get("GROQ_TRAINING_MODEL") ??
            "openai/gpt-oss-120b",
          limit_requests: limitRequests,
          remaining_requests: remainingRequests,
          reset_requests: resetRequests,
          last_feature: feature,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "provider,model" },
      );
  } catch {
    // Visual direction remains non-blocking.
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json(
      { error: "Method not allowed." },
      405,
    );
  }

  const authorization =
    req.headers.get("Authorization");

  if (!authorization?.startsWith("Bearer ")) {
    return json(
      { error: "Missing authenticated user." },
      401,
    );
  }

  const supabaseURL =
    Deno.env.get("SUPABASE_URL");
  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return json(
      { error: "ATHLTH backend is unavailable." },
      503,
    );
  }

  const token =
    authorization.slice(7).trim();

  const admin = createClient(
    supabaseURL,
    serviceRoleKey,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );

  const {
    data: { user },
    error: userError,
  } = await admin.auth.getUser(token);

  if (userError || !user) {
    return json(
      { error: "Invalid sign-in session." },
      401,
    );
  }

  let body: WorkoutHeroRequest = {};

  try {
    body = await req.json();
  } catch {
    return json(
      { error: "Invalid request body." },
      400,
    );
  }

  const context =
    sanitizeContext(body.context);

  let recipe =
    fallbackRecipe(context);
  let generatedByGroq = false;

  const groqKey =
    Deno.env.get("GROQ_API_KEY");

  if (groqKey) {
    const instructions = `
You are ATHLTH visual art direction AI.

Create one premium scenic hero direction for a fitness activity card.
The iPhone app renders the final scene and overlays the athlete's actual
route shape. You are choosing the visual direction, not writing copy.

The result should feel like a high-end editorial outdoor fitness image:
- bright, premium, cinematic and modern
- a clear sense of movement through landscape
- route-friendly negative space through the middle/right of the scene
- no map labels, streets, UI, logos, text or medical imagery
- no people as the main subject
- running and hiking should usually feel outdoors
- walking may use city, forest or coast
- cycling often suits coast, mountain or open-road atmosphere
- higher elevation should bias toward mountain/forest
- morning should feel fresh; evening may use golden-hour or dusk
- choose only values allowed by the JSON schema
- vary the composition so repeated workouts do not look identical
`.trim();

    const response = await fetch(
      "https://api.groq.com/openai/v1/responses",
      {
        method: "POST",
        headers: {
          "Authorization":
            `Bearer ${groqKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model:
            Deno.env.get(
              "GROQ_TRAINING_MODEL",
            ) ??
            "openai/gpt-oss-120b",
          reasoning: { effort: "low" },
          instructions,
          input: JSON.stringify(context),
          text: {
            format: {
              type: "json_schema",
              name: "athlth_workout_hero_recipe",
              strict: true,
              schema: recipeSchema,
            },
          },
        }),
      },
    );

    await recordGroqQuota(
      response,
      "workout-hero",
    );

    if (response.ok) {
      try {
        const payload =
          await response.json();
        const outputText =
          extractOutputText(payload);

        if (outputText) {
          recipe =
            JSON.parse(outputText);
          generatedByGroq = true;
        }
      } catch {
        // Deterministic visual fallback remains valid.
      }
    }
  }

  return json({
    recipe,
    generatedByGroq,
  });
});
