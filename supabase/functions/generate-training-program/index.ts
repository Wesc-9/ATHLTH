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
  preferredDays?: number[];
  sessionDurationMinutes?: number;
  userNotes?: string;
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
  const openAIKey = Deno.env.get("OPENAI_API_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "ATHLTH backend is unavailable." }, 503);
  }

  if (!openAIKey) {
    return json({
      error: "AI program generation is not configured yet.",
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
  const sessionDurationMinutes = clampInteger(
    body.sessionDurationMinutes,
    20,
    180,
    60,
  );
  const goals = Array.isArray(body.goals) ? body.goals.slice(0, 8) : [];
  if (goals.length === 0) {
    return json({ error: "Choose at least one goal." }, 400);
  }

  const existingDays = Array.isArray(body.existingDays)
    ? body.existingDays.slice(0, 52 * 7)
    : [];

  const constraints = {
    mode,
    startDate: body.startDate ?? null,
    weekCount,
    sessionsPerWeek,
    preferredDays,
    preferredDayNames: preferredDays.map((day) => DAY_NAMES[day - 1]),
    sessionDurationMinutes,
    userNotes: String(body.userNotes ?? "").slice(0, 3000),
    goals,
    existingDays: mode === "complete" ? existingDays : [],
  };

  const instructions = `
You are ATHLTH AI, a conservative training-program planning assistant.
Create a practical general-fitness program from the user's explicit goals and constraints.

Hard rules:
- Return exactly the requested number of weeks.
- Every week must contain all seven days, dayIndex 1=Monday through 7=Sunday.
- Schedule at most one workout on a day and no more than sessionsPerWeek workouts per week.
- Schedule workouts only on preferredDays.
- In complete mode, days that already contain existingSessions are locked: return zero generated sessions for those days.
- Do not invent personal medical conditions, diagnoses, injuries, medications, or lab values.
- Do not promise that a goal will be achieved by a deadline.
- Use conservative progression, recovery, and rest. Avoid repeated maximal-effort sessions.
- If a goal or note suggests a medical limitation, keep recommendations general and low-risk rather than treating the condition.
- Strength work should use exercise names, sets, reps, sensible RPE, and rest, but never invent target weights.
- Running/walking sessions can include duration and/or distance. Only include a target pace when the provided goal genuinely supports one.
- Use the user's goal deadlines and milestones as context, but do not exceed the explicit timeline.
- The output is a draft the user will review before applying.
`.trim();

  const aiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_TRAINING_MODEL") ?? "gpt-5.6-terra",
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

  if (!aiResponse.ok) {
    const failure = await aiResponse.text();
    console.error("OpenAI program generation failed", {
      status: aiResponse.status,
      body: failure.slice(0, 2000),
      userID: user.id,
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
    console.error("Unable to parse structured AI program", {
      userID: user.id,
      output: outputText.slice(0, 2000),
    });
    return json({ error: "AI returned an invalid program." }, 502);
  }

  return json(
    normalizeProgram(
      program,
      weekCount,
      preferredDays,
      sessionsPerWeek,
      existingDays,
      mode,
    ),
  );
});
