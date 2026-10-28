import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";
import {
  canForwardRecoveryHealth,
  mustRejectUnconsentedInsight,
  mustRejectUnreleasedAutomaticCoachSharing,
} from "../_shared/recovery-privacy.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type RecoveryContext = {
  recoveryScore?: number | null;
  evidence?: {
    capturedAt?: string | null;
    sleepEndedAt?: string | null;
    hrvSampledAt?: string | null;
    restingPulseSampledAt?: string | null;
  } | null;
  recoveryState?: string;
  recoveryDetail?: string;
  sleepSeconds?: number | null;
  baselineSleepSeconds?: number | null;
  hrvMilliseconds?: number | null;
  baselineHRVMilliseconds?: number | null;
  restingHeartRate?: number | null;
  baselineRestingHeartRate?: number | null;
  yesterdayTrainingMinutes?: number;
  acuteTrainingMinutes?: number;
  chronicWeeklyAverageMinutes?: number | null;
  muscles?: Array<{
    name: string;
    recoveryPercent: number;
    status: string;
    completedSets: number;
  }>;
  checkIn?: {
    energy?: number | null;
    stress?: number | null;
    overallSoreness?: number | null;
    motivation?: number | null;
  };
};

type RecoveryChatTurn = {
  role?: "user" | "assistant";
  content?: string;
};

type RecoveryRequest = {
  mode?: "insight" | "ask";
  context?: RecoveryContext;
  question?: string | null;
  language?: "en" | "nb";
  history?: RecoveryChatTurn[];
  // Explicitly set true only after the user confirms sending health data.
  shareHealthData?: boolean;
  // Mandatory future-mode signal. Automatic transport is not released.
  healthSharingMode?: "confirmEachQuestion" | "automatic";
  // Structured, consented strength evidence: never included without this turn's health approval.
  coachStrengthContext?: unknown;
  // Bounded recorded running results, forwarded only on this turn's consent.
  coachRunningContext?: unknown;
  coachTrainingContext?: unknown;
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

const chatReplySchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "answer",
    "quickQuestions",
    "proposal",
  ],
  properties: {
    answer: {
      type: "string",
    },
    quickQuestions: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: { type: "string" },
    },
    proposal: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          additionalProperties: false,
          required: [
            "kind", "title", "summary", "activity",
            "durationMinutes", "weekCount", "sessionsPerWeek", "steps"
          ],
          properties: {
            kind: { type: "string", enum: ["workout", "plan"] },
            title: { type: "string" },
            summary: { type: "string" },
            activity: { type: "string", enum: ["running", "strength", "walking", "hybrid"] },
            durationMinutes: { type: "integer", minimum: 10, maximum: 180 },
            weekCount: { type: "integer", minimum: 1, maximum: 52 },
            sessionsPerWeek: { type: "integer", minimum: 1, maximum: 7 },
            steps: {
              type: "array", maxItems: 20,
              items: {
                type: "object",
                additionalProperties: false,
                required: ["title", "phase", "minutes", "sets", "repetitions", "restSeconds"],
                properties: {
                  title: { type: "string" },
                  phase: { type: "string", enum: ["warmup", "main", "recovery", "cooldown"] },
                  minutes: { type: "integer", minimum: 0, maximum: 180 },
                  sets: { type: "integer", minimum: 0, maximum: 20 },
                  repetitions: { type: "integer", minimum: 0, maximum: 100 },
                  restSeconds: { type: "integer", minimum: 0, maximum: 600 },
                },
              },
            },
          },
        },
      ],
    },
  },
};

const insightSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "headline",
    "summary",
    "factors",
    "suggestion",
    "quickQuestions",
  ],
  properties: {
    headline: { type: "string" },
    summary: { type: "string" },
    factors: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "detail", "impact"],
        properties: {
          title: { type: "string" },
          detail: { type: "string" },
          impact: {
            type: "string",
            enum: ["positive", "neutral", "negative"],
          },
        },
      },
    },
    suggestion: {
      type: "object",
      additionalProperties: false,
      required: ["title", "subtitle", "reason"],
      properties: {
        title: { type: "string" },
        subtitle: { type: "string" },
        reason: { type: "string" },
      },
    },
    quickQuestions: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: { type: "string" },
    },
  },
};

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

  if (!supabaseURL || !serviceRoleKey) {
    return {
      ok: false,
      response: json({ error: "ATHLTH backend is unavailable." }, 503),
    };
  }

  if (!groqKey) {
    return {
      ok: false,
      response: json(
        {
          error: "ATHLTH AI is not configured yet.",
          code: "AI_NOT_CONFIGURED",
        },
        503,
      ),
    };
  }

  const token = authorization.slice(7).trim();
  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: userError } = await admin.auth.getUser(token);
  if (userError || !user) {
    return {
      ok: false,
      response: json(
        { error: "Your sign-in session is no longer valid." },
        401,
      ),
    };
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
    return {
      ok: false,
      response: json(
        {
          error: "ATHLTH+ access could not be verified. Please try again.",
          code: "ENTITLEMENT_CHECK_FAILED",
        },
        503,
      ),
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
          error: "ATHLTH Coach requires an active ATHLTH+ plan or trial.",
          code: "PREMIUM_REQUIRED",
        },
        403,
      ),
    };
  }

  const budgetResponse = await enforceAIRequestBudget(() => admin.rpc("consume_ai_request_budget", {
    p_user_id: user.id, p_feature: "recovery-sense",
  }));
  if (budgetResponse) return { ok: false, response: budgetResponse };

  return { ok: true, userID: user.id, groqKey };
}

function sanitizeContext(input: RecoveryContext | undefined, requireEvidence = false) {
  const context = input ?? {};
  const now = Date.now();
  const timestamp = (text: unknown): number | null => {
    if (typeof text !== "string") return null;
    const parsed = Date.parse(text);
    return Number.isFinite(parsed) ? parsed : null;
  };
  const captured = timestamp(context.evidence?.capturedAt);
  const captureValid = captured != null &&
    now - captured >= -5 * 60_000 && now - captured <= 15 * 60_000;
  const fresh = (text: unknown, hours: number): boolean => {
    if (!requireEvidence) return true;
    if (!captureValid) return false;
    const time = timestamp(text);
    return time != null && now - time >= -5 * 60_000 &&
      now - time <= hours * 3_600_000;
  };
  const freshSleep = fresh(context.evidence?.sleepEndedAt, 48);
  const freshHRV = fresh(context.evidence?.hrvSampledAt, 72);
  const freshRHR = fresh(context.evidence?.restingPulseSampledAt, 72);
  const readyHasSources = freshSleep || freshHRV || freshRHR;

  return {
    sources: {
      collectedAt: captureValid ? context.evidence?.capturedAt ?? null : null,
      sleepEndedAt: freshSleep ? context.evidence?.sleepEndedAt ?? null : null,
      hrvSampledAt: freshHRV ? context.evidence?.hrvSampledAt ?? null : null,
      restingPulseSampledAt: freshRHR
        ? context.evidence?.restingPulseSampledAt ?? null : null,
      verified: !requireEvidence || captureValid,
    },
    recoveryScore:
      readyHasSources && typeof context.recoveryScore === "number"
        ? Math.max(0, Math.min(100, Math.round(context.recoveryScore)))
        : null,
    recoveryState: readyHasSources
      ? String(context.recoveryState ?? "").slice(0, 80) : "Recent data unavailable",
    recoveryDetail: readyHasSources
      ? "Locally calculated, approximate readiness. Use only the dated sample fields and never infer missing signals."
      : "No verified recent HealthKit readings available for a current readiness estimate.",
    sleepSeconds:
      freshSleep && typeof context.sleepSeconds === "number"
        ? Math.max(0, Math.min(context.sleepSeconds, 86400))
        : null,
    baselineSleepSeconds:
      freshSleep && typeof context.baselineSleepSeconds === "number"
        ? Math.max(0, Math.min(context.baselineSleepSeconds, 86400))
        : null,
    hrvMilliseconds:
      freshHRV && typeof context.hrvMilliseconds === "number"
        ? Math.max(0, Math.min(context.hrvMilliseconds, 1000))
        : null,
    baselineHRVMilliseconds:
      freshHRV && typeof context.baselineHRVMilliseconds === "number"
        ? Math.max(0, Math.min(context.baselineHRVMilliseconds, 1000))
        : null,
    restingHeartRate:
      freshRHR && typeof context.restingHeartRate === "number"
        ? Math.max(20, Math.min(context.restingHeartRate, 240))
        : null,
    baselineRestingHeartRate:
      freshRHR && typeof context.baselineRestingHeartRate === "number"
        ? Math.max(20, Math.min(context.baselineRestingHeartRate, 240))
        : null,
    yesterdayTrainingMinutes:
      typeof context.yesterdayTrainingMinutes === "number"
        ? Math.max(0, Math.min(context.yesterdayTrainingMinutes, 1440))
        : 0,
    acuteTrainingMinutes:
      typeof context.acuteTrainingMinutes === "number"
        ? Math.max(0, Math.min(context.acuteTrainingMinutes, 10080))
        : 0,
    chronicWeeklyAverageMinutes:
      typeof context.chronicWeeklyAverageMinutes === "number"
        ? Math.max(0, Math.min(context.chronicWeeklyAverageMinutes, 10080))
        : null,
    muscles: Array.isArray(context.muscles)
      ? context.muscles.slice(0, 10).map((muscle) => ({
          name: String(muscle?.name ?? "").slice(0, 80),
          recoveryPercent: Math.max(
            0,
            Math.min(100, Math.round(Number(muscle?.recoveryPercent ?? 0))),
          ),
          status: String(muscle?.status ?? "").slice(0, 80),
          completedSets: Math.max(
            0,
            Math.min(100, Math.round(Number(muscle?.completedSets ?? 0))),
          ),
        }))
      : [],
    checkIn: {
      energy: context.checkIn?.energy ?? null,
      stress: context.checkIn?.stress ?? null,
      overallSoreness: context.checkIn?.overallSoreness ?? null,
      motivation: context.checkIn?.motivation ?? null,
    },
  };
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

function normalizeCoachRunningContext(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const obj = value as Record<string, unknown>;
  if (obj.windowDays !== 56) return null;
  const count = (v: unknown, max: number) => {
    const n = Number(v);
    return Number.isFinite(n) ? Math.min(max, Math.max(0, Math.round(n))) : 0;
  };
  const raw = Array.isArray(obj.recentRuns) ? obj.recentRuns.slice(0, 8) : [];
  const recentRuns = raw.flatMap((item: unknown) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return [];
    const run = item as Record<string, unknown>;
    const title = typeof run.title === "string" ? run.title.trim().slice(0, 90) : "";
    if (!title || /[<>{}\n\r]/.test(title)) return [];
    const pace = Number(run.averageWorkPaceSecondsPerKilometer);
    return [{
      title,
      daysAgo: count(run.daysAgo, 56),
      durationMinutes: count(run.durationMinutes, 1_000),
      averageWorkPaceSecondsPerKilometer:
        run.averageWorkPaceSecondsPerKilometer == null ||
        !Number.isFinite(pace) || pace < 120 || pace > 3_600 ? null : Math.round(pace),
      wasUserReported: run.wasUserReported === true,
    }];
  });
  return {
    windowDays: 56,
    completedRuns: count(obj.completedRuns, 1_000),
    runsLastSevenDays: count(obj.runsLastSevenDays, 200),
    recentRuns,
  };
}

function normalizeCoachTrainingContext(input: unknown) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  const obj = input as Record<string, unknown>;
  const clean = (value: unknown, limit = 100) =>
    typeof value === "string" && !/[<>{}\n\r]/.test(value)
      ? value.trim().slice(0, limit) : "";
  const upcoming = Array.isArray(obj.upcoming) ? obj.upcoming.slice(0, 12)
    .flatMap((entry: unknown) => {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) return [];
      const event = entry as Record<string, unknown>;
      const title = clean(event.title);
      const date = clean(event.date, 40);
      const activity = clean(event.activity, 30);
      if (!title || !/^\d{4}-\d{2}-\d{2}T/.test(date)) return [];
      const rawDuration = Number(event.durationMinutes);
      return [{
        title, activity, date,
        durationMinutes: event.durationMinutes == null ||
          !Number.isFinite(rawDuration) ? null :
          Math.min(480, Math.max(0, Math.round(rawDuration))),
      }];
    }) : [];
  return {
    planTitle: clean(obj.planTitle) || null,
    planVersion: typeof obj.planVersion === "number" &&
      Number.isFinite(obj.planVersion) ? Math.max(0, Math.round(obj.planVersion)) : null,
    upcoming,
    goalTitles: (Array.isArray(obj.goalTitles) ? obj.goalTitles : [])
      .slice(0, 6).map((goal: unknown) => clean(goal)).filter(Boolean),
  };
}

function sanitizeHistory(
  input: RecoveryChatTurn[] | undefined,
) {
  if (!Array.isArray(input)) return [];

  return input
    .slice(-16)
    .map((turn) => {
      const role =
        turn?.role === "assistant"
          ? "assistant"
          : "user";
      const content =
        String(turn?.content ?? "")
          .trim()
          .slice(0, 1800);

      return {
        role,
        content,
      };
    })
    .filter((turn) => turn.content.length > 0);
}

function requestsPersonalMeasurements(question: string): boolean {
  const text = question.toLocaleLowerCase();
  const measurements = /(søvn|sovet|søvnkvalitet|hrv|hvilepuls|restitusjon|dagsform|sleep|resting heart rate|readiness|recovery score)/i.test(text);
  const personalized = /(mitt|mine|min |jeg |meg |siste nettene|siste natt|my |i slept|did i|last nights?|my recent|hvordan har|hvor mye|what was|how was|how have i)/i.test(text);
  return measurements && personalized;
}

const sharedInstructions = `
You are ATHLTH Coach, a unified assistant for strength, running, cycling, training plans and recovery inside a fitness app.
For Insight requests, focus on recovery interpretation. For user questions, respond as a complete fitness coach.
Use only the data supplied in the request.

Important:
- You provide general fitness and recovery guidance, not medical diagnosis or treatment.
- Never invent symptoms, injuries, illnesses, medications, lab values or personal history.
- Avoid certainty. Recovery and muscle-recovery values are estimates from consumer wearable/training data.
- Treat the user's own report of soreness, pain or readiness as essential context. Do not override what the user feels based only on estimated recovery percentages. Adapt the proposed workout accordingly.
- Prefer the user's own baselines over generic population norms.
- When data is missing, say it is missing rather than guessing.
- Every personal recovery number requires current, source-dated evidence. Never claim a timestamp or a sleep/HRV/RHR number that is not supplied in the sanitized context.
- Do not confuse a calculated readiness score with a directly observed physiological measurement. Distinguish baselines from last-night readings and explicitly state unavailable/stale values.
- Keep language concise, calm and useful.
- Do not tell the user that a medical condition explains the data.
- If the supplied data is concerning only in a general sense, recommend reducing training load or seeking appropriate professional advice if they feel unwell, without diagnosing.
`.trim();

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const access = await verifyPlus(req);
  if (!access.ok) return access.response;

  let body: RecoveryRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  // Enforce the consent boundary at the API, not only in SwiftUI.
  // Old clients that omit shareHealthData must never disclose metrics.
  if (body.mode !== "ask" && body.mode !== "insight") {
    return json({ error: "Unsupported recovery request." }, 400);
  }
  if (mustRejectUnconsentedInsight(body.mode, body.shareHealthData)) {
    return json({ error: "Explicit Insights health permission required." }, 403);
  }
  if (mustRejectUnreleasedAutomaticCoachSharing(
    body.mode, body.healthSharingMode,
  )) {
    return json({ error: "Automatic Coach health sharing is not released." }, 403);
  }
  const canShareHealth = canForwardRecoveryHealth(body.shareHealthData);
  const context = sanitizeContext(
    canShareHealth ? body.context : undefined,
    body.mode === "ask",
  );
  const coachStrengthContext =
    canShareHealth && body.mode === "ask"
      ? normalizeCoachStrengthContext(body.coachStrengthContext)
      : null;
  const coachRunningContext =
    canShareHealth && body.mode === "ask"
      ? normalizeCoachRunningContext(body.coachRunningContext)
      : null;
  const coachTrainingContext =
    canShareHealth && body.mode === "ask"
      ? normalizeCoachTrainingContext(body.coachTrainingContext)
      : null;
  const responseLanguage =
    body.language === "nb" ? "Norwegian Bokmål" : "English";
  const languageInstruction =
    `\nWrite every user-visible response in ${responseLanguage}. Keep metric abbreviations such as HRV and bpm unchanged.`;

  if (body.mode === "ask") {
    const question = String(body.question ?? "").trim().slice(0, 1200);
    if (!question) {
      return json({ error: "Ask a recovery question first." }, 400);
    }

    // Earlier replies may contain health context. Include them only when
    // the user explicitly approves this particular health-aware request.
    const history = body.shareHealthData === true
      ? sanitizeHistory(body.history)
      : [];

    // Never ask a language model to fill in personal measurements when the
    // athlete has not authorized forwarding those measurements in this turn.
    // A guaranteed, deterministic answer prevents invented sleep/HRV/RHR.
    if (!canShareHealth && requestsPersonalMeasurements(question)) {
      const norwegian = body.language === "nb";
      return json({
        answer: norwegian
          ? "Jeg har ikke fått tilgang til helsemålingene dine i dette spørsmålet, så jeg kan ikke si hvordan søvn, HRV eller restitusjon faktisk har vært. Du kan velge å dele helse- og treningsdata for dette spørsmålet, eller jeg kan gi generelle treningsråd uten personlige tall."
          : "I don't have your health measurements for this question, so I can't verify how your sleep, HRV or recovery has been. You can approve sharing health and training data for this question, or I can give general training guidance without personal figures.",
        quickQuestions: norwegian
          ? ["Hvordan deler jeg helsedata for ett spørsmål?", "Hvordan påvirker lite søvn trening generelt?", "Lag en rolig økt uten personlige helsedata"]
          : ["How can I share health data for one question?", "How does short sleep affect training?", "Create an easy workout without personal health data"],
        proposal: null,
      });
    }

    const response = await fetch("https://api.groq.com/openai/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${access.groqKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("GROQ_TRAINING_MODEL") ?? "openai/gpt-oss-120b",
        reasoning: { effort: "medium" },
        instructions:
          sharedInstructions +
          languageInstruction +
          `
You are continuing an ATHLTH Coach conversation.
- Use the supplied conversation history to understand follow-up questions and references such as "that", "tomorrow", or "what about strength?".
- Answer the latest question directly in 2-5 short sentences.
- If no recovery metrics were shared, say you do not have access to personal health data for this question. Never infer or invent such metrics.
- Make the relationship to the supplied recovery data clear when relevant.
- When coachStrengthContext is present, base strength advice on confirmed sets and exercise trends, never invented personal records. No weight changes without approval.
- When coachRunningContext is present, use only confirmed completed runs, elapsed durations and measured pace samples, distinguishing manually reported from observed evidence. Never invent missing paces, route distances or personal bests.
- Do not infer that missing strength metrics imply the athlete has not exercised. Explain data limitations and account for running/cycling and recovery instead of prescribing strength in isolation.
- User consent for this question governs coachStrengthContext, coachRunningContext and coachTrainingContext. When absent, do not claim access to the current training plan, goals, strength or running history. Do not expose raw input context verbatim unless the athlete requests it.
- With coachTrainingContext, base plan-aware advice on actual upcoming sessions and recorded goal titles. Do not infer an active plan when planTitle is null, or treat a suggested exercise as already scheduled.
- You can propose structured workouts and plan briefs. The app will validate and let the athlete approve every add/save action; never claim an action was performed.
- For requests to build a specific workout, include a proposal with kind workout and 2-12 realistic ordered steps. For running, include warmup/work/cooldown and duration minutes; for strength include named exercises, sets, repetitions and rest; never invent the athlete's working weights or target pace. A step is an exercise or run segment, not prose. No medical guarantees.
- For requests to build a training program, include a plan proposal with title, activity, duration per session, weeks and weekly frequency. The ATHLTH plan builder will flesh it out after the athlete approves. Set steps [] for plan.
- If the request is only a question, advice, an injury assessment or an adjustment without a clear draft request, return proposal null. If details are insufficient for a safely usable workout, ask a follow-up question instead of guessing.
- When health data is not shared, never assert personal sleep, HRV, RHR, readiness score or muscle-recovery values from old conversation content. Previously mentioned numbers are not verified current measurements.
- Do not repeat information from earlier answers unless it helps answer the latest question.
- Return exactly three short follow-up questions that are useful next steps based on today's recovery context and the conversation so far.
- Follow-up questions must be meaningfully different from questions the user already asked.
- Prioritize decisions the user could reasonably make next: training intensity, recovery, sleep, muscle readiness, workload, or tomorrow's plan.
`,
        input: JSON.stringify({
          context,
          coachStrengthContext,
          coachRunningContext,
          coachTrainingContext,
          history,
          question,
        }),
        text: {
          format: {
            type: "json_schema",
            name: "athlth_recovery_chat_reply",
            strict: true,
            schema: chatReplySchema,
          },
        },
      }),
    });

    await recordGroqQuota(response, "recovery-ask");

    if (!response.ok) {
      // Provider error payloads may echo sensitive prompt content.
      // Never persist them or generated health text in server logs.
      console.error("ATHLTH Coach ask failed", {
        status: response.status,
      });
      return json({ error: "ATHLTH Coach is temporarily unavailable." }, 502);
    }

    const payload = await response.json();
    const outputText = extractOutputText(payload)?.trim();
    if (!outputText) {
      return json({ error: "ATHLTH Coach returned an empty answer." }, 502);
    }

    try {
      const parsed = JSON.parse(outputText);
      const answer = String(parsed?.answer ?? "").trim().slice(0, 1800);
      const quickQuestions = Array.isArray(parsed?.quickQuestions)
        ? parsed.quickQuestions
            .map((item: unknown) => String(item ?? "").trim().slice(0, 300))
            .filter((item: string) => item.length > 0)
            .slice(0, 3)
        : [];

      if (!answer || quickQuestions.length !== 3) {
        throw new Error("Incomplete chat reply.");
      }

      const rawProposal = parsed?.proposal;
      const validActivity = new Set(["running", "strength", "walking", "hybrid"]);
      const validPhase = new Set(["warmup", "main", "recovery", "cooldown"]);
      let proposal: Record<string, unknown> | null = null;
      if (rawProposal && typeof rawProposal === "object" &&
          (rawProposal.kind === "workout" || rawProposal.kind === "plan") &&
          validActivity.has(rawProposal.activity) &&
          typeof rawProposal.title === "string" &&
          rawProposal.title.trim().length > 2) {
        const steps = Array.isArray(rawProposal.steps)
          ? rawProposal.steps.slice(0, 20).flatMap((step: any) => {
            if (typeof step?.title !== "string" ||
                !step.title.trim() ||
                !validPhase.has(step.phase)) return [];
            return [{
              title: step.title.trim().slice(0, 110),
              phase: step.phase,
              minutes: Math.min(180, Math.max(0, Math.round(Number(step.minutes) || 0))),
              sets: Math.min(20, Math.max(0, Math.round(Number(step.sets) || 0))),
              repetitions: Math.min(100, Math.max(0, Math.round(Number(step.repetitions) || 0))),
              restSeconds: Math.min(600, Math.max(0, Math.round(Number(step.restSeconds) || 0))),
            }];
          }) : [];
        if (rawProposal.kind === "plan" || steps.length > 0) {
          proposal = {
            kind: rawProposal.kind,
            title: rawProposal.title.trim().slice(0, 110),
            summary: String(rawProposal.summary ?? "").trim().slice(0, 700),
            activity: rawProposal.activity,
            durationMinutes: Math.min(180, Math.max(10, Math.round(Number(rawProposal.durationMinutes) || 45))),
            weekCount: Math.min(52, Math.max(1, Math.round(Number(rawProposal.weekCount) || 8))),
            sessionsPerWeek: Math.min(7, Math.max(1, Math.round(Number(rawProposal.sessionsPerWeek) || 3))),
            steps,
          };
        }
      }
      return json({ answer, quickQuestions, proposal });
    } catch (error) {
      console.error("Unable to parse ATHLTH Coach chat reply", {
        kind: "invalid_response_format",
      });
      return json({ error: "ATHLTH Coach returned an invalid answer." }, 502);
    }
  }

  const response = await fetch("https://api.groq.com/openai/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${access.groqKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("GROQ_TRAINING_MODEL") ?? "openai/gpt-oss-120b",
      reasoning: { effort: "medium" },
      instructions:
        sharedInstructions +
        languageInstruction +
        `
Create today's Recovery insight.
- headline: short and specific.
- summary: 2-3 concise sentences explaining the overall picture.
- factors: the 1-3 signals that matter most today. Use impact positive/neutral/negative.
- suggestion: one practical training/recovery direction for today. It must remain a suggestion, not an instruction.
- quickQuestions: three short useful follow-up questions the user could ask ATHLTH.
`,
      input: JSON.stringify(context),
      text: {
        format: {
          type: "json_schema",
          name: "athlth_recovery_insight",
          strict: true,
          schema: insightSchema,
        },
      },
    }),
  });

  await recordGroqQuota(response, "recovery-insight");

  if (!response.ok) {
    console.error("ATHLTH Coach insight failed", {
      status: response.status,
    });
    return json({ error: "ATHLTH Coach is temporarily unavailable." }, 502);
  }

  const payload = await response.json();
  const outputText = extractOutputText(payload);
  if (!outputText) {
    return json({ error: "ATHLTH Coach returned an empty insight." }, 502);
  }

  try {
    return json(JSON.parse(outputText));
  } catch {
    console.error("Unable to parse ATHLTH Coach insight", {
      kind: "invalid_response_format",
    });
    return json({ error: "ATHLTH Coach returned an invalid insight." }, 502);
  }
});
