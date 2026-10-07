import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type ExerciseCandidate = {
  exerciseID: string;
  name: string;
  bodyPart?: string | null;
  primaryMuscles?: string[];
  secondaryMuscles?: string[];
  equipment?: string[];
  category?: string | null;
  difficulty?: string | null;
};

type RecentExercise = {
  name?: string;
  primaryMuscles?: string[];
  completedSets?: number;
};

type RecentWorkout = {
  title?: string;
  daysAgo?: number;
  exercises?: RecentExercise[];
};

type RequestBody = {
  goal?: string;
  durationMinutes?: number;
  exerciseCount?: number;
  focusBodyPart?: string | null;
  personalize?: boolean;
  language?: string;
  existingExerciseIDs?: string[];
  existingExerciseNames?: string[];
  recentWorkouts?: RecentWorkout[];
  candidates?: ExerciseCandidate[];
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

const clampInteger = (
  value: unknown,
  minimum: number,
  maximum: number,
  fallback: number,
) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(Math.round(parsed), minimum), maximum);
};

const finiteNumber = (
  value: unknown,
  minimum: number,
  maximum: number,
): number | null => {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.min(Math.max(value, minimum), maximum);
};

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

async function verifyAccess(
  req: Request,
): Promise<
  | {
      ok: true;
      userID: string;
      groqKey: string;
      admin: ReturnType<typeof createClient>;
    }
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
      response: json({ error: "ATHLTH AI is unavailable." }, 503),
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
      response: json({
        error: "ATHLTH+ access could not be verified.",
      }, 503),
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
      response: json({
        error: "AI exercise selection requires ATHLTH+.",
        code: "PREMIUM_REQUIRED",
      }, 403),
    };
  }

  const budgetResponse = await enforceAIRequestBudget(() =>
    admin.rpc("consume_ai_request_budget", {
      p_user_id: user.id,
      p_feature: "strength-exercise-planner",
    })
  );

  if (budgetResponse) {
    return {
      ok: false,
      response: budgetResponse,
    };
  }

  return {
    ok: true,
    userID: user.id,
    groqKey,
    admin,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const access = await verifyAccess(req);
  if (!access.ok) return access.response;

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const candidateMap = new Map<string, ExerciseCandidate>();
  for (const candidate of (body.candidates ?? []).slice(0, 80)) {
    const exerciseID = String(candidate?.exerciseID ?? "").trim();
    const name = String(candidate?.name ?? "").trim();

    if (!exerciseID || !name || candidateMap.has(exerciseID)) {
      continue;
    }

    candidateMap.set(exerciseID, {
      exerciseID,
      name: name.slice(0, 120),
      bodyPart:
        typeof candidate?.bodyPart === "string"
          ? candidate.bodyPart.slice(0, 60)
          : null,
      primaryMuscles: Array.isArray(candidate?.primaryMuscles)
        ? candidate.primaryMuscles.slice(0, 8).map((value) =>
            String(value).slice(0, 60)
          )
        : [],
      secondaryMuscles: Array.isArray(candidate?.secondaryMuscles)
        ? candidate.secondaryMuscles.slice(0, 8).map((value) =>
            String(value).slice(0, 60)
          )
        : [],
      equipment: Array.isArray(candidate?.equipment)
        ? candidate.equipment.slice(0, 8).map((value) =>
            String(value).slice(0, 60)
          )
        : [],
      category:
        typeof candidate?.category === "string"
          ? candidate.category.slice(0, 60)
          : null,
      difficulty:
        typeof candidate?.difficulty === "string"
          ? candidate.difficulty.slice(0, 40)
          : null,
    });
  }

  const candidates = Array.from(candidateMap.values());
  if (candidates.length < 3) {
    return json({
      error: "Not enough compatible exercises are available.",
    }, 400);
  }

  const requestedCount = clampInteger(
    body.exerciseCount,
    3,
    8,
    5,
  );
  const exerciseCount = Math.min(
    requestedCount,
    candidates.length,
  );
  const durationMinutes = clampInteger(
    body.durationMinutes,
    15,
    120,
    45,
  );

  const allowedGoals = new Set([
    "general",
    "strength",
    "hypertrophy",
    "endurance",
  ]);
  const goal = allowedGoals.has(String(body.goal))
    ? String(body.goal)
    : "general";

  const language =
    String(body.language ?? "en").toLowerCase().startsWith("nb") ||
      String(body.language ?? "en").toLowerCase().startsWith("no")
      ? "Norwegian Bokmål"
      : "English";

  const existingExerciseIDs = new Set(
    (body.existingExerciseIDs ?? [])
      .map(String)
      .filter(Boolean),
  );

  const eligibleCandidates = candidates.filter(
    (candidate) => !existingExerciseIDs.has(candidate.exerciseID),
  );

  if (eligibleCandidates.length < exerciseCount) {
    return json({
      error: "Not enough unused exercises are available.",
    }, 400);
  }

  const candidateIDs =
    eligibleCandidates.map((candidate) => candidate.exerciseID);

  const schema = {
    type: "object",
    additionalProperties: false,
    required: [
      "title",
      "summary",
      "estimatedMinutes",
      "exercises",
    ],
    properties: {
      title: {
        type: "string",
        minLength: 1,
        maxLength: 80,
      },
      summary: {
        type: "string",
        minLength: 1,
        maxLength: 320,
      },
      estimatedMinutes: {
        type: "integer",
        minimum: 10,
        maximum: 120,
      },
      exercises: {
        type: "array",
        minItems: exerciseCount,
        maxItems: exerciseCount,
        items: {
          type: "object",
          additionalProperties: false,
          required: [
            "exerciseID",
            "sets",
            "reps",
            "restSeconds",
            "targetRPE",
            "reason",
          ],
          properties: {
            exerciseID: {
              type: "string",
              enum: candidateIDs,
            },
            sets: {
              type: "integer",
              minimum: 1,
              maximum: 6,
            },
            reps: {
              type: "integer",
              minimum: 4,
              maximum: 30,
            },
            restSeconds: {
              type: "integer",
              minimum: 30,
              maximum: 240,
            },
            targetRPE: {
              type: ["number", "null"],
              minimum: 5,
              maximum: 10,
            },
            reason: {
              type: "string",
              minLength: 1,
              maxLength: 160,
            },
          },
        },
      },
    },
  };

  const recentWorkouts = body.personalize === true
    ? (body.recentWorkouts ?? []).slice(0, 4).map((workout) => ({
        title: String(workout?.title ?? "").slice(0, 100),
        daysAgo: clampInteger(workout?.daysAgo, 0, 60, 0),
        exercises: Array.isArray(workout?.exercises)
          ? workout.exercises.slice(0, 10).map((exercise) => ({
              name: String(exercise?.name ?? "").slice(0, 100),
              primaryMuscles: Array.isArray(exercise?.primaryMuscles)
                ? exercise.primaryMuscles.slice(0, 8).map((value) =>
                    String(value).slice(0, 60)
                  )
                : [],
              completedSets: clampInteger(
                exercise?.completedSets,
                0,
                20,
                0,
              ),
            }))
          : [],
      }))
    : [];

  const context = {
    goal,
    durationMinutes,
    exerciseCount,
    focusBodyPart:
      typeof body.focusBodyPart === "string" &&
        body.focusBodyPart.trim()
        ? body.focusBodyPart.trim().slice(0, 60)
        : null,
    personalize: body.personalize === true,
    language,
    existingExerciseNames: (body.existingExerciseNames ?? [])
      .slice(0, 12)
      .map((value) => String(value).slice(0, 100)),
    recentWorkouts,
    candidates: eligibleCandidates,
  };

  const instructions = [
    "You are ATHLTH AI, selecting exercises for one strength workout.",
    "Use only exerciseID values provided in candidates.",
    "Every selected exerciseID must be unique.",
    "Do not invent exercises, IDs, weights, injuries, diagnoses, recovery scores, or medical facts.",
    "Existing exercises are already in the workout. Complement them and do not choose duplicates.",
    "Use recentWorkouts only when personalize is true. Recent history can reduce unnecessary repetition, but it does not prove fatigue, soreness, injury, or recovery state.",
    "Respect the requested goal, time, focus and exercise count.",
    "Prefer a balanced ordering: larger compound movements earlier when appropriate, smaller accessory work later.",
    "For strength: generally favor lower-to-moderate reps and longer rests.",
    "For hypertrophy: generally favor moderate reps and moderate rests.",
    "For endurance: generally favor higher reps and shorter rests.",
    "For general: use a practical balanced prescription.",
    "Never prescribe target weight. Sets, reps, rest and optional RPE only.",
    "Keep estimatedMinutes realistic for the prescriptions.",
    "Write title, summary and each reason in " + language + ".",
    "Reasons should be concise and explain the exercise's role in this specific session.",
  ].join("\n");

  const aiResponse = await fetch(
    "https://api.groq.com/openai/v1/responses",
    {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + access.groqKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model:
          Deno.env.get("GROQ_TRAINING_MODEL") ??
          "openai/gpt-oss-120b",
        reasoning: {
          effort: "low",
        },
        instructions,
        input: JSON.stringify(context),
        text: {
          format: {
            type: "json_schema",
            name: "athlth_strength_session",
            strict: true,
            schema,
          },
        },
      }),
    },
  );

  if (!aiResponse.ok) {
    const failure = await aiResponse.text();
    console.error("Strength session generation failed", {
      userID: access.userID,
      status: aiResponse.status,
      body: failure.slice(0, 1400),
    });
    return json({
      error: "ATHLTH AI could not build the strength session.",
    }, 502);
  }

  const payload = await aiResponse.json();
  const output = extractOutputText(payload);

  if (!output) {
    return json({
      error: "ATHLTH AI returned no strength session.",
    }, 502);
  }

  let generated: any;
  try {
    generated = JSON.parse(output);
  } catch {
    return json({
      error: "ATHLTH AI returned an invalid strength session.",
    }, 502);
  }

  const seen = new Set<string>();
  const exercises = Array.isArray(generated?.exercises)
    ? generated.exercises
        .filter((exercise: any) => {
          const id = String(exercise?.exerciseID ?? "");
          if (!candidateMap.has(id) || seen.has(id)) return false;
          seen.add(id);
          return true;
        })
        .slice(0, exerciseCount)
        .map((exercise: any) => ({
          exerciseID: String(exercise.exerciseID),
          sets: clampInteger(exercise.sets, 1, 6, 3),
          reps: clampInteger(exercise.reps, 4, 30, 8),
          restSeconds: clampInteger(exercise.restSeconds, 30, 240, 90),
          targetRPE: finiteNumber(exercise.targetRPE, 5, 10),
          reason: String(exercise.reason ?? "").slice(0, 160),
        }))
    : [];

  if (exercises.length !== exerciseCount) {
    return json({
      error: "ATHLTH AI did not return enough valid exercises.",
    }, 502);
  }

  return json({
    title: String(generated?.title ?? "ATHLTH AI Strength").slice(0, 80),
    summary: String(generated?.summary ?? "").slice(0, 320),
    estimatedMinutes: clampInteger(
      generated?.estimatedMinutes,
      10,
      120,
      durationMinutes,
    ),
    exercises,
  });
});
