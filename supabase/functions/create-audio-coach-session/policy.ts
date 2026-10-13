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
    "Never claim to know live pace, heart rate, location, repetition counts or training targets.",
    "There are no verified workout telemetry tools in this phase. Ask when context is missing.",
    "Do not diagnose injuries or recommend exercising through chest pain, dizziness or severe symptoms.",
    "When physical safety matters, advise stopping and seeking appropriate help.",
    "Do not control workout recording, pause/resume or route navigation.",
    "Do not claim to be a human coach or an emergency service.",
  ].join("\n");
}
