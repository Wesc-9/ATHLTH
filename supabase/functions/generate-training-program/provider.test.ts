import { coachProgramRequest, coachProgramOutput, coachProviderErrorCode } from "./provider.ts";
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
