import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { enforceAIRequestBudget } from "./_shared/ai-request-budget.ts";

type Candidate = {
  id: string;
  name: string;
  equipment: string[];
  primaryMuscles: string[];
};
type ScanRequest = {
  imageBase64?: string;
  language?: string;
  candidates?: Candidate[];
};

const json = (payload: Record<string, unknown>, status = 200) =>
  Response.json(payload, { status, headers: { "Cache-Control": "no-store" } });

function textOutput(body: any): string | null {
  if (typeof body?.choices?.[0]?.message?.content === "string") {
    return body.choices[0].message.content;
  }
  return null;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Sign-in required." }, 401);
  }

  const baseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!baseURL || !serviceKey || !groqKey) {
    return json({ error: "Equipment scanner is unavailable." }, 503);
  }

  const admin = createClient(baseURL, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: userError } =
    await admin.auth.getUser(authorization.slice(7).trim());
  if (userError || !user) return json({ error: "Invalid sign-in session." }, 401);

  const { data: entitlement, error: planError } = await admin
    .from("subscription_entitlements")
    .select("status,trial_ends_at,current_period_ends_at")
    .eq("user_id", user.id).maybeSingle();
  if (planError) return json({ error: "ATHLTH+ access could not be verified." }, 503);
  const now = Date.now();
  const trial = entitlement?.status === "trialing" &&
    typeof entitlement.trial_ends_at === "string" &&
    Date.parse(entitlement.trial_ends_at) > now;
  const paid = entitlement?.status === "active" &&
    (entitlement.current_period_ends_at == null ||
      (typeof entitlement.current_period_ends_at === "string" &&
        Date.parse(entitlement.current_period_ends_at) > now));
  if (!trial && !paid) {
    return json({
      error: "The equipment scanner requires ATHLTH+.",
      code: "PREMIUM_REQUIRED",
    }, 403);
  }

  let body: ScanRequest;
  try { body = await request.json(); }
  catch { return json({ error: "Invalid scan request." }, 400); }

  // Request payloads contain a deliberately resized still photo, never live video.
  const base64 = body.imageBase64 ?? "";
  if (typeof base64 !== "string" || base64.length < 100 ||
      base64.length > 1_400_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    return json({ error: "The image must be a JPEG smaller than 1 MB." }, 413);
  }
  const cleanCandidates = new Map<string, Candidate>();
  if (Array.isArray(body.candidates)) {
    for (const item of body.candidates.slice(0, 110)) {
      const id = String(item?.id ?? "").trim();
      const name = String(item?.name ?? "").trim();
      if (!/^[a-fA-F0-9-]{36}$/.test(id) || !name || cleanCandidates.has(id)) continue;
      cleanCandidates.set(id, {
        id,
        name: name.slice(0, 100),
        equipment: Array.isArray(item?.equipment)
          ? item.equipment.slice(0, 5).map((v) => String(v).slice(0, 40))
          : [],
        primaryMuscles: Array.isArray(item?.primaryMuscles)
          ? item.primaryMuscles.slice(0, 4).map((v) => String(v).slice(0, 40))
          : [],
      });
    }
  }
  const candidates = [...cleanCandidates.values()];
  if (candidates.length === 0) return json({ error: "No exercises to match." }, 400);

  const budget = await enforceAIRequestBudget(() =>
    admin.rpc("consume_ai_request_budget", {
      p_user_id: user.id, p_feature: "strength-exercise-planner",
    })
  );
  if (budget) return budget;

  const language = body.language === "en" ? "English" : "Norwegian Bokmål";
  const prompt = [
    "You are ATHLTH's conservative gym equipment vision assistant.",
    "Inspect ONLY the attached gym equipment photo. Do not infer injuries, diagnoses, people, or capabilities.",
    "Identify equipment category and what exercises the VISIBLE equipment can reasonably support.",
    "Choose exercise IDs ONLY from the supplied candidate array. Never invent IDs, brands, models, or exercises.",
    "An exercise is valid only when the machine or attachment is plausible from the visible photo.",
    "Prefer 1-6 useful matches in descending relevance. No duplicates.",
    "If the photo shows no identifiable exercise equipment, use confidence=low, equipmentName='Unknown', and return an EMPTY list.",
    "If there are multiple possible machine types, say so in the explanation and use confidence=low or medium.",
    "Do not claim that exercise setup or technique is safe based only on a photo.",
    "Return one JSON object with equipmentName, confidence ('low'|'medium'|'high'), explanation, exerciseIDs.",
    "Write equipmentName and explanation in " + language + ".",
    "Candidates: " + JSON.stringify(candidates),
  ].join("\n");

  let ai: Response;
  try {
    ai = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + groqKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("GROQ_VISION_MODEL") ?? "qwen/qwen3.8-27b",
        messages: [{
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: "data:image/jpeg;base64," + base64 } },
          ],
        }],
        response_format: { type: "json_object" },
        temperature: 0,
        max_completion_tokens: 900,
        stream: false,
      }),
      signal: AbortSignal.timeout(27000),
    });
  } catch {
    return json({ error: "The image could not be analyzed." }, 502);
  }
  if (!ai.ok) return json({ error: "ATHLTH AI could not analyze this image." }, 502);

  let parsed: any;
  try {
    parsed = JSON.parse(textOutput(await ai.json()) ?? "");
  } catch {
    return json({ error: "ATHLTH AI returned an invalid equipment analysis." }, 502);
  }
  const confidence = ["high", "medium", "low"].includes(parsed?.confidence)
    ? parsed.confidence as "high" | "medium" | "low" : "low";
  const equipmentName = typeof parsed?.equipmentName === "string"
    ? parsed.equipmentName.trim().slice(0, 90) : "";
  const explanation = typeof parsed?.explanation === "string"
    ? parsed.explanation.trim().slice(0, 360) : "";
  const exerciseIDs: string[] = [];
  if (confidence !== "low" && Array.isArray(parsed?.exerciseIDs)) {
    for (const raw of parsed.exerciseIDs.slice(0, 14)) {
      const id = String(raw);
      if (cleanCandidates.has(id) && !exerciseIDs.includes(id)) exerciseIDs.push(id);
      if (exerciseIDs.length === 6) break;
    }
  }
  // No photo is persisted. Only a matched ID list and non-sensitive explanation leave this function.
  return json({
    equipmentName: equipmentName || "Unknown",
    confidence,
    explanation,
    exerciseIDs,
  });
});
