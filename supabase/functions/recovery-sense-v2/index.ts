import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";
import {
  canForwardRecoveryHealth,
  mustRejectUnconsentedInsight,
  mustRejectUnreleasedAutomaticCoachSharing,
} from "../_shared/recovery-privacy.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type RecoveryContext = {
  recoveryScore?: number | null;
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
  ],
  properties: {
    answer: {
      type: "string",
    },
    quickQuestions: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: {
        type: "string",
      },
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

function sanitizeContext(input: RecoveryContext | undefined) {
  const context = input ?? {};

  return {
    recoveryScore:
      typeof context.recoveryScore === "number"
        ? Math.max(0, Math.min(100, Math.round(context.recoveryScore)))
        : null,
    recoveryState: String(context.recoveryState ?? "").slice(0, 80),
    recoveryDetail: String(context.recoveryDetail ?? "").slice(0, 1200),
    sleepSeconds:
      typeof context.sleepSeconds === "number"
        ? Math.max(0, Math.min(context.sleepSeconds, 86400))
        : null,
    baselineSleepSeconds:
      typeof context.baselineSleepSeconds === "number"
        ? Math.max(0, Math.min(context.baselineSleepSeconds, 86400))
        : null,
    hrvMilliseconds:
      typeof context.hrvMilliseconds === "number"
        ? Math.max(0, Math.min(context.hrvMilliseconds, 1000))
        : null,
    baselineHRVMilliseconds:
      typeof context.baselineHRVMilliseconds === "number"
        ? Math.max(0, Math.min(context.baselineHRVMilliseconds, 1000))
        : null,
    restingHeartRate:
      typeof context.restingHeartRate === "number"
        ? Math.max(20, Math.min(context.restingHeartRate, 240))
        : null,
    baselineRestingHeartRate:
      typeof context.baselineRestingHeartRate === "number"
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
  );
  const coachStrengthContext =
    canShareHealth && body.mode === "ask"
      ? normalizeCoachStrengthContext(body.coachStrengthContext)
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
- When coachStrengthContext is present, you are ATHLTH's evidence-first strength AND endurance coach: base strength advice on actual confirmed working sets, exercise history, trend, prescribed load vs estimated 1RM, not invented personal records. Two successful sessions may warrant reviewing a modest increase but NEVER applying changes. Plateau is a discussion prompt, not a diagnosis.
- Do not infer that missing strength metrics imply the athlete has not exercised. Explain data limitations and account for running/cycling and recovery instead of prescribing strength in isolation.
- User consent for this question governs coachStrengthContext. When absent, do not claim access to strength history. Do not expose raw input context back verbatim unless needed for the requested recommendation.
- You cannot change, activate or save training plans through this chat; offer the athlete an editable plan review with explicit approval instead.
- Do not repeat information from earlier answers unless it helps answer the latest question.
- Return exactly three short follow-up questions that are useful next steps based on today's recovery context and the conversation so far.
- Follow-up questions must be meaningfully different from questions the user already asked.
- Prioritize decisions the user could reasonably make next: training intensity, recovery, sleep, muscle readiness, workload, or tomorrow's plan.
`,
        input: JSON.stringify({
          context,
          coachStrengthContext,
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

      return json({
        answer,
        quickQuestions,
      });
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
