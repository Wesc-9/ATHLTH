import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type GoalInput = {
  id: string;
  title: string;
  category: string;
  deadline?: string | null;
  targetSummary?: string | null;
  whyItMatters?: string | null;
  notes?: string | null;
  milestones?: string[];
};

type SessionInput = {
  id: string;
  title: string;
  kind: string;
  durationMinutes?: number | null;
  scheduledStart?: string | null;
  notes?: string | null;
};

type DayInput = {
  weekNumber: number;
  dayIndex: number;
  date?: string | null;
  title: string;
  sessions: SessionInput[];
};

type AdaptationRequest = {
  planID?: string;
  planVersion?: number;
  planTitle?: string;
  planStartDate?: string | null;
  planEndDate?: string | null;
  today?: string;
  days?: DayInput[];
  goals?: GoalInput[];
  recentTraining?: string[];
  userNotes?: string;
};

const CHANGE_KINDS = [
  "moveWorkout",
  "replaceWorkout",
  "adjustDuration",
  "adjustIntensity",
  "addRecovery",
  "removeWorkout",
] as const;

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
  required: ["headline", "rationale", "changes"],
  properties: {
    headline: { type: "string" },
    rationale: { type: "string" },
    changes: {
      type: "array",
      maxItems: 5,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "kind",
          "sessionID",
          "sourceDate",
          "targetDate",
          "title",
          "summary",
          "reason",
          "replacementTitle",
          "durationMinutes",
          "intensityNote",
        ],
        properties: {
          kind: { type: "string", enum: CHANGE_KINDS },
          sessionID: { type: ["string", "null"] },
          sourceDate: { type: ["string", "null"] },
          targetDate: { type: ["string", "null"] },
          title: { type: "string" },
          summary: { type: "string" },
          reason: { type: "string" },
          replacementTitle: { type: ["string", "null"] },
          durationMinutes: { type: ["integer", "null"] },
          intensityNote: { type: ["string", "null"] },
        },
      },
    },
  },
};

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

function clampInteger(
  value: unknown,
  low: number,
  high: number,
  fallback: number,
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(Math.round(parsed), low), high);
}

async function recordGroqQuota(response: Response) {
  try {
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

    await admin.from("ai_provider_quota_snapshots").upsert(
      {
        provider: "groq",
        model:
          Deno.env.get("GROQ_TRAINING_MODEL") ??
          "openai/gpt-oss-120b",
        limit_requests: limitRequests,
        remaining_requests: remainingRequests,
        reset_requests: resetRequests,
        last_feature: "plan-adaptation",
        updated_at: new Date().toISOString(),
      },
      { onConflict: "provider,model" },
    );
  } catch (error) {
    console.error("Plan adaptation quota telemetry skipped", error);
  }
}

function normalize(
  raw: any,
  body: AdaptationRequest,
) {
  const days = Array.isArray(body.days) ? body.days : [];
  const today = typeof body.today === "string"
    ? body.today
    : new Date().toISOString().slice(0, 10);

  const allowedDates = new Set(
    days
      .map((day) => day.date)
      .filter((value): value is string =>
        typeof value === "string" && value >= today
      ),
  );

  const sessions = new Map<string, { date: string | null; title: string }>();
  const occupiedDates = new Set<string>();

  for (const day of days) {
    if (typeof day.date === "string" && (day.sessions ?? []).length > 0) {
      occupiedDates.add(day.date);
    }
    for (const session of day.sessions ?? []) {
      if (typeof session.id === "string") {
        sessions.set(session.id, {
          date: typeof day.date === "string" ? day.date : null,
          title: String(session.title ?? "Workout"),
        });
      }
    }
  }

  const inputChanges = Array.isArray(raw?.changes)
    ? raw.changes.slice(0, 5)
    : [];

  const changes = inputChanges.flatMap((change: any) => {
    if (!CHANGE_KINDS.includes(change?.kind)) return [];

    const kind = change.kind as typeof CHANGE_KINDS[number];
    const sessionID =
      typeof change?.sessionID === "string" &&
      sessions.has(change.sessionID)
        ? change.sessionID
        : null;

    const sourceDate = sessionID
      ? sessions.get(sessionID)?.date ?? null
      : null;

    const targetDate =
      typeof change?.targetDate === "string" &&
      allowedDates.has(change.targetDate)
        ? change.targetDate
        : null;

    const sessionRequired = kind !== "addRecovery";
    if (sessionRequired && !sessionID) return [];

    if (kind === "moveWorkout") {
      if (!targetDate || targetDate === sourceDate) return [];
      if (occupiedDates.has(targetDate)) return [];
    }

    if (kind === "addRecovery") {
      if (!targetDate || occupiedDates.has(targetDate)) return [];
    }

    const durationMinutes =
      change?.durationMinutes == null
        ? null
        : clampInteger(
            change.durationMinutes,
            10,
            kind === "addRecovery" ? 90 : 240,
            kind === "addRecovery" ? 25 : 45,
          );

    return [{
      kind,
      sessionID,
      sourceDate,
      targetDate,
      title: String(change?.title ?? "Coach suggestion").slice(0, 120),
      summary: String(change?.summary ?? "").slice(0, 500),
      reason: String(change?.reason ?? "").slice(0, 800),
      replacementTitle:
        typeof change?.replacementTitle === "string"
          ? change.replacementTitle.slice(0, 120)
          : null,
      durationMinutes,
      intensityNote:
        typeof change?.intensityNote === "string"
          ? change.intensityNote.slice(0, 500)
          : null,
    }];
  });

  return {
    headline:
      typeof raw?.headline === "string" && raw.headline.trim()
        ? raw.headline.slice(0, 160)
        : changes.length > 0
          ? "Your plan can adapt."
          : "Your plan still fits.",
    rationale:
      typeof raw?.rationale === "string"
        ? raw.rationale.slice(0, 1200)
        : "",
    changes,
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

  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "ATHLTH backend is unavailable." }, 503);
  }
  if (!groqKey) {
    return json({
      error: "ATHLTH AI is not configured yet.",
      code: "AI_NOT_CONFIGURED",
    }, 503);
  }

  const token = authorization.slice(7).trim();
  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: userError } = await admin.auth.getUser(token);
  if (userError || !user) {
    return json({ error: "Your sign-in session is no longer valid." }, 401);
  }

  const { data: entitlement, error: entitlementError } = await admin
    .from("subscription_entitlements")
    .select("status, trial_ends_at, current_period_ends_at")
    .eq("user_id", user.id)
    .maybeSingle();

  if (entitlementError) {
    return json({
      error: "ATHLTH+ access could not be verified. Please try again.",
      code: "ENTITLEMENT_CHECK_FAILED",
    }, 503);
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
    return json({
      error: "ATHLTH Coach requires an active ATHLTH+ plan or trial.",
      code: "PREMIUM_REQUIRED",
    }, 403);
  }

  let body: AdaptationRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  if (
    typeof body.planID !== "string" ||
    !Number.isInteger(body.planVersion) ||
    !Array.isArray(body.days) ||
    body.days.length === 0
  ) {
    return json({ error: "The active plan context is incomplete." }, 400);
  }

  const constraints = {
    planID: body.planID,
    planVersion: body.planVersion,
    planTitle: String(body.planTitle ?? "").slice(0, 160),
    planStartDate: body.planStartDate ?? null,
    planEndDate: body.planEndDate ?? null,
    today: body.today ?? new Date().toISOString().slice(0, 10),
    days: body.days.slice(0, 52 * 7),
    goals: Array.isArray(body.goals) ? body.goals.slice(0, 8) : [],
    recentTraining: Array.isArray(body.recentTraining)
      ? body.recentTraining.slice(0, 20).map((item) => String(item).slice(0, 260))
      : [],
    userNotes: String(body.userNotes ?? "").slice(0, 1200),
  };

  const instructions = `
You are ATHLTH Coach. Review an existing training plan and propose only useful,
conservative changes. You are not allowed to modify the plan directly.

Rules:
- Return no more than five proposed changes.
- Never change a day before "today".
- For moveWorkout, replaceWorkout, adjustDuration, adjustIntensity and
  removeWorkout, sessionID must exactly match one supplied session.
- addRecovery is the only change that may omit sessionID.
- targetDate must be one of the supplied plan dates and must not already contain
  a workout. Do not create double-session days.
- Do not make a change merely to appear helpful. Returning an empty changes
  array is correct when the current plan still makes sense.
- Use recentTraining only as incomplete training context. Missing workouts do
  not prove inactivity or a missed session.
- Never infer injury, illness, diagnosis, medication, or medical readiness.
- Keep training progression conservative. Do not prescribe maximal efforts.
- Respect explicit goals and userNotes, but never promise goal achievement.
- Explain every change in plain language under reason.
- The user must review and accept all changes before anything is applied.
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
      input: JSON.stringify(constraints),
      text: {
        format: {
          type: "json_schema",
          name: "athlth_plan_adaptation",
          strict: true,
          schema,
        },
      },
    }),
  });

  await recordGroqQuota(aiResponse);

  if (!aiResponse.ok) {
    const failure = await aiResponse.text();
    console.error("Groq plan adaptation failed", {
      status: aiResponse.status,
      body: failure.slice(0, 2000),
      userID: user.id,
    });
    return json({
      error: "Coach could not review the plan right now. Please try again.",
    }, 502);
  }

  const payload = await aiResponse.json();
  const outputText = extractOutputText(payload);
  if (!outputText) {
    return json({ error: "Coach returned an empty response." }, 502);
  }

  let parsed: any;
  try {
    parsed = JSON.parse(outputText);
  } catch {
    return json({ error: "Coach returned an invalid response." }, 502);
  }

  return json(normalize(parsed, body));
});
