import { coachProgramRequest, coachProgramOutput, coachProviderErrorCode, coachShouldRetryInvalidSchema, coachProgramFallbackRequest, coachProgramHasUsableWeeks, coachProgramSingleWeekRequest, coachProgramValidWeek, coachProgramMergeWeeks, coachCompactProgramSchema, coachCompactProgramRequest, coachCompactValidatedProgram, coachProviderRetryAfter } from "./provider.ts";
const check = (condition: boolean) => { if (!condition) throw new Error("Assertion failed"); };
Deno.test("Coach sends structured goals and selected scope using the chat contract", () => {
  const constraints = { weekCount: 4, userNotes: "Adjust Tuesday only", goals: [{ title: "5K" }] };
  const schema = { type: "object" };
  const request = coachProgramRequest("openai/gpt-oss-120b", "Prepare a plan", constraints, schema);
  check(request.messages[0].role === "system");
  check(JSON.parse(request.messages[1].content).userNotes === constraints.userNotes);
  check(request.response_format.json_schema.strict === true);
  check(request.response_format.json_schema.schema === schema);
  check(!("text" in request) && !("input" in request));
});
Deno.test("Coach output rejects empty responses and refusals", () => {
  check(coachProgramOutput({ choices: [{ message: { content: "{}" } }] }) === "{}");
  check(coachProgramOutput({ choices: [{ message: { content: "", refusal: "No" } }] }) === null);
  check(coachProgramOutput({}) === null);
});
Deno.test("Provider errors cannot log athlete notes or untrusted error prose", () => {
  check(coachProviderErrorCode({ error: { code: "private health information" } }) === "provider_rejected_request");
  check(coachProviderErrorCode({ error: { code: "model_not_found" } }) === "model_not_found");
});


Deno.test("Groq schema mismatch retries once using JSON object mode, not other 400s", () => {
  const rejected = { error: { code: "json_validate_failed", message: "may contain private user content" } };
  check(coachShouldRetryInvalidSchema(400, rejected));
  check(!coachShouldRetryInvalidSchema(400, { error: { code: "rate_limit_exceeded" } }));
  check(!coachShouldRetryInvalidSchema(429, rejected));
  check(!coachShouldRetryInvalidSchema(502, rejected));

  const input = { weekCount: 2, preferredDays: [1, 3], userNotes: "private" };
  const req = coachProgramFallbackRequest("openai/gpt-oss-120b", "Create safe plan", input);
  check(req.response_format.type === "json_object");
  check(req.messages[0].content.includes("JSON object"));
  check(JSON.parse(req.messages[1].content).weekCount === 2);
});

Deno.test("Coach rejects incomplete or forged fallback output before normalization", () => {
  const makeWeek = (n: number) => ({
    weekNumber: n,
    days: [{
      dayIndex: 1,
      sessions: [{
        title: "Easy run", kind: "running",
        exercises: [], blocks: [],
      }],
    }],
  });
  check(coachProgramHasUsableWeeks({ weeks: [makeWeek(1), makeWeek(2)] }, 2));
  check(!coachProgramHasUsableWeeks({ weeks: [makeWeek(1)] }, 2));
  check(!coachProgramHasUsableWeeks({ weeks: [{ ...makeWeek(1), days: [] }, makeWeek(2)] }, 2));
  check(!coachProgramHasUsableWeeks({ weeks: [makeWeek(2), makeWeek(1)] }, 2));
  check(!coachProgramHasUsableWeeks({ weeks: [
    { weekNumber: 1, days: [
      { dayIndex: 1, sessions: [] },
      { dayIndex: 1, sessions: [] },
    ] },
    makeWeek(2),
  ] }, 2));
  check(!coachProgramHasUsableWeeks({ weeks: [
    { weekNumber: 1, days: [{ dayIndex: 1, sessions: [] }] },
    { weekNumber: 2, days: [{ dayIndex: 1, sessions: [] }] },
  ] }, 2));
  check(!coachProgramHasUsableWeeks({
    weeks: [
      { weekNumber: 1, days: [{ dayIndex: 1, sessions: [{ title: "X", kind: "unknown" }] }] },
      makeWeek(2),
    ],
  }, 2));
});


Deno.test("Coach shards four-week programs without dropping safety constraints", () => {
  const safety = {
    weekCount: 4, preferredDays: [1, 3, 5], sessionsPerWeek: 2,
    aiChoosesFrequency: true, aiChoosesDuration: true,
    excludedMovements: ["Squats"], unavailableEquipment: ["Barbell"],
    injurySafetyNotes: "private training limitation",
  };
  const shard = coachProgramSingleWeekRequest(
    "openai/gpt-oss-120b", "Athlete safety is mandatory", safety, 3, 4,
  );
  check(shard.response_format.type === "json_object");
  check(shard.messages[0].content.includes("Athlete safety is mandatory"));
  const user = JSON.parse(shard.messages[1].content);
  check(user.weekCount === 1 && user.totalWeekCount === 4);
  check(user.requestedWeekNumber === 3);
  check(user.excludedMovements[0] === "Squats");
  check(user.unavailableEquipment[0] === "Barbell");
  check(user.injurySafetyNotes === safety.injurySafetyNotes);
});

Deno.test("Coach merges exactly four verified weeks without inventing workouts", () => {
  const makeChunk = (n: number) => ({
    title: "Strength program", summary: "Safe progression",
    weeks: [{
      weekNumber: n,
      days: [
        { dayIndex: 1, sessions: [{ title: "Easy strength", kind: "strength", exercises: [], blocks: [] }] },
        { dayIndex: 3, sessions: [] },
        { dayIndex: 5, sessions: [] },
      ],
    }],
  });
  const chunks = [1,2,3,4].map(makeChunk);
  const done = coachProgramMergeWeeks(chunks, 4, [1,3,5], 2);
  check(done !== null);
  check((done?.weeks as {weekNumber:number}[]).map(w=>w.weekNumber).join(",") === "1,2,3,4");
  check(!coachProgramMergeWeeks(chunks.slice(0,3), 4, [1,3,5], 2));
  check(!coachProgramMergeWeeks([makeChunk(1), makeChunk(2), makeChunk(2), makeChunk(4)], 4, [1,3,5], 2));
  check(!coachProgramValidWeek({
    weeks: [{ weekNumber: 1, days: [
      { dayIndex: 2, sessions: [{ title: "Unsafe day", kind: "running" }] },
    ] }],
  }, 1, [1,3,5], 2));
  check(!coachProgramValidWeek({
    weeks: [{ weekNumber: 1, days: [
      { dayIndex: 1, sessions: [
        { title: "A", kind: "running" }, { title: "B", kind: "running" },
      ] },
    ] }],
  }, 1, [1,3,5], 2));
  check(!coachProgramValidWeek({
    weeks: [{ weekNumber: 1, days: [
      { dayIndex: 1, sessions: [{ title: "A", kind: "running" }] },
      { dayIndex: 1, sessions: [] },
    ] }],
  }, 1, [1,3,5], 2));
  check(!coachProgramValidWeek({
    weeks: [{ weekNumber: 1, days: [
      { dayIndex: 1, sessions: [{ title: "A", kind: "running" }] },
      { dayIndex: 3, sessions: [{ title: "B", kind: "strength" }] },
    ] }],
  }, 1, [1,3,5], 1));
  check(!coachProgramMergeWeeks([makeChunk(1), makeChunk(2), makeChunk(3), {
    title: "T", summary: "S", weeks: [{weekNumber:4,days:[]}]
  }], 4, [1,3,5], 2));
});


Deno.test("Coach compact schema keeps strict JSON while reducing multiweek output", () => {
  const request = coachCompactProgramRequest("openai/gpt-oss-120b", "Use safe progression", {
    weekCount: 4, sessionsPerWeek: 3, preferredDays: [1,3,5],
    injurySafetyNotes: "Do not load knee", unavailableEquipment: ["Barbell"],
  });
  check(request.reasoning_effort === "low");
  check(request.response_format.type === "json_schema");
  check(request.response_format.json_schema?.strict === true);
  const constraints = JSON.parse(request.messages[1].content);
  check(constraints.weekCount === 4);
  check(constraints.injurySafetyNotes === "Do not load knee");
  check(constraints.unavailableEquipment[0] === "Barbell");
  const session = coachCompactProgramSchema.properties.weeks.items.properties.days.items
    .properties.sessions.items;
  check(session.required.includes("exercises") && session.required.includes("blocks"));
  check(!session.required.includes("notes"));
  const fallback = coachCompactProgramRequest("openai/gpt-oss-120b", "Safe plan", {
    weekCount: 4, preferredDays: [1],
  }, true);
  check(fallback.response_format.type === "json_object");
});

Deno.test("Coach compact plan accepts safe selected days and rejects off-day workouts", () => {
  const week = (n: number) => ({
    weekNumber: n,
    days: [
      { dayIndex: 1, sessions: [{
        title: "Easy run", kind: "running", durationMinutes: 30,
        exercises: [], blocks: [],
      }] },
      { dayIndex: 2, sessions: [] },
      { dayIndex: 3, sessions: [] },
    ],
  });
  const source = {title:"Plan",summary:"Safe progression",weeks:[1,2,3,4].map(week)};
  const normalized = coachCompactValidatedProgram(source, 4, [1,3], 2);
  check(normalized !== null);
  check((normalized?.weeks as {days:unknown[]}[]).every(w=>w.days.length === 2));
  check(coachCompactValidatedProgram({...source,weeks:source.weeks.slice(0,3)},4,[1,3],2) === null);
  const offDayWorkout = JSON.parse(JSON.stringify(source));
  offDayWorkout.weeks[0].days[1].sessions.push({
    title: "Off day run", kind: "running", exercises: [], blocks: [],
  });
  check(coachCompactValidatedProgram(offDayWorkout, 4, [1,3], 2) === null);
  const tooMany = JSON.parse(JSON.stringify(source));
  tooMany.weeks[0].days[2].sessions.push({
    title: "A", kind: "strength", exercises: [], blocks: [],
  });
  check(coachCompactValidatedProgram(tooMany, 4, [1,3], 1) === null);
  const empty = JSON.parse(JSON.stringify(source));
  for (const w of empty.weeks) for (const day of w.days) day.sessions = [];
  check(coachCompactValidatedProgram(empty, 4, [1,3], 2) === null);
});

Deno.test("Groq 429 retry header is bounded and never includes private output", () => {
  check(coachProviderRetryAfter(new Response("", {status:429,headers:{"retry-after":"2.3"}}))===3);
  check(coachProviderRetryAfter(new Response("", {status:429,headers:{"retry-after":"invalid"}}))===60);
  check(coachProviderRetryAfter(new Response("", {status:429,headers:{"retry-after":"999999"}}))===86400);
});
