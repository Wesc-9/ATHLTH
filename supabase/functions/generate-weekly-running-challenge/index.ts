import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type ChallengeRequest = {
  startDate?: string;
  endDate?: string;
  previousTitles?: string[];
  notes?: string;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

const schema = {
  type: "object",
  additionalProperties: false,
  required: ["title", "subtitle", "kind", "targetValue"],
  properties: {
    title: { type: "string" },
    subtitle: { type: "string" },
    kind: {
      type: "string",
      enum: ["distance", "sessions", "minutes", "streak"],
    },
    targetValue: { type: "number" },
  },
};


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
  if (typeof payload?.output_text === "string") return payload.output_text;

  for (const item of payload?.output ?? []) {
    for (const content of item?.content ?? []) {
      if (content?.type === "output_text" && typeof content?.text === "string") {
        return content.text;
      }
    }
  }
  return null;
}

function normalizeChallenge(raw: any) {
  const kind = ["distance", "sessions", "minutes", "streak"].includes(raw?.kind)
    ? raw.kind
    : "distance";

  let target = Number(raw?.targetValue);
  if (!Number.isFinite(target)) {
    target = kind === "distance" ? 25 : kind === "minutes" ? 150 : 3;
  }

  switch (kind) {
    case "distance":
      target = Math.min(Math.max(Math.round(target), 15), 50);
      break;
    case "sessions":
      target = Math.min(Math.max(Math.round(target), 2), 5);
      break;
    case "minutes":
      target = Math.min(Math.max(Math.round(target / 15) * 15, 90), 240);
      break;
    case "streak":
      target = Math.min(Math.max(Math.round(target), 3), 6);
      break;
  }

  return {
    title: String(raw?.title ?? "Weekly Run").trim().slice(0, 120),
    subtitle: String(raw?.subtitle ?? "A running challenge for the ATHLTH community.")
      .trim()
      .slice(0, 240),
    kind,
    targetValue: target,
  };
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

  if (!supabaseURL || !serviceRoleKey || !groqKey) {
    return json({ error: "ATHLTH AI is unavailable." }, 503);
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

  let body: ChallengeRequest = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const previousTitles = (body.previousTitles ?? [])
    .map(String)
    .slice(0, 12);

  const context = {
    startDate: body.startDate ?? null,
    endDate: body.endDate ?? null,
    previousTitles,
    notes: String(body.notes ?? "").slice(0, 1000),
    currentMonth: body.startDate
      ? new Date(body.startDate).toLocaleString("en", { month: "long" })
      : new Date().toLocaleString("en", { month: "long" }),
  };

  const instructions = `
You are ATHLTH AI creating one official weekly running challenge for a fitness community.

Goals:
- Make the challenge instantly understandable and attractive to a broad range of runners and walkers.
- Vary the challenge format from recent titles and avoid repeating the same concept every week.
- Keep the concept running-first, but registered walking workouts also count toward every challenge.
- Keep the challenge achievable for many recreational runners, but occasionally allow a more ambitious week such as 50 km.
- Use a concise, premium title and one-sentence subtitle.
- Let the calendar month/season influence tone lightly, but do not assume weather or geography.

Allowed challenge kinds and target ranges:
- distance: 15 to 50 kilometres completed through registered run or walk workouts.
- sessions: 2 to 5 separate run or walk workouts.
- minutes: 90 to 240 total run or walk minutes.
- streak: 3 to 6 days with at least one registered run or walk workout.

Hard rules:
- Make it clear in the subtitle when useful that registered walks count too.
- Never require a specific pace, medical state, heart-rate zone, body weight, age, or performance level.
- Never require dangerous maximal effort.
- Do not mention AI.
- Do not use a route unless explicitly requested.
- Output one challenge only.
`.trim();

  const aiResponse = await fetch("https://api.groq.com/openai/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${groqKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("GROQ_TRAINING_MODEL") ?? "openai/gpt-oss-120b",
      reasoning: { effort: "medium" },
      instructions,
      input: JSON.stringify(context),
      text: {
        format: {
          type: "json_schema",
          name: "athlth_weekly_running_challenge",
          strict: true,
          schema,
        },
      },
    }),
  });

  await recordGroqQuota(aiResponse, "weekly-challenge");

  if (!aiResponse.ok) {
    const failure = await aiResponse.text();
    console.error("Weekly challenge generation failed", {
      status: aiResponse.status,
      body: failure.slice(0, 1000),
      userID: user.id,
    });
    return json({ error: "Challenge generation failed. Please try again." }, 502);
  }

  const payload = await aiResponse.json();
  const outputText = extractOutputText(payload);
  if (!outputText) {
    return json({ error: "AI returned an empty challenge." }, 502);
  }

  try {
    return json(normalizeChallenge(JSON.parse(outputText)));
  } catch {
    return json({ error: "AI returned an invalid challenge." }, 502);
  }
});
