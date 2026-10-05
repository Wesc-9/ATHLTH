import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";
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
You are ATHLTH Coach, the recovery interpretation layer inside a fitness app.
Use only the data supplied in the request.

Important:
- You provide general fitness and recovery guidance, not medical diagnosis or treatment.
- Never invent symptoms, injuries, illnesses, medications, lab values or personal history.
- Avoid certainty. Recovery and muscle-recovery values are estimates from consumer wearable/training data.
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

  const context = sanitizeContext(body.context);
  const responseLanguage =
    body.language === "nb" ? "Norwegian Bokmål" : "English";
  const languageInstruction =
    `\nWrite every user-visible response in ${responseLanguage}. Keep metric abbreviations such as HRV and bpm unchanged.`;

  if (body.mode === "ask") {
    const question = String(body.question ?? "").trim().slice(0, 1200);
    if (!question) {
      return json({ error: "Ask a recovery question first." }, 400);
    }

    const history = sanitizeHistory(body.history);

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
- Make the relationship to the supplied recovery data clear when relevant.
- Do not repeat information from earlier answers unless it helps answer the latest question.
- Return exactly three short follow-up questions that are useful next steps based on today's recovery context and the conversation so far.
- Follow-up questions must be meaningfully different from questions the user already asked.
- Prioritize decisions the user could reasonably make next: training intensity, recovery, sleep, muscle readiness, workload, or tomorrow's plan.
`,
        input: JSON.stringify({
          context,
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
      const failure = await response.text();
      console.error("ATHLTH Coach ask failed", {
        userID: access.userID,
        status: response.status,
        body: failure.slice(0, 1500),
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
        userID: access.userID,
        output: outputText.slice(0, 1500),
        message:
          error instanceof Error
            ? error.message
            : String(error),
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
    const failure = await response.text();
    console.error("ATHLTH Coach insight failed", {
      userID: access.userID,
      status: response.status,
      body: failure.slice(0, 1500),
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
      userID: access.userID,
      output: outputText.slice(0, 1500),
    });
    return json({ error: "ATHLTH Coach returned an invalid insight." }, 502);
  }
});
