import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type Segment = {
  label?: string;
  durationSeconds?: number;
  distanceMeters?: number;
  elevationGainMeters?: number;
  elevationLossMeters?: number;
  averageHeartRateBPM?: number | null;
  maxHeartRateBPM?: number | null;
  paceSecondsPerKilometer?: number | null;
};

type WorkoutContext = {
  activity?: string;
  durationSeconds?: number;
  distanceMeters?: number | null;
  activeEnergyKilocalories?: number | null;
  averageHeartRateBPM?: number | null;
  maxHeartRateBPM?: number | null;
  personalMaximumHeartRateBPM?: number | null;
  elevationGainMeters?: number | null;
  routePointCount?: number;
  averagePaceSecondsPerKilometer?: number | null;
  averageRunningPowerWatts?: number | null;
  averageRunningStrideLengthMeters?: number | null;
  averageRunningVerticalOscillationCentimeters?: number | null;
  averageRunningGroundContactTimeMilliseconds?: number | null;
  segments?: Segment[];
};

type RequestBody = {
  context?: WorkoutContext;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });


async function recordGroqQuota(
  response: Response,
  feature: string,
) {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return;

  const parseHeader = (name: string) => {
    const raw = response.headers.get(name);
    if (!raw) return null;
    const value = Number(raw);
    return Number.isFinite(value) ? Math.max(0, Math.round(value)) : null;
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

async function verifyPlus(
  req: Request,
): Promise<
  | { ok: true; userID: string; groqKey: string }
  | { ok: false; response: Response }
> {
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return {
      ok: false,
      response: json({ error: "Missing authenticated user." }, 401),
    };
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const groqKey = Deno.env.get("GROQ_API_KEY");

  if (!supabaseURL || !serviceRoleKey || !groqKey) {
    return {
      ok: false,
      response: json({ error: "ATHLTH Coach is unavailable." }, 503),
    };
  }

  const token = authorization.slice(7).trim();
  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const {
    data: { user },
    error: userError,
  } = await admin.auth.getUser(token);

  if (userError || !user) {
    return {
      ok: false,
      response: json({ error: "Invalid sign-in session." }, 401),
    };
  }

  const { data: entitlement, error } = await admin
    .from("subscription_entitlements")
    .select("status, trial_ends_at, current_period_ends_at")
    .eq("user_id", user.id)
    .maybeSingle();

  if (error) {
    return {
      ok: false,
      response: json({ error: "ATHLTH+ access could not be verified." }, 503),
    };
  }

  const now = Date.now();
  const trialActive =
    entitlement?.status === "trialing" &&
    typeof entitlement?.trial_ends_at === "string" &&
    Date.parse(entitlement.trial_ends_at) > now;

  const paidActive =
    entitlement?.status === "active" &&
    (
      entitlement?.current_period_ends_at == null ||
      (
        typeof entitlement.current_period_ends_at === "string" &&
        Date.parse(entitlement.current_period_ends_at) > now
      )
    );

  if (!trialActive && !paidActive) {
    return {
      ok: false,
      response: json(
        {
          error: "ATHLTH Coach requires ATHLTH+.",
          code: "PREMIUM_REQUIRED",
        },
        403,
      ),
    };
  }

  return {
    ok: true,
    userID: user.id,
    groqKey,
  };
}

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

function sanitizeContext(input: WorkoutContext | undefined) {
  const context = input ?? {};

  return {
    activity: String(context.activity ?? "").slice(0, 40),
    durationSeconds:
      finiteNumber(context.durationSeconds, 0, 86400) ?? 0,
    distanceMeters:
      finiteNumber(context.distanceMeters, 0, 500000),
    activeEnergyKilocalories:
      finiteNumber(context.activeEnergyKilocalories, 0, 10000),
    averageHeartRateBPM:
      finiteNumber(context.averageHeartRateBPM, 20, 260),
    maxHeartRateBPM:
      finiteNumber(context.maxHeartRateBPM, 20, 280),
    personalMaximumHeartRateBPM:
      finiteNumber(context.personalMaximumHeartRateBPM, 80, 260),
    elevationGainMeters:
      finiteNumber(context.elevationGainMeters, 0, 20000),
    routePointCount:
      finiteNumber(context.routePointCount, 0, 200000) ?? 0,
    averagePaceSecondsPerKilometer:
      finiteNumber(context.averagePaceSecondsPerKilometer, 60, 7200),
    averageRunningPowerWatts:
      finiteNumber(context.averageRunningPowerWatts, 0, 2500),
    averageRunningStrideLengthMeters:
      finiteNumber(context.averageRunningStrideLengthMeters, 0, 5),
    averageRunningVerticalOscillationCentimeters:
      finiteNumber(
        context.averageRunningVerticalOscillationCentimeters,
        0,
        50,
      ),
    averageRunningGroundContactTimeMilliseconds:
      finiteNumber(
        context.averageRunningGroundContactTimeMilliseconds,
        0,
        2000,
      ),
    segments: Array.isArray(context.segments)
      ? context.segments.slice(0, 6).map((segment) => ({
          label: String(segment?.label ?? "").slice(0, 40),
          durationSeconds:
            finiteNumber(segment?.durationSeconds, 0, 86400) ?? 0,
          distanceMeters:
            finiteNumber(segment?.distanceMeters, 0, 200000) ?? 0,
          elevationGainMeters:
            finiteNumber(segment?.elevationGainMeters, 0, 10000) ?? 0,
          elevationLossMeters:
            finiteNumber(segment?.elevationLossMeters, 0, 10000) ?? 0,
          averageHeartRateBPM:
            finiteNumber(segment?.averageHeartRateBPM, 20, 260),
          maxHeartRateBPM:
            finiteNumber(segment?.maxHeartRateBPM, 20, 280),
          paceSecondsPerKilometer:
            finiteNumber(segment?.paceSecondsPerKilometer, 60, 7200),
        }))
      : [],
  };
}

const schema = {
  type: "object",
  additionalProperties: false,
  required: ["headline", "summary"],
  properties: {
    headline: {
      type: "string",
      minLength: 1,
      maxLength: 90,
    },
    summary: {
      type: "string",
      minLength: 1,
      maxLength: 420,
    },
  },
};

const instructions = `
You are ATHLTH Coach. Write a short post-workout insight for a running or walking workout.

Use only the supplied aggregate workout and route-segment data.
The segment data intentionally contains no GPS coordinates.

Priorities:
- Connect route profile, pace and heart-rate response when the data supports it.
- Elevation gain/loss and heart-rate or pace changes occurring in the same segment may be described as coinciding, not as proven causation.
- Notice pacing consistency, finishing pattern, heart-rate drift and whether effort changed with terrain.
- If personal maximum heart rate is supplied, you may use it cautiously to contextualize relative intensity.
- If route, heart-rate or pace data is missing, do not invent it.
- Do not diagnose health, fatigue, injury, illness or cardiovascular conditions.
- Consumer wearable data is approximate.
- Avoid generic praise. Prefer one concrete observation.
- headline: 3-8 words.
- summary: 1-2 concise sentences, roughly 25-60 words.
`.trim();

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const access = await verifyPlus(req);
  if (!access.ok) return access.response;

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const context = sanitizeContext(body.context);

  if (!context.activity) {
    return json({ error: "Workout context is missing." }, 400);
  }

  const response = await fetch(
    "https://api.groq.com/openai/v1/responses",
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${access.groqKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model:
          Deno.env.get("GROQ_TRAINING_MODEL") ??
          "openai/gpt-oss-120b",
        reasoning: { effort: "medium" },
        instructions,
        input: JSON.stringify(context),
        text: {
          format: {
            type: "json_schema",
            name: "athlth_workout_insight",
            strict: true,
            schema,
          },
        },
      }),
    },
  );

  await recordGroqQuota(response, "workout-insight");

  if (!response.ok) {
    const failure = await response.text();
    console.error("Workout insight failed", {
      userID: access.userID,
      status: response.status,
      body: failure.slice(0, 1200),
    });
    return json(
      { error: "ATHLTH Coach is temporarily unavailable." },
      502,
    );
  }

  const payload = await response.json();
  const output = extractOutputText(payload);

  if (!output) {
    return json({ error: "ATHLTH Coach returned no insight." }, 502);
  }

  try {
    return json(JSON.parse(output));
  } catch {
    return json({ error: "ATHLTH Coach returned an invalid insight." }, 502);
  }
});
