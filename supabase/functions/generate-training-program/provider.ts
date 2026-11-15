/** One provider contract for Coach plans. Chat Completions supports strict
 * GPT-OSS JSON schemas without depending on the Responses compatibility layer. */
export function coachProgramRequest(model: string, instructions: string, constraints: unknown, schema: unknown) {
  return {
    model,
    reasoning_effort: "medium",
    // Separate GPT-OSS reasoning from its JSON-only content channel.
    reasoning_format: "parsed",
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

/** Parse a single complete AI JSON object. Raw Groq content can contain
 * an optional code fence or a short introduction. Do not log or repair raw
 * plan text, which could echo private goals or health restrictions. */
export function coachParseProgramText(text: string | null): unknown | null {
  if (!text || text.length > 300_000) return null;
  const source = text.trim();
  const fence = new RegExp("^\\x60{3}(?:json)?\\s*([\\s\\S]*?)\\s*\\x60{3}$", "i");
  const match = fence.exec(source);
  const candidate = match ? match[1].trim() : source;
  try {
    return JSON.parse(candidate);
  } catch {
    const start = candidate.indexOf("{");
    const end = candidate.lastIndexOf("}");
    if (start < 0 || end <= start) return null;
    try {
      return JSON.parse(candidate.slice(start, end + 1));
    } catch {
      return null;
    }
  }
}

/** Never persist provider prose or generated content: either may echo user notes. */
export function coachProviderErrorCode(payload: unknown): string {
  const code = (payload as { error?: { code?: unknown } } | null)?.error?.code;
  const allowed = ["invalid_request_error", "model_not_found", "model_decommissioned", "json_validate_failed", "rate_limit_exceeded", "context_length_exceeded"];
  return typeof code === "string" && allowed.includes(code) ? code : "provider_rejected_request";
}

/** Groq can reject JSON schema and JSON object modes with
 * json_validate_failed. Only this error permits one plain-output fallback;
 * recovered JSON must pass the same completeness and injury safety gates. */
export function coachShouldRetryInvalidSchema(status: number, payload: unknown): boolean {
  return status === 400 && coachProviderErrorCode(payload) === "json_validate_failed";
}

export function coachProgramFallbackRequest(model: string, instructions: string, constraints: unknown) {
  return {
    model,
    reasoning_effort: "medium",
    reasoning_format: "parsed",
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
    // No response_format: Groq rejected both json_schema and json_object.
    // The plain completion is still parsed and validated before use.
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
    model,
    reasoning_effort: "low",
    reasoning_format: "parsed",
    max_completion_tokens: 5000,
    messages: [
      { role: "system", content: compactInstructions },
      { role: "user", content: JSON.stringify(constraints) },
    ],
    // undefined is intentionally omitted by JSON.stringify for the raw
    // fallback; it must not use the provider's failing JSON validation.
    response_format: jsonFallback
      ? undefined
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
  if (!Array.isArray(raw.weeks) || raw.weeks.length !== weekCount ||
      !Number.isInteger(weekCount) || weekCount < 1 ||
      weeklyLimit < 1 || preferredDays.length < 1) return null;

  const validKinds = new Set([
    "running", "walking", "strength", "mobility", "recovery", "custom",
  ]);
  const allowedDays = [...new Set(preferredDays)].sort((a, b) => a - b);
  const allowed = new Set(allowedDays);
  const weeks: Record<string, unknown>[] = [];
  let totalSessions = 0;

  for (let index = 0; index < weekCount; index++) {
    const week = raw.weeks[index];
    if (!week || typeof week !== "object" || Array.isArray(week) ||
        week.weekNumber !== index + 1 || !Array.isArray(week.days) ||
        week.days.length > 7) return null;

    const seen = new Set<number>();
    const existing = new Map<number, Record<string, unknown>>();
    const misplaced: Record<string, unknown>[] = [];

    for (const day of week.days) {
      if (!day || typeof day !== "object" || Array.isArray(day) ||
          !Number.isInteger(day.dayIndex) || day.dayIndex < 1 ||
          day.dayIndex > 7 || seen.has(day.dayIndex) ||
          !Array.isArray(day.sessions) || day.sessions.length > 1) return null;
      seen.add(day.dayIndex);
      const workout: Record<string, unknown>[] = [];
      for (const item of day.sessions) {
        if (!item || typeof item !== "object" || Array.isArray(item) ||
            typeof item.title !== "string" || !item.title.trim() ||
            !validKinds.has(item.kind) ||
            (item.blocks != null && !Array.isArray(item.blocks)) ||
            (item.exercises != null && !Array.isArray(item.exercises))) return null;
        // Optional arrays may be omitted by a compact provider response.
        workout.push({
          ...item,
          blocks: Array.isArray(item.blocks) ? item.blocks : [],
          exercises: Array.isArray(item.exercises) ? item.exercises : [],
        });
      }
      if (allowed.has(day.dayIndex)) {
        existing.set(day.dayIndex, { ...day, sessions: workout });
      } else if (workout.length > 0) {
        // Relocate rather than sending a workout on an athlete-unavailable
        // weekday. Never add a workout or cross an explicitly selected week.
        misplaced.push(workout[0]);
      }
    }

    // Keep the user's selected weekdays authoritative. Fill only empty
    // REST-day slots here; no exercise or training is invented.
    const days = allowedDays.map((dayIndex) =>
      existing.get(dayIndex) ?? { dayIndex, sessions: [] }
    );
    let weekSessions = days.reduce(
      (sum, day) => sum + (day.sessions as unknown[]).length, 0,
    );
    for (const session of misplaced) {
      if (weekSessions >= weeklyLimit) break;
      const free = days.find((day) => (day.sessions as unknown[]).length === 0);
      if (!free) break;
      free.sessions = [session];
      weekSessions++;
    }
    // Cap overly eager model output to the selected frequency. The athlete
    // always reviews the resulting unsaved draft before accepting it.
    let used = 0;
    for (const day of days) {
      const sessions = day.sessions as unknown[];
      if (sessions.length && used >= weeklyLimit) day.sessions = [];
      else if (sessions.length) used++;
    }
    totalSessions += used;
    weeks.push({
      ...week, days,
    });
  }
  // Never return a fabricated all-rest plan after a provider failure.
  if (totalSessions < 1) return null;
  return {
    title: typeof raw.title === "string" && raw.title.trim()
      ? raw.title.slice(0, 160) : "ATHLTH training plan",
    summary: typeof raw.summary === "string" ? raw.summary.slice(0, 1500) : "",
    weeks,
  };
}


/**
 * A compact AI reply can contain all requested weeks but spend nearly all
 * its output on the early weeks. E.g. 5/5/5/1 sessions in four weeks.
 *
 * We re-use ONLY actual sessions already generated for this same athlete
 * and program. Never synthesize exercises, invent future training history,
 * exceed available days or the weekly ceiling. Do not automatically
 * backfill when health restrictions were supplied: a rest-heavy week may
 * be intentional and must not be overridden without the athlete's input.
 *
 * A deload week still has training: reduce volume and effort on copied
 * workouts. The existing injury-exclusion guard is re-run on the full
 * normalized draft before it can be shown or saved.
 */
export function coachBackfillSparseFinalWeek(
  program: Record<string, unknown>,
  preferredDays: number[],
  weeklyLimit: number,
  allowReuse: boolean,
  varyWeeks: boolean,
): { program: Record<string, unknown>; added: number } {
  const raw = program.weeks;
  if (!allowReuse || !Array.isArray(raw) || raw.length < 3 ||
      weeklyLimit < 2 || preferredDays.length < 2) {
    return { program, added: 0 };
  }
  type Session = Record<string, unknown>;
  type Day = { dayIndex: number; sessions: Session[] };
  type Week = Record<string, unknown> & { days: Day[] };
  const weeks = raw as Week[];
  const previous = weeks.slice(0, -1);
  const latest = weeks[weeks.length - 1];
  if (!latest || !Array.isArray(latest.days)) return { program, added: 0 };

  const count = (week: Week) => week.days.reduce(
    (sum, day) => sum + (Array.isArray(day.sessions) ? day.sessions.length : 0), 0,
  );
  const previousCounts = previous.map(count);
  const typical = Math.max(0, ...previousCounts);
  // 1-2 prior workouts are too few to infer a meaningful "missing" week.
  if (typical < 3) return { program, added: 0 };
  const minimum = Math.min(weeklyLimit, Math.ceil(typical * 0.75));
  const existingCount = count(latest);
  if (existingCount >= minimum) return { program, added: 0 };

  const workdays = [...new Set(preferredDays)].sort((a, b) => a - b);
  const cloned = structuredClone(latest) as Week;
  const daysByIndex = new Map(cloned.days.map(day => [day.dayIndex, day]));
  const remaining = workdays.filter(day => {
    const existing = daysByIndex.get(day);
    return !existing || !Array.isArray(existing.sessions) ||
      existing.sessions.length === 0;
  });
  const lastWeekNames = cloned.days.flatMap(day =>
    (day.sessions ?? []).map(session => String(session.title ?? "")));
  const isDeload = /deload|recovery week|restitusjonsuke|avlastning/i.test(
    [String(cloned.title ?? ""), ...lastWeekNames].join(" "),
  );

  const reused = new Set<string>();
  let added = 0;
  for (const dayIndex of remaining) {
    if (existingCount + added >= minimum) break;
    // Prefer the same weekday across earlier weeks to retain the athlete's
    // chosen training pattern, but rotate source weeks if variety was chosen.
    const order = varyWeeks
      ? [...previous.slice(0, -1)].reverse().concat(previous[previous.length - 1])
      : [...previous].reverse();
    const candidates: { session: Session; key: string; sameDay: boolean }[] = [];
    for (const [sourceWeekIndex, week] of order.entries()) {
      for (const day of week.days) {
        const session = day.sessions?.[0];
        if (!session || typeof session.title !== "string") continue;
        candidates.push({
          session,
          key: [sourceWeekIndex, day.dayIndex, session.title].join(":"),
          sameDay: day.dayIndex === dayIndex,
        });
      }
    }
    candidates.sort((a, b) =>
      Number(b.sameDay) - Number(a.sameDay) ||
      (isDeload
        ? Number(/easy|rolig|aerobic/i.test(String(b.session.title ?? ""))) -
          Number(/easy|rolig|aerobic/i.test(String(a.session.title ?? "")))
        : 0),
    );
    const choice = candidates.find(c => !reused.has(c.key));
    if (!choice) break;
    reused.add(choice.key);
    const session = structuredClone(choice.session) as Session;
    if (isDeload) {
      if (typeof session.durationMinutes === "number") {
        session.durationMinutes = Math.max(15,
          Math.round(session.durationMinutes * 0.75 / 5) * 5);
      }
      if (typeof session.targetDistanceKilometers === "number") {
        session.targetDistanceKilometers =
          Math.round(session.targetDistanceKilometers * 0.75 * 10) / 10;
      }
      session.targetPaceSecondsPerKilometer = null;
      if (Array.isArray(session.exercises)) {
        session.exercises = session.exercises.map((exercise: Record<string, unknown>) => ({
          ...exercise,
          sets: typeof exercise.sets === "number"
            ? Math.max(1, Math.ceil(exercise.sets * 0.75))
            : exercise.sets,
          targetRPE: typeof exercise.targetRPE === "number"
            ? Math.min(exercise.targetRPE, 6) : exercise.targetRPE,
        }));
      }
      if (Array.isArray(session.blocks)) {
        session.blocks = session.blocks.map((block: Record<string, unknown>) => ({
          ...block,
          durationSeconds: typeof block.durationSeconds === "number"
            ? Math.max(10, Math.round(block.durationSeconds * 0.75))
            : block.durationSeconds,
          targetHeartRateZone: typeof block.targetHeartRateZone === "number"
            ? Math.min(3, block.targetHeartRateZone) : block.targetHeartRateZone,
          targetEffortRPE: typeof block.targetEffortRPE === "number"
            ? Math.min(6, block.targetEffortRPE) : block.targetEffortRPE,
          targetPaceSecondsPerKilometer: null,
        }));
      }
    }
    const target = daysByIndex.get(dayIndex);
    if (target) target.sessions = [session];
    else {
      const day = { dayIndex, sessions: [session] };
      cloned.days.push(day);
      daysByIndex.set(dayIndex, day);
    }
    added++;
  }
  if (added === 0) return { program, added: 0 };
  cloned.days.sort((a, b) => a.dayIndex - b.dayIndex);
  const amended = [...previous, cloned];
  return {
    program: { ...program, weeks: amended },
    added,
  };
}

/** Groq 429 responses include a Retry-After delay in seconds. */
export function coachProviderRetryAfter(response: Response): number {
  const seconds = Number(response.headers.get("retry-after"));
  return Number.isFinite(seconds) && seconds > 0
    ? Math.min(86400, Math.max(1, Math.ceil(seconds)))
    : 60;
}

/** The plan summary must be derived from the actual ATHLTH sessions, not
 * AI prose claiming a fixed weekly frequency that the schedule contradicts. */
export function coachGroundedProgramSummary(
  value: { weeks?: unknown }, language: "no" | "en" = "no",
): string {
  const weeks = Array.isArray(value.weeks) ? value.weeks : [];
  const counts = new Map<string, number>();
  const weeklyCounts: number[] = [];
  let minutes = 0;
  for (const week of weeks) {
    const days = week && typeof week === "object" && Array.isArray(week.days)
      ? week.days : [];
    let count = 0;
    for (const day of days) {
      const sessions = day && typeof day === "object" &&
        Array.isArray(day.sessions) ? day.sessions : [];
      for (const workout of sessions) {
        if (!workout || typeof workout !== "object") continue;
        const kind = typeof workout.kind === "string" ? workout.kind : "custom";
        counts.set(kind, (counts.get(kind) ?? 0) + 1);
        if (Number.isFinite(workout.durationMinutes)) {
          minutes += Math.max(0, Number(workout.durationMinutes));
        }
        count++;
      }
    }
    weeklyCounts.push(count);
  }
  const total = weeklyCounts.reduce((sum, n) => sum + n, 0);
  const names: [string, string, string][] = [
    ["strength", "styrke", "strength"], ["running", "løping", "running"],
    ["walking", "gåing", "walking"], ["mobility", "bevegelighet", "mobility"],
    ["recovery", "restitusjon", "recovery"], ["custom", "andre", "other"],
  ];
  const distribution = names.filter(([key]) => counts.has(key))
    .map(([key, no, en]) =>
      String(counts.get(key)) + " " + (language === "no" ? no : en)
    ).join(", ");
  return language === "no"
    ? String(weeks.length) + " uker med " + total + " økter. " +
      "Økter per uke: " + weeklyCounts.join(" / ") + ". " +
      (distribution ? "Fordeling: " + distribution + ". " : "") +
      (minutes > 0 ? "Totalt " + minutes + " planlagte minutter. " : "") +
      "Kontroller øktdetaljene før du lagrer planen."
    : String(weeks.length) + " weeks with " + total + " sessions. " +
      "Sessions per week: " + weeklyCounts.join(" / ") + ". " +
      (distribution ? "Breakdown: " + distribution + ". " : "") +
      (minutes > 0 ? minutes + " scheduled minutes in total. " : "") +
      "Review the workout details before saving.";
}

/** Protect the unified motor against text-only strength and malformed
 * intervals. A steady run with duration/distance is a valid basic recipe;
 * a named interval must contain real repetitions and recovery blocks. */
export function coachExecutableProgramIssues(
  value: { weeks?: unknown },
): string[] {
  const errors: string[] = [];
  const weeks = Array.isArray(value.weeks) ? value.weeks : [];
  for (let index = 0; index < weeks.length; index++) {
    const days = Array.isArray(weeks[index]?.days) ? weeks[index].days : [];
    for (const day of days) {
      const sessions = Array.isArray(day?.sessions) ? day.sessions : [];
      for (const workout of sessions) {
        const kind = workout?.kind;
        const blocks = Array.isArray(workout?.blocks) ? workout.blocks : [];
        const exercises = Array.isArray(workout?.exercises) ? workout.exercises : [];
        if (kind === "strength") {
          const validExercises = exercises.filter((e: any) =>
            typeof e?.name === "string" && Boolean(e.name.trim()) &&
            Number.isInteger(e.sets) && e.sets > 0 &&
            Number.isInteger(e.reps) && e.reps > 0
          );
          const validTimeline = blocks.some((b: any) =>
            b.kind === "exercise" && typeof b.title === "string" &&
            Boolean(b.title.trim()) && (
              Number.isFinite(b.repetitions) && b.repetitions > 0 ||
              Number.isFinite(b.durationSeconds) && b.durationSeconds > 0
            )
          );
          if (validExercises.length === 0 && !validTimeline) {
            errors.push("week_" + (index + 1) + ":strength_missing_sets");
          }
        }
        if (kind === "running" || kind === "walking") {
          const playable = blocks.some((b: any) => b.kind === "run" &&
            (Number.isFinite(b.durationSeconds) && b.durationSeconds > 0 ||
             Number.isFinite(b.distanceMeters) && b.distanceMeters > 0));
          const basic = (Number.isFinite(workout?.durationMinutes) &&
              workout.durationMinutes > 0) ||
            (Number.isFinite(workout?.targetDistanceKilometers) &&
              workout.targetDistanceKilometers > 0);
          if (!playable && !basic) {
            errors.push("week_" + (index + 1) + ":cardio_without_target");
          }
          if (/interval|intervall|4\s*[x×]\s*4/i.test(String(workout?.title ?? ""))) {
            const efforts = blocks.filter((b: any) =>
              b.kind === "run" && b.phase === "main").length;
            const rests = blocks.filter((b: any) =>
              b.kind === "rest" || b.phase === "recovery").length;
            if (efforts < 2 || rests < 1) {
              errors.push("week_" + (index + 1) + ":interval_without_drags");
            }
          }
        }
      }
    }
  }
  return errors;
}
