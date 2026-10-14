export type GroqTurn = {
  language: "no" | "en";
  tone: "balanced" | "motivating";
  text: string;
  audioBase64: string | null;
};

export function validateTurn(value: unknown): GroqTurn | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const p = value as Record<string, unknown>;
  if (p.providerConsent !== true ||
      (p.language !== "no" && p.language !== "en") ||
      (p.tone !== "balanced" && p.tone !== "motivating")) return null;
  const text = typeof p.text === "string" ? p.text.trim() : "";
  const audioBase64 = typeof p.audioBase64 === "string" ? p.audioBase64 : null;
  if (text && (text.length > 450 || audioBase64)) return null;
  if (!text && (!audioBase64 || audioBase64.length < 50 || audioBase64.length > 520_000)) return null;
  if (audioBase64 && (p.microphoneConsent !== true || !/^[A-Za-z0-9+/=]+$/.test(audioBase64))) return null;
  // The server purposely does not read workoutStatus/healthContext/location
  // even if a modified client includes it.
  return { language: p.language, tone: p.tone, text, audioBase64 };
}

export function decodeWavBase64(encoded: string): Uint8Array | null {
  try {
    const binary = atob(encoded);
    if (binary.length < 500 || binary.length > 390_000) return null;
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    const text = (start: number) => String.fromCharCode(...bytes.subarray(start, start + 4));
    if (text(0) !== "RIFF" || text(8) !== "WAVE") return null;
    const view = new DataView(bytes.buffer);
    if (text(12) !== "fmt " || view.getUint32(16, true) < 16 ||
        view.getUint16(20, true) !== 1 || view.getUint16(22, true) !== 1 ||
        view.getUint32(24, true) !== 16000 || view.getUint16(34, true) !== 16) return null;
    if (text(36) !== "data") return null;
    const declaredLength = view.getUint32(40, true);
    if (declaredLength < 3200 || declaredLength > bytes.length - 44 ||
        declaredLength > 386_000) return null;
    return bytes;
  } catch { return null; }
}

export function coachPrompt(language: GroqTurn["language"], tone: GroqTurn["tone"]): string {
  return [
    "You are ATHLTH Audio Coach during exercise. Respond in " +
      (language === "no" ? "natural Norwegian Bokmål" : "English") + ".",
    tone === "motivating" ? "Use a motivating, positive, grounded tone." :
      "Use a calm, helpful and clear tone.",
    "Answer with one or two short sentences suitable for spoken audio.",
    "No Markdown, emoji or stage directions.",
    "You have NO verified live workout data and NO access to HealthKit.",
    "Never invent the user's pace, heart rate, planned intervals, goals, position or recovery status.",
    "When asked about current metrics, say that live data sharing is not available for Groq pilot.",
    "You cannot pause, start, stop or control a workout.",
    "Do not diagnose injuries or encourage continuing through chest pain, severe dizziness or distress.",
    "If symptoms may be urgent, advise stopping and seeking appropriate emergency care.",
    "Do not imply your response is medical advice.",
  ].join("\n");
}
