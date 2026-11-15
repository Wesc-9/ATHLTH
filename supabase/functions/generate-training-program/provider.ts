/** One provider contract for Coach plans. Chat Completions supports strict
 * GPT-OSS JSON schemas without depending on the Responses compatibility layer. */
export function coachProgramRequest(model: string, instructions: string, constraints: unknown, schema: unknown) {
  return {
    model,
    reasoning_effort: "medium",
    messages: [
      { role: "system", content: instructions },
      { role: "user", content: JSON.stringify(constraints) },
    ],
    response_format: {
      type: "json_schema",
      json_schema: { name: "athlth_training_program", strict: true, schema },
    },
  };
}

export function coachProgramOutput(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const choices = (payload as { choices?: { message?: { content?: unknown; refusal?: unknown } }[] }).choices;
  const message = Array.isArray(choices) ? choices[0]?.message : undefined;
  if (message?.refusal) return null;
  return typeof message?.content === "string" && message.content.trim() ? message.content : null;
}

/** Never persist provider prose or generated content: either may echo user notes. */
export function coachProviderErrorCode(payload: unknown): string {
  const code = (payload as { error?: { code?: unknown } } | null)?.error?.code;
  const allowed = ["invalid_request_error", "model_not_found", "model_decommissioned", "json_validate_failed", "rate_limit_exceeded", "context_length_exceeded"];
  return typeof code === "string" && allowed.includes(code) ? code : "provider_rejected_request";
}

/** Groq can reject an oversized structured-output completion even with a
 * supported strict schema (json_validate_failed). Retry this *specific*
 * failure only once in JSON object mode; the server still validates every
 * returned week and every safety constraint before sending any draft. */
export function coachShouldRetryInvalidSchema(status: number, payload: unknown): boolean {
  return status === 400 && coachProviderErrorCode(payload) === "json_validate_failed";
}

export function coachProgramFallbackRequest(model: string, instructions: string, constraints: unknown) {
  return {
    model,
    reasoning_effort: "medium",
    messages: [
      {
        role: "system",
        content: instructions +
          "\nReturn ONLY one valid JSON object with title, summary and weeks. " +
          "Each week must have weekNumber, title and days. Each day must have " +
          "dayIndex, title and sessions. Each session must have title, kind, " +
          "durationMinutes, targetDistanceKilometers, " +
          "targetPaceSecondsPerKilometer, notes, exercises and blocks. " +
          "Use null when a numerical/string target is unknown and [] when " +
          "blocks or exercises are not justified. Include every requested " +
          "week and only the athlete's preferred weekdays; days without " +
          "workouts may have sessions: []. No markdown or extra prose.",
      },
      { role: "user", content: JSON.stringify(constraints) },
    ],
    response_format: { type: "json_object" },
  };
}

/** A JSON-mode fallback must not be normalized into a plausible-looking,
 * mostly fabricated empty plan. This is a structural gate, not a replacement
 * for the existing per-session normalization and injury exclusion guard. */
export function coachProgramHasUsableWeeks(value: unknown, expectedWeeks: number): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const weeks = (value as { weeks?: unknown }).weeks;
  if (!Number.isInteger(expectedWeeks) || expectedWeeks < 1 ||
      !Array.isArray(weeks) || weeks.length !== expectedWeeks) return false;
  let scheduled = 0;
  const kinds = new Set(["running", "walking", "strength", "mobility", "recovery", "custom"]);
  for (let i = 0; i < weeks.length; i++) {
    const week = weeks[i];
    if (!week || typeof week !== "object" ||
        week.weekNumber !== i + 1 || !Array.isArray(week.days) ||
        week.days.length < 1 || week.days.length > 7) return false;
    const seen = new Set<number>();
    for (const day of week.days) {
      if (!day || typeof day !== "object" ||
          !Number.isInteger(day.dayIndex) || day.dayIndex < 1 ||
          day.dayIndex > 7 || seen.has(day.dayIndex) ||
          !Array.isArray(day.sessions) || day.sessions.length > 1) return false;
      seen.add(day.dayIndex);
      for (const session of day.sessions) {
        if (!session || typeof session !== "object" ||
            typeof session.title !== "string" || !session.title.trim() ||
            !kinds.has(session.kind) ||
            (session.exercises !== undefined && !Array.isArray(session.exercises)) ||
            (session.blocks !== undefined && !Array.isArray(session.blocks))) return false;
        scheduled++;
      }
    }
  }
  return scheduled > 0;
}

/** Small, bounded model outputs avoid Groq JSON schema validation failures
 * on multiweek plans. Keep the whole original safety prompt and constraints:
 * weekCount: 1 refers only to output size; totalWeekCount and weekNumber
 * preserve the actual program phase and do not change athlete preferences. */
export function coachProgramSingleWeekRequest(
  model: string,
  instructions: string,
  constraints: Record<string, unknown>,
  weekNumber: number,
  totalWeekCount: number,
) {
  const scoped = {
    ...constraints,
    weekCount: 1,
    totalWeekCount,
    requestedWeekNumber: weekNumber,
  };
  return {
    model,
    reasoning_effort: "medium",
    messages: [
      {
        role: "system",
        content: instructions + "\nIMPORTANT WEEK-SCOPED OVERRIDE: " +
          "Generate exactly ONE training week numbered " + weekNumber +
          " in a total program of " + totalWeekCount + " weeks. " +
          "This overrides only the global week count; every safety, " +
          "training and equipment restriction remains unchanged. " +
          "Use the original program's phase and realistic progression. " +
          "Return a JSON object with title, summary, and weeks (exactly " +
          "one item with weekNumber=" + weekNumber + "). " +
          "That week has a days array, with entries only for chosen " +
          "preferredDays. Each day has dayIndex, title and sessions " +
          "(empty array for rest, otherwise at most one). " +
          "Each session needs title, kind, durationMinutes, " +
          "targetDistanceKilometers, targetPaceSecondsPerKilometer, " +
          "notes, exercises and blocks. Use null for unknown scalar " +
          "targets and [] when no blocks/exercises are justified. " +
          "Provide a sensible mix of actual workouts and rest days " +
          "when safe, matching the user's goals and limitations. " +
          "Return ONLY JSON, no markdown.",
      },
      { role: "user", content: JSON.stringify(scoped) },
    ],
    response_format: { type: "json_object" },
  };
}

/** Validate EACH AI week before stitching together a program. No invented
 * workouts, missing weeks, invalid day indexes or duplicates are accepted.
 * Selection of weekdays and maximum weekly frequency are checked here,
 * while the existing injury guard still validates the final draft. */
export function coachProgramValidWeek(
  payload: unknown,
  requestedWeek: number,
  preferredDays: number[],
  weeklyLimit: number,
): Record<string, unknown> | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
  const weeks = (payload as { weeks?: unknown }).weeks;
  if (!Array.isArray(weeks) || weeks.length !== 1) return null;
  const week = weeks[0];
  if (!week || typeof week !== "object" || Array.isArray(week) ||
      week.weekNumber !== requestedWeek || !Array.isArray(week.days) ||
      week.days.length < 1 || week.days.length > 7) return null;
  const chosen = new Set(preferredDays);
  const usedDays = new Set<number>();
  const kinds = new Set(["running", "walking", "strength", "mobility", "recovery", "custom"]);
  let sessions = 0;
  for (const day of week.days) {
    if (!day || typeof day !== "object" || Array.isArray(day) ||
        !Number.isInteger(day.dayIndex) ||
        !chosen.has(day.dayIndex) || usedDays.has(day.dayIndex) ||
        !Array.isArray(day.sessions) || day.sessions.length > 1) return null;
    usedDays.add(day.dayIndex);
    for (const session of day.sessions) {
      if (!session || typeof session !== "object" || Array.isArray(session) ||
          typeof session.title !== "string" || !session.title.trim() ||
          !kinds.has(session.kind) ||
          (session.blocks !== undefined && !Array.isArray(session.blocks)) ||
          (session.exercises !== undefined && !Array.isArray(session.exercises))) return null;
      sessions += 1;
    }
  }
  if (sessions > weeklyLimit) return null;
  return week as Record<string, unknown>;
}

/** Compose only verified AI-generated weeks in chronological order.
 * Never expand or silently invent missing plan weeks. */
export function coachProgramMergeWeeks(
  chunks: unknown[],
  expectedWeeks: number,
  preferredDays: number[],
  weeklyLimit: number,
): Record<string, unknown> | null {
  if (chunks.length !== expectedWeeks || expectedWeeks < 1) return null;
  const weeks: Record<string, unknown>[] = [];
  const summaries: string[] = [];
  let title = "";
  for (let index = 0; index < chunks.length; index++) {
    const chunk = chunks[index];
    const week = coachProgramValidWeek(chunk, index + 1, preferredDays, weeklyLimit);
    if (!week) return null;
    weeks.push(week);
    const obj = chunk as { title?: unknown; summary?: unknown };
    if (!title && typeof obj.title === "string") title = obj.title.trim().slice(0, 160);
    if (typeof obj.summary === "string" && obj.summary.trim()) {
      summaries.push("Week " + (index + 1) + ": " + obj.summary.trim().slice(0, 350));
    }
  }
  const result = {
    title: title || "ATHLTH training plan",
    summary: summaries.join("\n").slice(0, 1500),
    weeks,
  };
  return coachProgramHasUsableWeeks(result, expectedWeeks) ? result : null;
}

/** Compact strict schema: only fields required to reconstruct safe, structured
 * workouts. normalizeProgram fills omitted optional fields with null or []. */
export const coachCompactProgramSchema = {
  type: "object", additionalProperties: false,
  required: ["title", "summary", "weeks"],
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
    weeks: {
      type: "array", items: {
        type: "object", additionalProperties: false,
        required: ["weekNumber", "days"],
        properties: {
          weekNumber: { type: "integer" },
          days: { type: "array", items: {
            type: "object", additionalProperties: false,
            required: ["dayIndex", "sessions"],
            properties: {
              dayIndex: { type: "integer" },
              sessions: { type: "array", items: {
                type: "object", additionalProperties: false,
                required: ["title", "kind", "durationMinutes", "exercises", "blocks"],
                properties: {
                  title: { type: "string" },
                  kind: { type: "string", enum: ["running", "walking", "strength", "mobility", "recovery", "custom"] },
                  durationMinutes: { type: ["integer", "null"] },
                  exercises: { type: "array", items: {
                    type: "object", additionalProperties: false,
                    required: ["name", "sets", "reps", "targetRPE", "restSeconds"],
                    properties: {
                      name: { type: "string" }, sets: { type: "integer" },
                      reps: { type: ["integer", "null"] },
                      targetRPE: { type: ["number", "null"] },
                      restSeconds: { type: ["integer", "null"] },
                    },
                  }},
                  blocks: { type: "array", items: {
                    type: "object", additionalProperties: false,
                    required: [
                      "title", "kind", "phase", "durationSeconds", "distanceMeters",
                      "repetitions", "targetPaceSecondsPerKilometer",
                      "treadmillInclinePercent", "targetHeartRateZone", "targetEffortRPE",
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
                    },
                  }},
                },
              }},
            },
          }},
        },
      },
    },
  },
};

export function coachCompactProgramRequest(
  model: string, instructions: string, constraints: Record<string, unknown>,
  jsonFallback = false,
) {
  const compactInstructions = instructions +
    "\nCOMPACT OUTPUT CONTRACT: Produce exactly " + constraints.weekCount +
    " consecutive weeks numbered from 1. Each week needs weekNumber and days. " +
    "Include only preferredDays; each day needs dayIndex and sessions ([] for rest). " +
    "Each session contains only title, kind, durationMinutes, exercises and blocks. " +
    "Use null for unknown numeric fields and [] for unavailable exercise or block " +
    "details. Keep justified workout durations, distances, pace and zones in blocks. " +
    "No unnecessary blocks, note fields, or unrequested training. The athlete's " +
    "injury and equipment restrictions remain mandatory. Return JSON only.";
  return {
    model, reasoning_effort: "low", max_completion_tokens: 3500,
    messages: [
      { role: "system", content: compactInstructions },
      { role: "user", content: JSON.stringify(constraints) },
    ],
    response_format: jsonFallback
      ? { type: "json_object" }
      : { type: "json_schema", json_schema: {
          name: "athlth_compact_program", strict: true,
          schema: coachCompactProgramSchema,
        } },
  };
}

/** Reject incomplete weeks, duplicate weekdays, excess sessions, and any
 * workout on unavailable days. Ignore only empty extra rest-day entries. */
export function coachCompactValidatedProgram(
  value: unknown, weekCount: number, preferredDays: number[], weeklyLimit: number,
): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  if (typeof raw.title !== "string" || !raw.title.trim() ||
      !Array.isArray(raw.weeks) || raw.weeks.length !== weekCount) return null;
  const allowed = new Set(preferredDays);
  const weeks: Record<string, unknown>[] = [];
  let totalSessions = 0;
  for (let i = 0; i < weekCount; i++) {
    const week = raw.weeks[i];
    if (!week || typeof week !== "object" || Array.isArray(week) ||
        week.weekNumber !== i + 1 || !Array.isArray(week.days) ||
        week.days.length < 1 || week.days.length > 7) return null;
    const seen = new Set<number>();
    const selected: unknown[] = [];
    for (const day of week.days) {
      if (!day || typeof day !== "object" || Array.isArray(day) ||
          !Number.isInteger(day.dayIndex) || day.dayIndex < 1 ||
          day.dayIndex > 7 || seen.has(day.dayIndex) ||
          !Array.isArray(day.sessions) || day.sessions.length > 1) return null;
      seen.add(day.dayIndex);
      if (!allowed.has(day.dayIndex)) {
        if (day.sessions.length !== 0) return null;
      } else {
        selected.push(day);
        totalSessions += day.sessions.length;
      }
    }
    const canonical = { ...(week as Record<string, unknown>), days: selected };
    if (!coachProgramValidWeek({ weeks: [canonical] }, i + 1, preferredDays, weeklyLimit)) {
      return null;
    }
    weeks.push(canonical);
  }
  if (totalSessions < 1) return null;
  return {
    title: raw.title.slice(0, 160),
    summary: typeof raw.summary === "string" ? raw.summary.slice(0, 1500) : "",
    weeks,
  };
}

/** Groq 429 responses include a Retry-After delay in seconds. */
export function coachProviderRetryAfter(response: Response): number {
  const seconds = Number(response.headers.get("retry-after"));
  return Number.isFinite(seconds) && seconds > 0
    ? Math.min(86400, Math.max(1, Math.ceil(seconds)))
    : 60;
}
