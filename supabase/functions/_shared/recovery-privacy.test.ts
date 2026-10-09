import assert from "node:assert/strict";
import {
  canForwardRecoveryHealth,
  mustRejectUnconsentedInsight,
} from "./recovery-privacy.ts";

assert.equal(canForwardRecoveryHealth(undefined), false);
assert.equal(canForwardRecoveryHealth(false), false);
assert.equal(canForwardRecoveryHealth(true), true);

assert.equal(mustRejectUnconsentedInsight("insight", undefined), true);
assert.equal(mustRejectUnconsentedInsight("insight", false), true);
assert.equal(mustRejectUnconsentedInsight("insight", true), false);
assert.equal(mustRejectUnconsentedInsight("ask", undefined), false);
assert.equal(mustRejectUnconsentedInsight("ask", true), false);

console.log("Recovery AI health-sharing guard tests passed");
