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
