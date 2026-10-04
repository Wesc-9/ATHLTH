import test from "node:test";
import assert from "node:assert/strict";
import { enforceAIRequestBudget } from "./ai-request-budget.ts";

test("allowed requests proceed; exhausted budgets return 429 and retry time", async () => {
  assert.equal(await enforceAIRequestBudget(async () => ({ data: [{ allowed: true }], error: null })), null);
  const response = await enforceAIRequestBudget(async () => ({ data: [{ allowed: false, retry_after: 33.2 }], error: null }));
  assert.equal(response?.status, 429);
  assert.equal(response?.headers.get("Retry-After"), "34");
  assert.equal((await response?.json()).code, "AI_RATE_LIMIT");
});

test("database failures and invalid results prevent paid requests", async () => {
  for (const result of [{ data: null, error: "offline" }, { data: [], error: null }, { data: [{ allowed: false }], error: null }]) {
    assert.equal((await enforceAIRequestBudget(async () => result))?.status, 503);
  }
  assert.equal((await enforceAIRequestBudget(async () => { throw Error("network"); }))?.status, 503);
});
