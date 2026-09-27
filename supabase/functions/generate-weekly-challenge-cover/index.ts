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

const coverSchema = {
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

function cleanText(value: unknown, maxLength: number): string {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

function extractOutputText(payload: any): string | null {
  if (typeof payload?.output_text === "string") return payload.output_text;

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
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseURL || !serviceRoleKey) return;

    const parseHeader = (name: string) => {
      const raw = response.headers.get(name);
      if (!raw) return null;
      const value = Number(raw);
      return Number.isFinite(value)
        ? Math.max(0, Math.round(value))
        : null;
    };

    const limitRequests = parseHeader("x-ratelimit-limit-requests");
    const remainingRequests = parseHeader("x-ratelimit-remaining-requests");
    const resetRequests = response.headers.get("x-ratelimit-reset-requests");

    if (limitRequests == null && remainingRequests == null) return;

    const admin = createClient(supabaseURL, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { error } = await admin
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

    if (error) {
      console.error("Unable to record AI quota", {
        feature,
        message: error.message,
      });
    }
  } catch (error) {
    console.error("AI quota telemetry skipped", {
      feature,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

function fallbackRecipe(kind: string) {
  switch (kind) {
    case "sessions":
      return {
        palette: "violet",
        scene: "track",
        light: "daylight",
        motif: "group",
        energy: "energetic",
        variant: 2,
      };
    case "minutes":
      return {
        palette: "ocean",
        scene: "coast",
        light: "golden_hour",
        motif: "pulse",
        energy: "steady",
        variant: 3,
      };
    case "streak":
      return {
        palette: "amber",
        scene: "forest",
        light: "sunrise",
        motif: "streak",
        energy: "steady",
        variant: 4,
      };
    case "distance":
    default:
      return {
        palette: "sage",
        scene: "mountain",
        light: "daylight",
        motif: "route",
        energy: "steady",
        variant: 1,
      };
  }
}

function coverAsset(recipe: Record<string, unknown>): string {
  const params = new URLSearchParams();
  for (const key of [
    "palette",
    "scene",
    "light",
    "motif",
    "energy",
    "variant",
  ]) {
    params.set(key, String(recipe[key] ?? ""));
  }

  return `athlth-cover://v1?${params.toString()}`;
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
  const groqKey = Deno.env.get("GROQ_API_KEY");

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
    .select("id,title,subtitle,kind,target_value")
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

  let recipe = fallbackRecipe(challenge.kind);
  let generatedByGroq = false;

  if (groqKey) {
    const instructions = `
You are ATHLTH visual art direction AI.
Choose a structured visual recipe for one premium weekly fitness challenge cover.

The app itself renders the artwork from your recipe. You are not generating pixels.

Goals:
- Match the challenge concept, type and target.
- Keep the result bright, premium, modern and Scandinavian.
- Vary the look from generic Community branding.
- Prefer tasteful fitness/outdoor visual language.
- Do not include text, logos, typography or medical imagery.
- Pick only values from the provided JSON schema.
`.trim();

    const aiResponse = await fetch(
      "https://api.groq.com/openai/v1/responses",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${groqKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model:
            Deno.env.get("GROQ_TRAINING_MODEL") ??
            "openai/gpt-oss-120b",
          reasoning: { effort: "low" },
          instructions,
          input: JSON.stringify({
            title: cleanText(challenge.title, 120),
            subtitle: cleanText(challenge.subtitle, 240),
            kind: cleanText(challenge.kind, 40),
            targetValue: Number(challenge.target_value),
          }),
          text: {
            format: {
              type: "json_schema",
              name: "athlth_weekly_cover_recipe",
              strict: true,
              schema: coverSchema,
            },
          },
        }),
      },
    );

    await recordGroqQuota(aiResponse, "weekly-cover");

    if (aiResponse.ok) {
      try {
        const payload = await aiResponse.json();
        const outputText = extractOutputText(payload);
        if (outputText) {
          const parsed = JSON.parse(outputText);
          recipe = parsed;
          generatedByGroq = true;
        }
      } catch (error) {
        console.error("Unable to parse Groq cover recipe", {
          challengeId,
          userID: user.id,
          message: error instanceof Error ? error.message : String(error),
        });
      }
    } else {
      const failure = await aiResponse.text();
      console.error("Groq weekly cover direction failed", {
        challengeId,
        userID: user.id,
        status: aiResponse.status,
        body: failure.slice(0, 1200),
      });
    }
  }

  const heroAsset = coverAsset(recipe);

  const { error: updateError } = await admin
    .from("official_weekly_challenges")
    .update({
      hero_asset: heroAsset,
      updated_at: new Date().toISOString(),
    })
    .eq("id", challenge.id);

  if (updateError) {
    console.error("Weekly challenge cover recipe update failed", {
      challengeId,
      message: updateError.message,
    });
    return json({
      generated: false,
      reason: "challenge_update_failed",
    });
  }

  return json({
    generated: true,
    generatedByGroq,
    heroAsset,
  });
});
