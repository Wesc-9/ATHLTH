import {
  checkLiveCoachConsent,
  coachSessionInstructions,
} from "./policy.ts";

Deno.test("requires both microphone and AI audio consent", () => {
  const base = { language: "no", tone: "motivating" };
  if (checkLiveCoachConsent({ ...base, microphoneConsent: true })) {
    throw new Error("Should reject missing provider consent");
  }
  if (checkLiveCoachConsent({ ...base, aiAudioProcessingConsent: true })) {
    throw new Error("Should reject missing microphone consent");
  }
  if (checkLiveCoachConsent({ ...base, microphoneConsent: true, aiAudioProcessingConsent: true })?.language !== "no") {
    throw new Error("Expected opt-in to be accepted");
  }
  if (checkLiveCoachConsent({ ...base, microphoneConsent: true, aiAudioProcessingConsent: true, language: "other" })) {
    throw new Error("Unsupported language must be rejected");
  }
});

Deno.test("voice prompt cannot infer health or exercise data", () => {
  const text = coachSessionInstructions({ language: "no", tone: "motivating" });
  for (const expected of ["Norwegian Bokmål", "never falsely reassuring", "Never claim to know live pace"]) {
    if (!text.includes(expected)) throw new Error("Missing safety constraint: " + expected);
  }
});
