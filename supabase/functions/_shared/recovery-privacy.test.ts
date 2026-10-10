import assert from "node:assert/strict";
import {
  canForwardRecoveryHealth,
  mustRejectUnconsentedInsight,
  mustRejectUnreleasedAutomaticCoachSharing,
} from "./recovery-privacy.ts";

assert.equal(canForwardRecoveryHealth(undefined), false);
assert.equal(canForwardRecoveryHealth(false), false);
assert.equal(canForwardRecoveryHealth(true), true);

assert.equal(mustRejectUnconsentedInsight("insight", undefined), true);
assert.equal(mustRejectUnconsentedInsight("insight", false), true);
assert.equal(mustRejectUnconsentedInsight("insight", true), false);
assert.equal(mustRejectUnconsentedInsight("ask", undefined), false);
assert.equal(mustRejectUnconsentedInsight("ask", true), false);


// The unreleased ongoing-sharing mode must be rejected independently
// of a true shareHealthData value or a modified iOS client.
assert.equal(mustRejectUnreleasedAutomaticCoachSharing("ask", "automatic"), true);
assert.equal(mustRejectUnreleasedAutomaticCoachSharing("ask", "confirmEachQuestion"), false);
assert.equal(mustRejectUnreleasedAutomaticCoachSharing("ask", undefined), false);
assert.equal(mustRejectUnreleasedAutomaticCoachSharing("insight", undefined), false);

console.log("Recovery AI health-sharing guard tests passed");
