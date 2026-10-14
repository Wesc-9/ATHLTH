/**
 * Pure request validation, separate from the paid-provider token endpoint.
 * Workout metrics are intentionally not accepted in phase 1.
 */
export type LiveCoachSessionChoices = {
  language: "no" | "en";
  tone: "balanced" | "motivating";
};

export function checkLiveCoachConsent(input: unknown): LiveCoachSessionChoices | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  const value = input as Record<string, unknown>;
  if (value.microphoneConsent !== true || value.aiAudioProcessingConsent !== true) {
    return null;
  }
  if (value.language !== "no" && value.language !== "en") return null;
  if (value.tone !== "balanced" && value.tone !== "motivating") return null;
  return { language: value.language, tone: value.tone };
}

export function coachSessionInstructions(choices: LiveCoachSessionChoices): string {
  const language = choices.language === "no" ? "Norwegian Bokmål" : "English";
  const tone = choices.tone === "motivating"
    ? "Warm, encouraging and energetic, but never falsely reassuring."
    : "Calm and encouraging.";
  return [
    "You are ATHLTH, a voice conversation assistant for people exercising.",
    "Always speak " + language + ". Use natural, short spoken sentences.",
    "Tone: " + tone,
    "Respond briefly, usually in one or two sentences, unless asked to explain.",
    "Never claim to know live pace, heart rate, location, repetition counts or training targets unless returned by a trusted get_live_workout_status tool call.",
    "A workout status function may be offered only after the user separately consents. Never assume it is available.",
    "If the user asks about their current workout and a workout status function is available, call it first. Treat null metrics or unavailable as unknown.",
    "Never infer speed or heart rate from distance or elapsed time alone. Never fabricate metrics, goals or clinical recommendations.",
    "Only use the fields returned in the latest tool result; do not extrapolate future measurements.",
    "Do not diagnose injuries or recommend exercising through chest pain, dizziness or severe symptoms.",
    "When physical safety matters, advise stopping and seeking appropriate help.",
    "Do not control workout recording, pause/resume or route navigation.",
    "Do not claim to be a human coach or an emergency service.",
  ].join("\n");
}

/**
 * Keep spoken responses short. This per-response cap does not replace
 * account-level usage limits or provider billing controls.
 */
export function realtimeCoachSessionConfiguration(
  choices: LiveCoachSessionChoices,
  model = "gpt-realtime-2.1",
) {
  return {
    type: "realtime",
    model,
    max_output_tokens: 512,
    instructions: coachSessionInstructions(choices),
    audio: { output: { voice: "marin" } },
  };
}
