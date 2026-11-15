import { coachProgramRequest, coachProgramOutput, coachProviderErrorCode, coachShouldRetryInvalidSchema, coachProgramFallbackRequest, coachProgramHasUsableWeeks, coachProgramSingleWeekRequest, coachProgramValidWeek, coachProgramMergeWeeks, coachCompactProgramSchema, coachCompactProgramRequest, coachCompactValidatedProgram, coachProviderRetryAfter, coachParseProgramText, coachBackfillSparseFinalWeek, coachGroundedProgramSummary, coachExecutableProgramIssues } from "./provider.ts";
const check = (condition: boolean) => { if (!condition) throw new Error("Assertion failed"); };
Deno.test("Coach sends structured goals and selected scope using the chat contract", () => {
  const constraints = { weekCount: 4, userNotes: "Adjust Tuesday only", goals: [{ title: "5K" }] };
  const schema = { type: "object" };
  const request = coachProgramRequest("openai/gpt-oss-120b", "Prepare a plan", constraints, schema);
  check(request.reasoning_format === "parsed");
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


Deno.test("Groq schema mismatch permits one plain-text fallback, not other 400s", () => {
  const rejected = { error: { code: "json_validate_failed", message: "may contain private user content" } };
  check(coachShouldRetryInvalidSchema(400, rejected));
  check(!coachShouldRetryInvalidSchema(400, { error: { code: "rate_limit_exceeded" } }));
  check(!coachShouldRetryInvalidSchema(429, rejected));
  check(!coachShouldRetryInvalidSchema(502, rejected));

  const input = { weekCount: 2, preferredDays: [1, 3], userNotes: "private" };
  const req = coachProgramFallbackRequest("openai/gpt-oss-120b", "Create safe plan", input);
  check(req.reasoning_format === "parsed");
  check(!("response_format" in req));
  check(!JSON.stringify(req).includes("response_format"));
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
  check(request.reasoning_format === "parsed");
  check(request.response_format?.type === "json_schema");
  check(request.response_format?.json_schema?.strict === true);
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
  check(fallback.reasoning_format === "parsed");
  check(fallback.response_format === undefined);
  check(!JSON.stringify(fallback).includes("response_format"));
});

Deno.test("Coach compact plan safely normalizes generated days to allowed weekdays", () => {
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
  const moved = coachCompactValidatedProgram(offDayWorkout, 4, [1,3], 2);
  check(moved !== null);
  const firstWeek = (moved?.weeks as {days: {dayIndex:number,sessions:{title:string}[]}[]}[])[0];
  check(firstWeek.days.length === 2);
  check(firstWeek.days[0].dayIndex === 1 && firstWeek.days[0].sessions.length === 1);
  check(firstWeek.days[1].dayIndex === 3 && firstWeek.days[1].sessions.length === 1);
  check(firstWeek.days[1].sessions[0].title === "Off day run");
  const tooMany = JSON.parse(JSON.stringify(source));
  tooMany.weeks[0].days[2].sessions.push({
    title: "A", kind: "strength", exercises: [], blocks: [],
  });
  const capped = coachCompactValidatedProgram(tooMany, 4, [1,3], 1);
  check(capped !== null);
  check((capped?.weeks as {days:{sessions:unknown[]}[]}[])[0].days
    .reduce((n,day)=>n+day.sessions.length,0) === 1);
  const empty = JSON.parse(JSON.stringify(source));
  for (const w of empty.weeks) for (const day of w.days) day.sessions = [];
  check(coachCompactValidatedProgram(empty, 4, [1,3], 2) === null);
});

Deno.test("Groq 429 retry header is bounded and never includes private output", () => {
  check(coachProviderRetryAfter(new Response("", {status:429,headers:{"retry-after":"2.3"}}))===3);
  check(coachProviderRetryAfter(new Response("", {status:429,headers:{"retry-after":"invalid"}}))===60);
  check(coachProviderRetryAfter(new Response("", {status:429,headers:{"retry-after":"999999"}}))===86400);
});


Deno.test("Coach fills omitted selected rest weekdays but never invents workouts", () => {
  const weeks = Array.from({length:4},(_,i)=>({
    weekNumber:i+1,
    days: i===2?[]:[{
      dayIndex: 3,
      sessions: [{title:"Walk",kind:"walking",durationMinutes:35}],
    }],
  }));
  const program = coachCompactValidatedProgram({title:"Plan",weeks},4,[1,3,5],2);
  check(program !== null);
  const normalized = program?.weeks as {days:{dayIndex:number,sessions:unknown[]}[]}[];
  check(normalized.length === 4);
  check(normalized.every(w=>w.days.map(d=>d.dayIndex).join(",")==="1,3,5"));
  check(normalized[2].days.every(d=>d.sessions.length===0));
  check(normalized[1].days[1].sessions.length===1);
  check(coachCompactValidatedProgram({title:"Plan",weeks:weeks.slice(0,3)},4,[1,3,5],2)===null);
  const invalid = structuredClone(weeks);
  invalid[0].days[0].dayIndex=8;
  check(coachCompactValidatedProgram({title:"Plan",weeks:invalid},4,[1,3,5],2)===null);
});

Deno.test("Coach parses a complete JSON plan from unconstrained Groq output", () => {
  const result = { title: "Running plan", weeks: [{ weekNumber: 1, days: [] }] };
  const raw = JSON.stringify(result);
  const fence = String.fromCharCode(96).repeat(3);
  const examples = [raw, fence + "json\n" + raw + "\n" + fence,
    "Generated plan:\n" + raw];
  for (const text of examples) {
    check(JSON.stringify(coachParseProgramText(text)) === raw);
  }
  check(coachParseProgramText(null) === null);
  check(coachParseProgramText("This is not a JSON plan") === null);
  check(coachParseProgramText(raw.slice(0, -2)) === null);
  check(coachParseProgramText("{" + "x".repeat(300_001) + "}") === null);
});

Deno.test("Coach repairs a nearly empty final deload week without fabricating exercises", () => {
  const makeWorkout = (kind: string, title: string) => ({
    title, kind, durationMinutes: 60,
    exercises: kind === "strength"
      ? [{ name: "Bench Press", sets: 4, reps: 8, targetRPE: 8 }] : [],
    blocks: kind === "running"
      ? [{ title: "Easy", kind: "run", phase: "main",
           durationSeconds: 1800, targetHeartRateZone: 2, targetEffortRPE: 5 }] : [],
  });
  const days = [1, 2, 3, 4, 5];
  const base = days.map(dayIndex => ({
    dayIndex,
    sessions: [makeWorkout(dayIndex % 2 ? "strength" : "running",
      dayIndex % 2 ? "Full Body" : "Easy Aerobic Run")],
  }));
  const weeks = [1, 2, 3].map(weekNumber => ({
    weekNumber, days: structuredClone(base),
  }));
  weeks.push({
    weekNumber: 4,
    days: [{ dayIndex: 1, sessions: [{
      ...makeWorkout("strength", "Strength (Deload)"),
    }] }, ...days.slice(1).map(dayIndex => ({ dayIndex, sessions: [] as
      ReturnType<typeof makeWorkout>[] }))],
  });
  const original = { title: "Mixed plan", summary: "Four weeks", weeks };
  const snapshot = JSON.stringify(original);
  const repaired = coachBackfillSparseFinalWeek(
    original, days, 5, true, true,
  );
  check(repaired.added === 3);
  const outputWeeks = repaired.program.weeks as typeof weeks;
  const last = outputWeeks[3].days;
  check(last.filter(day => day.sessions.length > 0).length === 4);
  check(last[0].sessions[0].title === "Strength (Deload)");
  check(last.slice(1).filter(day => day.sessions.length > 0)
    .every(day => day.sessions[0].durationMinutes === 45));
  check(last.slice(1).filter(day => day.sessions[0]?.kind === "strength")
    .every(day => day.sessions[0].exercises[0].sets === 3));
  check(outputWeeks[0].days.every(day => day.sessions.length === 1));
  check(JSON.stringify(original) === snapshot);
  check(repaired.program !== original);
});

Deno.test("Coach never fills recovery weeks from outside the user's allowed days or with health exclusions", () => {
  const sample = (kind: string) => ({
    kind, title: "Easy", durationMinutes: 30,
    exercises: [], blocks: [],
  });
  const weekdays = [1, 3, 5];
  const full = (n: number) => ({
    weekNumber: n,
    days: weekdays.map(dayIndex => ({
      dayIndex, sessions: [sample("walking")],
    })),
  });
  const last = { weekNumber: 4,
    days: weekdays.map(dayIndex => ({
      dayIndex, sessions: dayIndex === 1 ? [sample("walking")] : [] as ReturnType<typeof sample>[],
    })),
  };
  const program = { title: "Walking", weeks: [full(1), full(2), full(3), last] };
  const protectedProgram = coachBackfillSparseFinalWeek(
    program, weekdays, 3, false, true,
  );
  check(protectedProgram.added === 0 && protectedProgram.program === program);
  const repaired = coachBackfillSparseFinalWeek(program, weekdays, 3, true, false);
  check(repaired.added === 2);
  const out = repaired.program.weeks as typeof program.weeks;
  check(out[3].days.every(day => weekdays.includes(day.dayIndex)));
  check(out[3].days.every(day => day.sessions.length === 1));
  const normal = coachBackfillSparseFinalWeek({title:"Plan", weeks: [
    full(1), full(2), full(3), full(4),
  ]}, weekdays, 3, true, true);
  check(normal.added === 0);
  const lowFrequency = coachBackfillSparseFinalWeek(program, weekdays, 1, true, true);
  check(lowFrequency.added === 0);
});


Deno.test("Coach summaries only describe the actual ATHLTH week sessions", () => {
  const strength = { title:"Full Body",kind:"strength",durationMinutes:60,
    exercises:[{name:"Squat",sets:3,reps:8}],blocks:[] };
  const run = { title:"Easy Run",kind:"running",durationMinutes:40,
    exercises:[],blocks:[] };
  const week = (n:number, count:number) => ({
    weekNumber:n,days:[{
      dayIndex:1,sessions:Array.from({length:count},(_,i)=>i%2===0?strength:run),
    }],
  });
  const plan = { title:"Coach",summary:"Incorrect: five 60-minute sessions per week",
    weeks:[week(1,5),week(2,5),week(3,5),week(4,1)] };
  const no = coachGroundedProgramSummary(plan,"no");
  const en = coachGroundedProgramSummary(plan,"en");
  check(no.includes("4 uker med 16 økter"));
  check(no.includes("5 / 5 / 5 / 1"));
  check(!no.includes("five 60-minute"));
  check(en.includes("4 weeks with 16 sessions"));
  check(en.includes("5 / 5 / 5 / 1"));
  check(no.includes("planlagte minutter"));
});

Deno.test("Coach accepts real ATHLTH strength sets and steady runs", () => {
  const valid = { weeks:[{days:[{sessions:[
    { title:"Strength",kind:"strength",durationMinutes:60,
      exercises:[{name:"Squat",sets:3,reps:8}],blocks:[] },
    { title:"Easy Run",kind:"running",durationMinutes:40,blocks:[],exercises:[] },
  ]}]}]};
  check(coachExecutableProgramIssues(valid).length===0);
});

Deno.test("Coach rejects a text-only strength card or a fake interval", () => {
  const invalid = { weeks:[{days:[{sessions:[
    { title:"Full Body",kind:"strength",durationMinutes:60,
      exercises:[],blocks:[] },
    { title:"4x4 intervals",kind:"running",durationMinutes:45,blocks:[] },
  ]}]}]};
  const issues = coachExecutableProgramIssues(invalid);
  check(issues.includes("week_1:strength_missing_sets"));
  check(issues.includes("week_1:interval_without_drags"));
  const validInterval = { weeks:[{days:[{sessions:[{
    title:"4x4 interval",kind:"running",durationMinutes:30,blocks:[
      {title:"Work 1",kind:"run",phase:"main",durationSeconds:240},
      {title:"Recover",kind:"rest",phase:"recovery",durationSeconds:120},
      {title:"Work 2",kind:"run",phase:"main",durationSeconds:240},
    ],
  }]}]}]};
  check(coachExecutableProgramIssues(validInterval).length===0);
});
