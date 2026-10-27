import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";
import { conflictsWithInjuryRestrictions } from "../_shared/ai-training-injury-guard.ts";
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

type ExistingDay = {
  weekNumber: number;
  dayIndex: number;
  dayTitle: string;
  existingSessions: string[];
};

type ProgramRequest = {
  mode?: "generate" | "complete";
  startDate?: string;
  weekCount?: number;
  sessionsPerWeek?: number;
  aiChoosesFrequency?: boolean;
  preferredDays?: number[];
  sessionDurationMinutes?: number;
  userNotes?: string;
  // Explicitly opted-in by the athlete, only for this request.
  injurySafetyNotes?: string | null;
  excludedMovements?: string[] | null;
  goals?: GoalInput[];
  existingDays?: ExistingDay[];
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
  required: ["title", "summary", "weeks"],
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
    weeks: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["weekNumber", "title", "days"],
        properties: {
          weekNumber: { type: "integer" },
          title: { type: "string" },
          days: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["dayIndex", "title", "sessions"],
              properties: {
                dayIndex: { type: "integer" },
                title: { type: "string" },
                sessions: {
                  type: "array",
                  items: {
                    type: "object",
                    additionalProperties: false,
                    required: [
                      "title",
                      "kind",
                      "durationMinutes",
                      "targetDistanceKilometers",
                      "targetPaceSecondsPerKilometer",
                      "notes",
                      "exercises",
                      "blocks",
                    ],
                    properties: {
                      title: { type: "string" },
                      kind: {
                        type: "string",
                        enum: [
                          "running",
                          "walking",
                          "strength",
                          "mobility",
                          "recovery",
                          "custom",
                        ],
                      },
                      durationMinutes: {
                        type: ["integer", "null"],
                      },
                      targetDistanceKilometers: {
                        type: ["number", "null"],
                      },
                      targetPaceSecondsPerKilometer: {
                        type: ["number", "null"],
                      },
                      notes: {
                        type: ["string", "null"],
                      },
                      blocks: {
                        type: "array",
                        items: {
                          type: "object",
                          additionalProperties: false,
                          required: [
                            "title", "kind", "phase", "durationSeconds",
                            "distanceMeters", "repetitions",
                            "targetPaceSecondsPerKilometer",
                            "treadmillInclinePercent", "targetHeartRateZone",
                            "targetEffortRPE", "notes",
                          ],
                          properties: {
                            title: { type: "string" },
                            kind: { type: "string", enum: ["run", "exercise", "rest", "note"] },
                            phase: { type: "string", enum: ["warmup", "main", "recovery", "cooldown"] },
                            durationSeconds: { type: ["number", "null"] },
                            distanceMeters: { type: ["number", "null"] },
                            repetitions: { type: ["integer", "null"] },
                            targetPaceSecondsPerKilometer: { type: ["number", "null"] },
                            treadmillInclinePercent: { type: ["number", "null"] },
                            targetHeartRateZone: { type: ["integer", "null"] },
                            targetEffortRPE: { type: ["integer", "null"] },
                            notes: { type: ["string", "null"] },
                          },
                        },
                      },
                      exercises: {
                        type: "array",
                        items: {
                          type: "object",
                          additionalProperties: false,
                          required: [
                            "name",
                            "sets",
                            "reps",
                            "targetRPE",
                            "restSeconds",
                            "notes",
                          ],
                          properties: {
                            name: { type: "string" },
                            sets: { type: "integer" },
                            reps: { type: ["integer", "null"] },
                            targetRPE: { type: ["number", "null"] },
                            restSeconds: { type: ["integer", "null"] },
                            notes: { type: ["string", "null"] },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
};

const DAY_NAMES = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

function clampInteger(value: unknown, low: number, high: number, fallback: number) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(Math.round(parsed), low), high);
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
  } catch (error) {
    console.error("AI quota telemetry skipped", {
      feature,
      message:
        error instanceof Error
          ? error.message
          : String(error),
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

function normalizeProgram(
  program: any,
  weekCount: number,
  preferredDays: number[],
  sessionsPerWeek: number,
  existingDays: ExistingDay[],
  mode: "generate" | "complete",
) {
  const occupied = new Set(
    existingDays
      .filter((day) => (day.existingSessions ?? []).length > 0)
      .map((day) => `${day.weekNumber}:${day.dayIndex}`),
  );

  const preferred = new Set(preferredDays);
  const inputWeeks = Array.isArray(program?.weeks) ? program.weeks : [];

  const weeks = Array.from({ length: weekCount }, (_, weekOffset) => {
    const weekNumber = weekOffset + 1;
    const sourceWeek =
      inputWeeks.find((week: any) => Number(week?.weekNumber) === weekNumber) ??
      inputWeeks[weekOffset] ??
      {};

    const sourceDays = Array.isArray(sourceWeek.days) ? sourceWeek.days : [];
    let usedSessions = 0;

    const days = Array.from({ length: 7 }, (_, dayOffset) => {
      const dayIndex = dayOffset + 1;
      const key = `${weekNumber}:${dayIndex}`;
      const sourceDay =
        sourceDays.find((day: any) => Number(day?.dayIndex) === dayIndex) ??
        {};

      const maySchedule =
        preferred.has(dayIndex) &&
        !(mode === "complete" && occupied.has(key)) &&
        usedSessions < sessionsPerWeek;

      let sessions = maySchedule && Array.isArray(sourceDay.sessions)
        ? sourceDay.sessions.slice(0, 1)
        : [];

      sessions = sessions.map((session: any) => ({
        title: String(session?.title ?? "Training Session").slice(0, 120),
        kind: [
          "running",
          "walking",
          "strength",
          "mobility",
          "recovery",
          "custom",
        ].includes(session?.kind)
          ? session.kind
          : "custom",
        durationMinutes: Number.isFinite(session?.durationMinutes)
          ? clampInteger(session.durationMinutes, 10, 240, 60)
          : null,
        targetDistanceKilometers:
          typeof session?.targetDistanceKilometers === "number"
            ? Math.max(0, Math.min(session.targetDistanceKilometers, 100))
            : null,
        targetPaceSecondsPerKilometer:
          typeof session?.targetPaceSecondsPerKilometer === "number"
            ? Math.max(120, Math.min(session.targetPaceSecondsPerKilometer, 1200))
            : null,
        notes:
          typeof session?.notes === "string"
            ? session.notes.slice(0, 1200)
            : null,
        blocks: Array.isArray(session?.blocks)
          ? session.blocks.slice(0, 80).filter((block: any) =>
              block && ["run", "exercise", "rest", "note"].includes(block.kind) &&
              ["warmup", "main", "recovery", "cooldown"].includes(block.phase) &&
              typeof block.title === "string" && block.title.trim()
            ).map((block: any) => ({
              title: String(block.title).slice(0, 120),
              kind: block.kind,
              phase: block.phase,
              durationSeconds: Number.isFinite(block.durationSeconds) &&
                  block.durationSeconds > 0
                ? Math.min(block.durationSeconds, 14_400) : null,
              distanceMeters: Number.isFinite(block.distanceMeters) &&
                  block.distanceMeters > 0
                ? Math.min(block.distanceMeters, 100_000) : null,
              repetitions: Number.isInteger(block.repetitions) &&
                  block.repetitions >= 1 && block.repetitions <= 100
                ? block.repetitions : null,
              targetPaceSecondsPerKilometer:
                Number.isFinite(block.targetPaceSecondsPerKilometer) &&
                block.targetPaceSecondsPerKilometer >= 120 &&
                block.targetPaceSecondsPerKilometer <= 1200
                  ? block.targetPaceSecondsPerKilometer : null,
              treadmillInclinePercent:
                Number.isFinite(block.treadmillInclinePercent) &&
                block.treadmillInclinePercent >= 0 &&
                block.treadmillInclinePercent <= 20
                  ? block.treadmillInclinePercent : null,
              targetHeartRateZone:
                Number.isInteger(block.targetHeartRateZone) &&
                block.targetHeartRateZone >= 1 &&
                block.targetHeartRateZone <= 5
                  ? block.targetHeartRateZone : null,
              targetEffortRPE:
                Number.isInteger(block.targetEffortRPE) &&
                block.targetEffortRPE >= 1 && block.targetEffortRPE <= 10
                  ? block.targetEffortRPE : null,
              notes: typeof block.notes === "string"
                ? block.notes.slice(0, 500) : null,
            }))
          : [],
        exercises: Array.isArray(session?.exercises)
          ? session.exercises.slice(0, 12).map((exercise: any) => ({
              name: String(exercise?.name ?? "Exercise").slice(0, 120),
              sets: clampInteger(exercise?.sets, 1, 8, 3),
              reps: Number.isFinite(exercise?.reps)
                ? clampInteger(exercise.reps, 1, 50, 8)
                : null,
              targetRPE:
                typeof exercise?.targetRPE === "number"
                  ? Math.max(1, Math.min(exercise.targetRPE, 10))
                  : null,
              restSeconds: Number.isFinite(exercise?.restSeconds)
                ? clampInteger(exercise.restSeconds, 15, 600, 90)
                : null,
              notes:
                typeof exercise?.notes === "string"
                  ? exercise.notes.slice(0, 500)
                  : null,
            }))
          : [],
      }));

      if (sessions.length > 0) usedSessions += 1;

      return {
        dayIndex,
        title: DAY_NAMES[dayOffset],
        sessions,
      };
    });

    return {
      weekNumber,
      title:
        typeof sourceWeek?.title === "string" && sourceWeek.title.trim()
          ? sourceWeek.title.slice(0, 120)
          : `Week ${weekNumber}`,
      days,
    };
  });

  return {
    title:
      typeof program?.title === "string" && program.title.trim()
        ? program.title.slice(0, 160)
        : "AI Training Program",
    summary:
      typeof program?.summary === "string"
        ? program.summary.slice(0, 1500)
        : "",
    weeks,
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
    console.error("Unable to verify ATHLTH+ entitlement", {
      userID: user.id,
      message: entitlementError.message,
    });
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
      error: "ATHLTH AI requires an active ATHLTH+ plan or trial.",
      code: "PREMIUM_REQUIRED",
    }, 403);
  }

  let body: ProgramRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const mode = body.mode === "complete" ? "complete" : "generate";
  const weekCount = clampInteger(body.weekCount, 1, 52, 8);
  const preferredDays = Array.from(
    new Set(
      (body.preferredDays ?? [])
        .map(Number)
        .filter((day) => Number.isInteger(day) && day >= 1 && day <= 7),
    ),
  ).sort();

  if (preferredDays.length === 0) {
    return json({ error: "Choose at least one available training day." }, 400);
  }

  const sessionsPerWeek = Math.min(
    clampInteger(body.sessionsPerWeek, 1, 7, 4),
    preferredDays.length,
  );
  const aiChoosesFrequency = mode === "generate" && body.aiChoosesFrequency === true;
  const sessionDurationMinutes = clampInteger(
    body.sessionDurationMinutes,
    20,
    180,
    60,
  );
  // A saved ATHLTH goal is optional. Standalone Coach requests carry
  // explicitly selected training types and outcomes in userNotes.
  const goals = Array.isArray(body.goals) ? body.goals.slice(0, 8) : [];

  const existingDays = Array.isArray(body.existingDays)
    ? body.existingDays.slice(0, 52 * 7)
    : [];

  const constraints = {
    mode,
    startDate: body.startDate ?? null,
    weekCount,
    sessionsPerWeek,
    aiChoosesFrequency,
    preferredDays,
    preferredDayNames: preferredDays.map((day) => DAY_NAMES[day - 1]),
    sessionDurationMinutes,
    userNotes: String(body.userNotes ?? "").slice(0, 3000),
    // Do not merge this into generic notes: generic note limits previously
    // truncated safety-critical restrictions placed near the end.
    injurySafetyNotes: typeof body.injurySafetyNotes === "string"
      ? body.injurySafetyNotes.slice(0, 3_000) : null,
    excludedMovements: Array.isArray(body.excludedMovements)
      ? body.excludedMovements
          .filter((name): name is string => typeof name === "string")
          .map((name) => name.trim().slice(0, 100))
          .filter((name) => name.length >= 2)
          .slice(0, 40)
      : [],
    goals,
    existingDays: mode === "complete" ? existingDays : [],
  };

  const instructions = `
You are ATHLTH AI, a conservative training-program planning assistant.
Create a practical program from the user's explicit goals, selected outcomes and constraints. A saved goal may be absent; in that case use only the stated intake and never invent a target.

Hard rules:
- Return exactly the requested number of weeks.
- Every week must contain all seven days, dayIndex 1=Monday through 7=Sunday.
- Schedule at most one workout on a day and no more than sessionsPerWeek workouts per week.
- If aiChoosesFrequency is true, sessionsPerWeek is a strict MAXIMUM, not a required target. Select a sustainable weekly frequency yourself based on the stated experience, current training, goal, time and available days. Do not assume all available days should be training days. Explain the chosen frequency in the summary and leave recovery days.
- If aiChoosesFrequency is false, aim for the requested sessionsPerWeek unless the user constraints make that unsafe or impossible.
- Schedule workouts only on preferredDays.
- In complete mode, days that already contain existingSessions are locked: return zero generated sessions for those days.
- Do not invent personal medical conditions, diagnoses, injuries, medications, or lab values.
- Do not promise that a goal will be achieved by a deadline.
- Use conservative progression, recovery, and rest. Avoid repeated maximal-effort sessions.
- The injurySafetyNotes field, when present, contains the athlete's expressly consented health restrictions. It is a mandatory exercise-exclusion safety constraint, not optional context.
- Never prescribe, suggest or include any exercise explicitly listed in excludedMovements, including close variations and exercises that put load on an area the user said cannot be loaded.
- If the athlete forbids lower-body loading, no running, walking, squats, lunges, jumping, cycling or lower-body strength blocks are allowed. If activities selected earlier conflict with these restrictions, the injury restrictions always take priority.
- Respect the athlete's injury description even if it conflicts with their preferred sport, goals or session count. If a safe workout cannot be selected, leave that day as a rest day and explain the limitation in the summary. Do not replace an excluded exercise with a similarly aggravating variation.
- If there is no injurySafetyNotes field, do not assume you know a diagnosis or which exercises are individually safe. Do not claim a generated workout is medically cleared.
- Use health notes to avoid contraindicated exercises; do not diagnose, treat or promise any medical result.
- If a goal or note suggests a medical limitation, keep recommendations general and low-risk rather than treating the condition.
- Strength work should use exercise names, sets, reps, sensible RPE, and rest, but never invent target weights.
- Running/walking sessions can include duration and/or distance. Only include a target pace when the provided goal genuinely supports one.
- Every session has a blocks array (which may be empty if no precise structure is justified). Blocks describe one chronological timeline: warmup, main effort, recovery between efforts, cooldown. If prescribing intervals, include EACH effort and EACH between-effort rest; never append an extra rest after the last repeat.
- For an explicitly prescribed 4x4 interval session, provide warmup, four distinct 240-second main run blocks, three 120-second recovery blocks between them, and a cooldown. Use targetPaceSecondsPerKilometer, treadmillInclinePercent, targetHeartRateZone and targetEffortRPE only when justified by user input; otherwise use null.
- For strength, include explicit exercise blocks with proper repetitions and recovery steps when helpful. Never invent a measured heart rate, completed workout, equipment access or target weight.
- Keep arrays of blocks reasonably short (prefer fewer than 30), and do not generate workout details that were not requested or cannot be supported.
- Use the user's goal deadlines and milestones as context, but do not exceed the explicit timeline.
- The output is a draft the user will review before applying.
`.trim();

  const budgetResponse = await enforceAIRequestBudget(() => admin.rpc("consume_ai_request_budget", {
    p_user_id: user.id, p_feature: "generate-training-program",
  }));
  if (budgetResponse) return budgetResponse;

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
          name: "athlth_training_program",
          strict: true,
          schema,
        },
      },
    }),
  });

  await recordGroqQuota(aiResponse, "training-program");

  if (!aiResponse.ok) {
    // Provider response bodies can echo consented injury details.
    // Keep health information out of persistent application logs.
    console.error("Groq program generation failed", {
      status: aiResponse.status,
      feature: "generate-training-program",
    });
    return json({ error: "AI program generation failed. Please try again." }, 502);
  }

  const payload = await aiResponse.json();
  const outputText = extractOutputText(payload);
  if (!outputText) {
    return json({ error: "AI returned an empty program." }, 502);
  }

  let program: any;
  try {
    program = JSON.parse(outputText);
  } catch {
    // Never log AI output: it can contain sensitive training limitations.
    console.error("Unable to parse structured AI program", {
      feature: "generate-training-program",
    });
    return json({ error: "AI returned an invalid program." }, 502);
  }

  const normalized = normalizeProgram(
    program,
    weekCount,
    preferredDays,
    sessionsPerWeek,
    existingDays,
    mode,
  );

  if (conflictsWithInjuryRestrictions(
    normalized,
    constraints.excludedMovements,
    constraints.injurySafetyNotes,
  )) {
    // Do not return a contraindicated AI plan for the athlete to accept.
    // Do not log or echo the health notes or specific restricted movements.
    return json({
      error: "AI suggested an excluded exercise. No plan was saved; please try again.",
      code: "AI_COACH_INJURY_CONFLICT",
    }, 422);
  }

  return json(normalized);
});
