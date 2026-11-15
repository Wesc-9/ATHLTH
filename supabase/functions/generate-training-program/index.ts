import { coachProgramRequest, coachProgramOutput, coachProviderErrorCode, coachShouldRetryInvalidSchema, coachProgramFallbackRequest, coachProgramHasUsableWeeks, coachCompactProgramRequest, coachCompactValidatedProgram, coachProviderRetryAfter, coachParseProgramText, coachBackfillSparseFinalWeek } from "./provider.ts";
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
  aiChoosesDuration?: boolean;
  varyWeeks?: boolean;
  preferredDays?: number[];
  sessionDurationMinutes?: number;
  userNotes?: string;
  // Explicitly opted-in by the athlete, only for this request.
  injurySafetyNotes?: string | null;
  excludedMovements?: string[] | null;
  unavailableEquipment?: string[] | null;
  // Explicitly consented strength signal summary from on-device Coach History.
  coachStrengthContext?: unknown;
  goals?: GoalInput[];
  existingDays?: ExistingDay[];
};

const json = (
  body: Record<string, unknown>,
  status = 200,
  extraHeaders: Record<string, string> = {},
) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...extraHeaders,
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



type StrengthCoachContext = {
  windowDays: number;
  completedStrengthSessions: number;
  strengthSessionsLastSevenDays: number;
  completedWorkingSets: number;
  recordedVolumeKg: number;
  exerciseSignals: Array<{
    exercise: string;
    completedSessions: number;
    mostRecentWorkingWeightKg: number | null;
    bestEstimatedOneRepMaxKg: number | null;
    trend: string;
    recommendation: string;
  }>;
};

// Explicit allowlist: no hidden symptoms, diagnoses, notes or unbounded
// user-supplied prose can be copied from the request into the AI prompt.
function normalizeCoachStrengthContext(value: unknown): StrengthCoachContext | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const obj = value as Record<string, unknown>;
  if (typeof obj.windowDays !== "number" ||
      !Number.isInteger(obj.windowDays) || obj.windowDays !== 56) return null;
  const bounded = (raw: unknown, maximum: number): number => {
    const n = Number(raw);
    return Number.isFinite(n) ? Math.max(0, Math.min(n, maximum)) : 0;
  };
  const optionalWeight = (raw: unknown): number | null => {
    if (typeof raw !== "number" || !Number.isFinite(raw) || raw <= 0) return null;
    return Math.min(raw, 2_000);
  };
  const validTrends = new Set(["plateau", "improving", "insufficient_evidence"]);
  const validAdvice = new Set(["review_small_increase", "review_plateau", "hold_and_collect_evidence"]);
  const entries = Array.isArray(obj.exerciseSignals) ? obj.exerciseSignals.slice(0, 10) : [];
  const exerciseSignals = entries.flatMap((raw: unknown) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
    const item = raw as Record<string, unknown>;
    const exercise = typeof item.exercise === "string" ? item.exercise.trim().slice(0, 100) : "";
    if (!exercise || /[<>{}\n\r]/.test(exercise)) return [];
    return [{
      exercise,
      completedSessions: bounded(item.completedSessions, 56),
      mostRecentWorkingWeightKg: optionalWeight(item.mostRecentWorkingWeightKg),
      bestEstimatedOneRepMaxKg: optionalWeight(item.bestEstimatedOneRepMaxKg),
      trend: validTrends.has(String(item.trend)) ? String(item.trend) : "insufficient_evidence",
      recommendation: validAdvice.has(String(item.recommendation))
        ? String(item.recommendation) : "hold_and_collect_evidence",
    }];
  });
  return {
    windowDays: 56,
    completedStrengthSessions: bounded(obj.completedStrengthSessions, 70),
    strengthSessionsLastSevenDays: bounded(obj.strengthSessionsLastSevenDays, 14),
    completedWorkingSets: bounded(obj.completedWorkingSets, 2_000),
    recordedVolumeKg: bounded(obj.recordedVolumeKg, 1_000_000),
    exerciseSignals,
  };
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
  const aiChoosesDuration = mode === "generate" && body.aiChoosesDuration === true;
  const varyWeeks = mode === "generate" && body.varyWeeks === true;
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
    aiChoosesDuration,
    varyWeeks,
    preferredDays,
    preferredDayNames: preferredDays.map((day) => DAY_NAMES[day - 1]),
    sessionDurationMinutes,
    userNotes: String(body.userNotes ?? "").slice(0, 3000),
    // Do not merge this into generic notes: generic note limits previously
    // truncated safety-critical restrictions placed near the end.
    injurySafetyNotes: typeof body.injurySafetyNotes === "string"
      ? body.injurySafetyNotes.slice(0, 3_000) : null,
    coachStrengthContext: normalizeCoachStrengthContext(body.coachStrengthContext),
    excludedMovements: Array.isArray(body.excludedMovements)
      ? body.excludedMovements
          .filter((name): name is string => typeof name === "string")
          .map((name) => name.trim().slice(0, 100))
          .filter((name) => name.length >= 2)
          .slice(0, 40)
      : [],
    unavailableEquipment: Array.isArray(body.unavailableEquipment)
      ? body.unavailableEquipment
          .filter((name): name is string => typeof name === "string")
          .map((name) => name.trim().slice(0, 80))
          .filter(Boolean).slice(0, 30)
      : [],
    goals,
    existingDays: mode === "complete" ? existingDays : [],
  };

  const instructions = `
You are ATHLTH AI, a conservative training-program planning assistant.
Create a practical program from the user's explicit goals, selected outcomes and constraints. A saved goal may be absent; in that case use only the stated intake and never invent a target.

Hard rules:
- Return exactly the requested number of weeks.
- Each week should contain only selected preferredDays with dayIndex 1=Monday through 7=Sunday. The server will fill omitted rest days; represent a rest on a selected weekday with sessions: []. This keeps long plans compact without losing real schedule information.
- Schedule at most one workout on a day and no more than sessionsPerWeek workouts per week.
- If aiChoosesFrequency is true, sessionsPerWeek is a strict MAXIMUM, not a required target. Select a sustainable weekly frequency yourself based on the stated experience, current training, goal, time and available days. Do not assume all available days should be training days. Explain the chosen frequency in the summary and leave recovery days.
- If aiChoosesFrequency is false, aim for the requested sessionsPerWeek unless the user constraints make that unsafe or impossible.
- If varyWeeks is true, make the WEEKS meaningfully different through changing the exercise mix, session structure and appropriate training progression. Do not duplicate the same workout list verbatim every week. Keep the user's selected weekdays, equipment and injury restrictions, and a consistent mix of strength/cardio for mixed goals. Do not vary at random or add unrequested high intensity.
- If varyWeeks is false, a familiar weekly pattern is fine, but week-to-week progression and recovery must still be sensible.
- A lighter final recovery (deload) week does NOT mean six rest days. Keep a meaningful training frequency, usually 70–80% of the preceding weeks, and reduce volume, duration, intensity or RPE instead. A truly rest-heavy week is appropriate only when the athlete's express limitations require it. Every week must have real workouts unless safety restrictions prevent exercise.
- If aiChoosesDuration is true, sessionDurationMinutes is only a fallback reference, NOT a fixed duration. Choose sensible durations separately for the workout type and the user's experience, recovery and schedule; keep each session 20–180 minutes and make its blocks fit the chosen duration. Do not prescribe the same duration on every day without a reason.
- If aiChoosesDuration is false, respect the requested approximate duration within practical warmup and cooldown needs.
- Schedule workouts only on preferredDays.
- In complete mode, days that already contain existingSessions are locked: return zero generated sessions for those days.
- Do not invent personal medical conditions, diagnoses, injuries, medications, or lab values.
- Do not promise that a goal will be achieved by a deadline.
- Use conservative progression, recovery, and rest. Avoid repeated maximal-effort sessions.
- The injurySafetyNotes field, when present, contains the athlete's expressly consented health restrictions. It is a mandatory exercise-exclusion safety constraint, not optional context.
- Never prescribe, suggest or include any exercise explicitly listed in excludedMovements, including close variations and exercises that put load on an area the user said cannot be loaded.
- unavailableEquipment is a hard equipment restriction. Never prescribe exercises that require those items, even when the generic note assumes full gym access. Select accessible equipment-free substitutions or leave a rest day if necessary. Do not silently assume excluded gear can be borrowed.
- If the athlete forbids lower-body loading, no running, walking, squats, lunges, jumping, cycling or lower-body strength blocks are allowed. If activities selected earlier conflict with these restrictions, the injury restrictions always take priority.
- Respect the athlete's injury description even if it conflicts with their preferred sport, goals or session count. If a safe workout cannot be selected, leave that day as a rest day and explain the limitation in the summary. Do not replace an excluded exercise with a similarly aggravating variation.
- If there is no injurySafetyNotes field, do not assume you know a diagnosis or which exercises are individually safe. Do not claim a generated workout is medically cleared.
- Use health notes to avoid contraindicated exercises; do not diagnose, treat or promise any medical result.
- If a goal or note suggests a medical limitation, keep recommendations general and low-risk rather than treating the condition.
- When coachStrengthContext is present, use it only as supporting evidence from recorded training: differentiate measured working weight from an estimated 1RM, distinguish absence of history from lack of progress, and consider strength/cardio fatigue together. A plateau is a review signal, not a diagnosis.
- Never extrapolate from an estimated 1RM to an automatic prescription or invent a personal max. Suggest incremental load review only when two separate verified completed sessions met their prescribed sets/reps/loads. Do not copy current weights into every future session. Apply conservative progression and deload weeks when indicated, always as an editable draft.
- coachStrengthContext is absent if the athlete has not enabled Coach History. Never request or invent those records or infer injury details from training load.
- Strength work should use exercise names, sets, reps, sensible RPE, and rest, but never invent target weights.
- Running/walking sessions can include duration and/or distance. Only include a target pace when the provided goal genuinely supports one.
- Every session has a blocks array (which may be empty if no precise structure is justified). Blocks describe one chronological timeline: warmup, main effort, recovery between efforts, cooldown. If prescribing intervals, include EACH effort and EACH between-effort rest; never append an extra rest after the last repeat.
- For an explicitly prescribed 4x4 interval session, provide warmup, four distinct 240-second main run blocks, three 120-second recovery blocks between them, and a cooldown. Use targetPaceSecondsPerKilometer, treadmillInclinePercent, targetHeartRateZone and targetEffortRPE only when justified by user input; otherwise use null.
- For strength, include explicit exercise blocks with proper repetitions and recovery steps when helpful. Never invent a measured heart rate, completed workout, equipment access or target weight.
- Keep arrays of blocks reasonably short (prefer fewer than 18), and do not generate workout details that were not requested or cannot be supported. Do not add redundant note blocks or unnecessary exercise metadata.
- Use the user's goal deadlines and milestones as context, but do not exceed the explicit timeline.
- The output is a draft the user will review before applying.
`.trim();

  // Global provider cooldown survives across requests and Edge Function
  // instances. It stores only the provider name and expiry; no athlete data.
  const { data: cooldown, error: cooldownError } = await admin
    .from("athlth_ai_provider_cooldowns")
    .select("retry_at")
    .eq("provider", "groq")
    .maybeSingle();

  if (cooldownError) {
    console.error("Coach provider cooldown unavailable", {
      code: cooldownError.code ?? "query_failed",
    });
    // Fail closed: never consume a paid AI request if the limiter is offline.
    return json({
      error: "ATHLTH Coach is temporarily unavailable.",
      code: "AI_PROVIDER_UNAVAILABLE",
    }, 503);
  }

  const retryAt = typeof cooldown?.retry_at === "string"
    ? Date.parse(cooldown.retry_at) : NaN;
  const cooldownSeconds = Number.isFinite(retryAt)
    ? Math.max(0, Math.ceil((retryAt - Date.now()) / 1000)) : 0;
  if (cooldownSeconds > 0) {
    return json({
      error: "ATHLTH Coach's AI capacity is refreshing. Please try later.",
      code: "AI_PROVIDER_RATE_LIMIT",
      retryAfterSeconds: cooldownSeconds,
    }, 429, { "Retry-After": String(cooldownSeconds) });
  }

  const storeGroqCooldown = async (seconds: number): Promise<void> => {
    const { error } = await admin.rpc("athlth_set_ai_provider_cooldown", {
      p_provider: "groq",
      p_seconds: Math.min(3600, Math.max(1, Math.ceil(seconds))),
    });
    if (error) {
      console.error("Coach could not store provider cooldown", {
        code: error.code ?? "rpc_failed",
      });
    }
  };

  const budgetResponse = await enforceAIRequestBudget(() => admin.rpc("consume_ai_request_budget", {
    p_user_id: user.id, p_feature: "generate-training-program",
  }));
  if (budgetResponse) return budgetResponse;

  // The response may include private goals or consented injury notes.
  // Never persist a provider response body, prompt, or athlete identifiers.
  const requestId = crypto.randomUUID();
  const model = Deno.env.get("GROQ_TRAINING_MODEL") ?? "openai/gpt-oss-120b";
  const upstreamStart = Date.now();

  const requestGroq = (fallback: boolean) => fetch(
    "https://api.groq.com/openai/v1/chat/completions",
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${groqKey}`,
        "Content-Type": "application/json",
      },
      // Bound both attempts to remain under the Edge Function request limit.
      signal: AbortSignal.timeout(45_000),
      body: JSON.stringify(fallback
        ? coachProgramFallbackRequest(model, instructions, constraints)
        : coachProgramRequest(model, instructions, constraints, schema)),
    },
  );

  let program: unknown;

  if (weekCount >= 3 && weekCount <= 8) {
    // The four-week rich schema caused Groq JSON validation failures.
    // Per-week parallel requests then consumed the available provider TPM
    // and triggered HTTP 429. Use ONE compact strict-schema call instead.
    // This preserves actual workout details, not repeated template weeks.
    let accepted = false;
    for (let attempt = 0; attempt < 2 && !accepted; attempt++) {
      const fallback = attempt === 1;
      const requestStarted = Date.now();
      let response: Response;
      try {
        response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${groqKey}`,
            "Content-Type": "application/json",
          },
          signal: AbortSignal.timeout(45_000),
          body: JSON.stringify(coachCompactProgramRequest(
            model, instructions, constraints, fallback,
          )),
        });
        await recordGroqQuota(response, "training-program-compact");
      } catch (error) {
        console.error("Coach compact provider transport failed", {
          requestId, fallback,
          failure: error instanceof DOMException && error.name === "TimeoutError"
            ? "timeout" : "transport",
          elapsedMs: Date.now() - requestStarted,
        });
        return json({
          error: "ATHLTH Coach is temporarily unavailable.",
          code: "AI_PROVIDER_UNAVAILABLE", requestId,
        }, 503);
      }

      if (response.status === 429) {
        // Never automatically retry a rate limit; preserve Groq's reset
        // guidance so clients can display a real cooldown.
        const seconds = Math.min(3600, coachProviderRetryAfter(response) + 3);
        await storeGroqCooldown(seconds);
        console.warn("Coach provider rate limit", {
          requestId, retryAfterSeconds: seconds, phase: fallback ? "json" : "strict",
        });
        return json({
          error: "ATHLTH Coach has reached the AI provider's limit. Please try later.",
          code: "AI_PROVIDER_RATE_LIMIT", retryAfterSeconds: seconds, requestId,
        }, 429, { "Retry-After": String(seconds) });
      }

      if (!response.ok) {
        const providerError = await response.json().catch(() => null);
        const code = coachProviderErrorCode(providerError);
        console.error("Coach compact provider error", {
          requestId, status: response.status, code,
          fallback, elapsedMs: Date.now() - requestStarted,
        });
        if (!fallback && coachShouldRetryInvalidSchema(response.status, providerError)) {
          // A second attempt is allowed only when Groq reports enough
          // tokens remaining. Otherwise return a cooldown; do not flood.
          const tokensHeader = response.headers.get("x-ratelimit-remaining-tokens");
          const remaining = tokensHeader === null ? NaN : Number(tokensHeader);
          if (Number.isFinite(remaining) && remaining < 1500) {
            await storeGroqCooldown(60);
            return json({
              error: "ATHLTH Coach's AI capacity is temporarily exhausted.",
              code: "AI_PROVIDER_RATE_LIMIT", retryAfterSeconds: 60, requestId,
            }, 429, { "Retry-After": "60" });
          }
          continue;
        }
        return json({
          error: "ATHLTH Coach could not generate your plan.",
          code: "AI_PROVIDER_UNAVAILABLE", requestId,
        }, 502);
      }

      const providerPayload = await response.json().catch(() => null);
      const resultText = coachProgramOutput(providerPayload);
      const rawFinishReason = providerPayload?.choices?.[0]?.finish_reason;
      const finishReason = ["stop", "length", "content_filter", "tool_calls"]
        .includes(rawFinishReason) ? rawFinishReason : "unknown";
      // Groq's plain output may have a code fence; JSON is never logged.
      const parsed = coachParseProgramText(resultText);
      const validated = coachCompactValidatedProgram(
        parsed, weekCount, preferredDays, sessionsPerWeek,
      );
      if (validated) {
        // The compact AI output sometimes exhausts its last-week token
        // budget and emits only one workout in a previously full schedule.
        // Complete that week using earlier AI-generated sessions ONLY when
        // the athlete supplied no injury/exercise restrictions. No further
        // Groq request is required, so this cannot amplify rate limits.
        const allowReuse = !constraints.injurySafetyNotes &&
          constraints.excludedMovements.length === 0;
        const repaired = coachBackfillSparseFinalWeek(
          validated, preferredDays, sessionsPerWeek, allowReuse, varyWeeks,
        );
        if (repaired.added > 0) {
          const repairedWeeks = repaired.program.weeks as {
            days: { sessions: unknown[] }[]
          }[];
          const finalCount = repairedWeeks.at(-1)?.days.reduce(
            (total, day) => total + day.sessions.length, 0,
          ) ?? 0;
          console.warn("Coach sparse final week recovered", {
            requestId, added: repaired.added, finalWeekSessions: finalCount,
          });
          const original = typeof repaired.program.summary === "string"
            ? repaired.program.summary : "";
          repaired.program.summary = (
            original + "\nFinal recovery week: " + finalCount +
            " sessions, with reduced volume where appropriate. " +
            "Additional workouts reuse earlier program sessions."
          ).trim().slice(0, 1500);
        }
        program = repaired.program;
        accepted = true;
      } else {
        // Report only non-sensitive structure diagnostics, never plan text.
        const foundWeeks = parsed && typeof parsed === "object" &&
          Array.isArray((parsed as { weeks?: unknown }).weeks)
          ? (parsed as { weeks: unknown[] }).weeks.length : 0;
        // Only log non-sensitive structural counts and provider finish code.
        // Never log generated text, injuries, athlete ID, or prompt data.
        console.error("Coach compact plan validation failed", {
          requestId, fallback, expectedWeeks: weekCount, foundWeeks,
          finishReason,
          elapsedMs: Date.now() - requestStarted,
        });
        // A retry with raw JSON rarely corrects missing weeks and may
        // consume the remaining TPM budget, so do not repeat it here.
        return json({
          error: "ATHLTH Coach returned an incomplete plan. No plan was saved.",
          code: "AI_INVALID_PROGRAM", requestId,
        }, 502);
      }
    }
    if (!accepted) {
      return json({
        error: "ATHLTH Coach could not finish a complete plan. No plan was saved.",
        code: "AI_INVALID_PROGRAM", requestId,
      }, 502);
    }
  } else {
  let aiResponse: Response;
  let fallbackUsed = false;
  try {
    aiResponse = await requestGroq(false);
    await recordGroqQuota(aiResponse, "training-program");

    if (!aiResponse.ok) {
      // Parse only the allowlisted provider error code. Do not log raw bodies:
      // they can include personal plan notes and injury restrictions.
      const firstError = await aiResponse.json().catch(() => null);
      const safeCode = coachProviderErrorCode(firstError);
      console.error("Coach upstream request rejected", {
        requestId, status: aiResponse.status, code: safeCode,
        phase: "structured", elapsedMs: Date.now() - upstreamStart,
      });
      if (coachShouldRetryInvalidSchema(aiResponse.status, firstError)) {
        fallbackUsed = true;
        // The fallback has a different response format so it can recover
        // from a Groq schema-validation failure. It is attempted at most once.
        aiResponse = await requestGroq(true);
        await recordGroqQuota(aiResponse, "training-program-fallback");
      }
    }
  } catch (error) {
    console.error("Coach upstream connection failed", {
      requestId,
      phase: fallbackUsed ? "json_fallback" : "structured",
      failure: error instanceof DOMException && error.name === "TimeoutError"
        ? "timeout" : "transport",
      elapsedMs: Date.now() - upstreamStart,
    });
    return json({
      error: "ATHLTH Coach is temporarily unavailable. Please try again.",
      code: "AI_PROVIDER_UNAVAILABLE", requestId,
    }, 503);
  }

  if (!aiResponse.ok) {
    if (aiResponse.status === 429) {
      const seconds = Math.min(3600, coachProviderRetryAfter(aiResponse) + 3);
      await storeGroqCooldown(seconds);
      console.warn("Coach provider rate limit", {
        requestId, retryAfterSeconds: seconds,
        phase: fallbackUsed ? "json" : "strict",
      });
      return json({
        error: "ATHLTH Coach's AI capacity is refreshing. Try again later.",
        code: "AI_PROVIDER_RATE_LIMIT", retryAfterSeconds: seconds, requestId,
      }, 429, { "Retry-After": String(seconds) });
    }
    const providerError = await aiResponse.json().catch(() => null);
    const code = coachProviderErrorCode(providerError);
    console.error("Coach upstream response failed", {
      requestId, phase: fallbackUsed ? "json_fallback" : "structured",
      status: aiResponse.status, code,
      elapsedMs: Date.now() - upstreamStart,
    });
    // No infinite retries, and never retry rate limits or auth failures.
    const throttled = aiResponse.status === 429;
    return json({
      error: throttled
        ? "ATHLTH Coach is busy. Try again shortly."
        : "ATHLTH Coach could not generate a program. Please try again.",
      code: throttled ? "AI_PROVIDER_RATE_LIMIT" : "AI_PROVIDER_UNAVAILABLE",
      requestId,
    }, throttled ? 429 : 502);
  }

  const payload = await aiResponse.json().catch(() => null);
  const outputText = coachProgramOutput(payload);
  if (!outputText) {
    console.error("Coach returned empty response", { requestId, fallbackUsed });
    return json({
      error: "ATHLTH Coach could not complete the plan. Try again.",
      code: "AI_INVALID_PROGRAM", requestId,
    }, 502);
  }

  program = coachParseProgramText(outputText);
  if (!program) {
    // Never log raw AI output: it can echo goals or consented limitations.
    console.error("Coach JSON parse failed", { requestId, fallbackUsed });
    return json({
      error: "ATHLTH Coach could not complete the plan. Try again.",
      code: "AI_INVALID_PROGRAM", requestId,
    }, 502);
  }

  if (!coachProgramHasUsableWeeks(program, weekCount)) {
    // Do not silently fabricate missing weeks or approve an empty plan.
    console.error("Coach plan completeness failed", {
      requestId, fallbackUsed, expectedWeeks: weekCount,
    });
    return json({
      error: "ATHLTH Coach returned an incomplete plan. No plan was saved.",
      code: "AI_INVALID_PROGRAM", requestId,
    }, 502);
  }

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
