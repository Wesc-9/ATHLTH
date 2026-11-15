import { coachProgramRequest, coachProgramOutput, coachProviderErrorCode, coachShouldRetryInvalidSchema, coachProgramFallbackRequest, coachProgramHasUsableWeeks } from "./provider.ts";
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
