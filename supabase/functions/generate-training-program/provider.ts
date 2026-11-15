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
