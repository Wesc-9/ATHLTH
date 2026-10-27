import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";

// ATHLTH+ neural speech. No GPS or medical records are sent. Live coach
// messages may include workout metrics; opt-in is enforced by the iOS UI.
// The server never persists, caches or logs spoken text.
const sample = "Du er godt i gang. Hold et jevnt tempo, og fokuser på neste drag.";
const voiceIDs: Record<string, string> = {
  finn: "nb-NO-FinnNeural",
  iselin: "nb-NO-IselinNeural",
  pernille: "nb-NO-PernilleNeural",
};

// Query the voices supported by the configured Azure resource instead of
// hardcoding the three original voices in the iOS client. No secret or URL
// is ever supplied by the client. Only Norwegian neural ShortNames are used.
type AzureVoice = { ShortName?: string; Locale?: string; Gender?: string };
type CoachVoice = { id: string; name: string; detail: string; shortName: string };
let cachedDirectory: { region: string; expires: number; voices: CoachVoice[] } | null = null;
async function voiceDirectory(key: string, region: string): Promise<CoachVoice[]> {
  if (cachedDirectory && cachedDirectory.region === region &&
      cachedDirectory.expires > Date.now()) return cachedDirectory.voices;
  const response = await fetch(
    "https://" + region + ".tts.speech.microsoft.com/cognitiveservices/voices/list",
    { headers: { "Ocp-Apim-Subscription-Key": key },
      signal: AbortSignal.timeout(5000) },
  );
  if (!response.ok) throw new Error("Azure voices unavailable");
  const records: unknown = await response.json();
  if (!Array.isArray(records) || records.length > 1500)
    throw new Error("Invalid Azure voice catalog");
  const voices = (records as AzureVoice[])
    .filter((voice) => voice.Locale === "nb-NO" &&
      typeof voice.ShortName === "string" &&
      /^nb-NO-[A-Za-z0-9]+Neural$/.test(voice.ShortName))
    .map((voice) => {
      const shortName = voice.ShortName!;
      const legacy = Object.entries(voiceIDs).find(([, value]) => value === shortName);
      const name = shortName.slice("nb-NO-".length, -"Neural".length);
      return {
        id: legacy?.[0] ?? shortName,
        name,
        detail: voice.Gender === "Male" ? "Norsk · mannlig" :
          voice.Gender === "Female" ? "Norsk · kvinnelig" : "Norsk",
        shortName,
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name, "nb"));
  cachedDirectory = { region, expires: Date.now() + 60 * 60_000, voices };
  return voices;
}
const json = (data: Record<string, unknown>, status = 200) =>
  Response.json(data, { status, headers: { "Cache-Control": "no-store" } });
const escapeXML = (s: string): string => s.replace(/[&<>"']/g, (match) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" } as Record<string, string>)[match]);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (Deno.env.get("ATHLTH_AZURE_TTS_ENABLED") !== "true")
    return json({ error: "Azure previews are not configured", code: "NOT_AVAILABLE" }, 503);
  const key = Deno.env.get("AZURE_SPEECH_KEY");
  const region = Deno.env.get("AZURE_SPEECH_REGION");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key || !region || !url || !serviceKey || !/^[a-z0-9-]{2,30}$/.test(region))
    return json({ error: "Voice provider unavailable" }, 503);

  const bearer = req.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!bearer) return json({ error: "Authentication required" }, 401);
  let body: unknown;
  try {
    if (Number(req.headers.get("Content-Length") || "0") > 2048)
      return json({ error: "Request too large" }, 413);
    const raw = await req.text();
    if (raw.length > 2048) return json({ error: "Request too large" }, 413);
    body = JSON.parse(raw);
  } catch { return json({ error: "Invalid request" }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body))
    return json({ error: "Invalid request" }, 400);
  const requestBody = body as Record<string, unknown>;
  const isCatalog = requestBody.action === "catalog";
  const requestedVoice = requestBody.voice;
  if (!isCatalog && (typeof requestedVoice !== "string" ||
      !(/^[a-z]{3,20}$/.test(requestedVoice) ||
        /^nb-NO-[A-Za-z0-9]+Neural$/.test(requestedVoice))))
    return json({ error: "Unsupported voice", code: "UNSUPPORTED_VOICE" }, 400);
  // No arbitrary URL or SSML can be provided by the client.
  const liveText = requestBody.text;
  if (liveText !== undefined &&
      (typeof liveText !== "string" || liveText.trim().length < 1 ||
       liveText.length > 220 || /[\u0000-\u0008\u000e-\u001f]/.test(liveText)))
    return json({ error: "Invalid speech text" }, 400);
  const speech = typeof liveText === "string" ? liveText.trim() : sample;

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error } = await admin.auth.getUser(bearer);
  if (error || !user) return json({ error: "Invalid authentication" }, 401);
  const { data: entitlement, error: entitlementError } = await admin
    .from("subscription_entitlements")
    .select("tier,status,trial_ends_at,current_period_ends_at")
    .eq("user_id", user.id).maybeSingle();
  if (entitlementError) return json({ error: "Entitlement unavailable" }, 503);
  const now = Date.now();
  const validUntil = (s: unknown) => typeof s === "string" && Date.parse(s) > now;
  const eligible = entitlement?.tier === "athlth_plus" &&
    ((entitlement.status === "active" &&
      (entitlement.current_period_ends_at == null || validUntil(entitlement.current_period_ends_at))) ||
     (entitlement.status === "trialing" && validUntil(entitlement.trial_ends_at)));
  if (!eligible) return json({ error: "ATHLTH+ required", code: "PREMIUM_REQUIRED" }, 403);
  // Catalog discovery does not synthesize speech or consume TTS quota.
  // Both catalog and synthesis stay behind verified ATHLTH+ access.
  if (isCatalog) {
    try {
      const voices = await voiceDirectory(key, region);
      return json({ voices: voices.map(({ id, name, detail }) => ({
        id, name, detail,
      })) });
    } catch {
      return json({ error: "Could not load Azure voice catalog",
                    code: "VOICE_CATALOG_UNAVAILABLE" }, 503);
    }
  }

  // The client may select a newer Norwegian voice discovered from Azure.
  // Resolve only against Azure's server-fetched list, never raw client SSML.
  let azureShortName = typeof requestedVoice === "string"
    ? voiceIDs[requestedVoice] : undefined;
  if (!azureShortName) {
    try {
      const voices = await voiceDirectory(key, region);
      azureShortName = voices.find((voice) => voice.id === requestedVoice)?.shortName;
    } catch {
      return json({ error: "Voice directory is unavailable",
                    code: "VOICE_CATALOG_UNAVAILABLE" }, 503);
    }
  }
  if (!azureShortName)
    return json({ error: "Unsupported voice", code: "UNSUPPORTED_VOICE" }, 400);


  // Both routes require the server-verified ATHLTH+ entitlement above.
  // Live training uses its own fair-use cap. Previews keep the existing
  // shared AI-request budget. Both reserve from the SAME F0 monthly cap.
  if (typeof liveText === "string") {
    const { data: reserved, error: budgetError } = await admin.rpc(
      "reserve_athlth_azure_tts_live",
      { p_user_id: user.id, p_characters: speech.length },
    );
    if (budgetError || reserved !== true)
      return json({ error: "Free live voice quota reached or unavailable",
                    code: "FREE_BUDGET_EXHAUSTED" }, 429);
  } else {
    const userBudget = await enforceAIRequestBudget(() =>
      admin.rpc("consume_ai_request_budget", {
        p_user_id: user.id,
        p_feature: "generate-training-program",
      }));
    if (userBudget) return userBudget;

    const { data: reserved, error: budgetError } = await admin.rpc(
      "reserve_athlth_azure_tts_preview",
      { p_characters: speech.length },
    );
    if (budgetError || reserved !== true)
      return json({ error: "Free preview budget reached or unavailable",
                    code: "FREE_BUDGET_EXHAUSTED" }, 429);
  }

  const ssml = '<speak version="1.0" xml:lang="nb-NO"><voice name="' +
    azureShortName + '">' + escapeXML(speech) + '</voice></speak>';
  let azure: Response;
  try {
    azure = await fetch("https://" + region + ".tts.speech.microsoft.com/cognitiveservices/v1", {
      method: "POST",
      headers: {
        "Ocp-Apim-Subscription-Key": key,
        "Content-Type": "application/ssml+xml",
        "X-Microsoft-OutputFormat": "audio-16khz-32kbitrate-mono-mp3",
        "User-Agent": "ATHLTH-AzureCoachVoice",
      },
      body: ssml,
      signal: AbortSignal.timeout(9000),
    });
  } catch { return json({ error: "Voice service timed out" }, 502); }
  if (!azure.ok)
    return json({ error: "Voice provider unavailable", code: "AZURE_UNAVAILABLE" },
      azure.status === 429 ? 429 : 502);
  if (Number(azure.headers.get("Content-Length") || 0) > 250000)
    return json({ error: "Audio response too large" }, 502);
  const buffer = new Uint8Array(await azure.arrayBuffer());
  if (!buffer.length || buffer.length > 250000)
    return json({ error: "Invalid audio response" }, 502);
  let binary = "";
  for (const byte of buffer) binary += String.fromCharCode(byte);
  return json({ voice: requestedVoice, audioBase64: btoa(binary) });
});
