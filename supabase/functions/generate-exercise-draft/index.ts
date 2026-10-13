import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { enforceAIRequestBudget } from "../_shared/ai-request-budget.ts";

const allowedMuscles = ["Chest","Back","Shoulders","Biceps","Triceps","Forearms","Core","Glutes","Quads","Hamstrings","Calves"];
const cors = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const json = (data: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: cors });

function outputText(payload: any): string | undefined {
  if (typeof payload?.output_text === "string") return payload.output_text;
  for (const item of payload?.output ?? []) {
    for (const part of item?.content ?? []) {
      if (part?.type === "output_text" && typeof part?.text === "string") return part.text;
    }
  }
  return undefined;
}

const schema = {
  type: "object",
  additionalProperties: false,
  required: ["name", "primaryMuscles", "secondaryMuscles", "equipment", "instructions", "videoBrief"],
  properties: {
    name: { type: "string" },
    primaryMuscles: { type: "array", items: { type: "string", enum: allowedMuscles } },
    secondaryMuscles: { type: "array", items: { type: "string", enum: allowedMuscles } },
    equipment: { type: "array", items: { type: "string" } },
    instructions: { type: "array", items: { type: "string" } },
    videoBrief: { type: "string" },
  },
};

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);
  const bearer = request.headers.get("Authorization");
  if (!bearer?.startsWith("Bearer ")) return json({ error: "Sign-in required." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const aiKey = Deno.env.get("GROQ_API_KEY");
  if (!url || !secret || !aiKey) return json({ error: "ATHLTH AI unavailable." }, 503);

  const supabase = createClient(url, secret, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: authError } =
    await supabase.auth.getUser(bearer.slice(7).trim());
  if (authError || !user) return json({ error: "Invalid session." }, 401);

  // Match the existing strength AI entitlement and shared per-user budget.
  const { data: plan, error: planError } = await supabase
    .from("subscription_entitlements")
    .select("status,trial_ends_at,current_period_ends_at")
    .eq("user_id", user.id).maybeSingle();
  if (planError) return json({ error: "Subscription verification unavailable." }, 503);
  const now = Date.now();
  const trial = plan?.status === "trialing" &&
    typeof plan.trial_ends_at === "string" && Date.parse(plan.trial_ends_at) > now;
  const paid = plan?.status === "active" &&
    (plan.current_period_ends_at == null ||
      (typeof plan.current_period_ends_at === "string" &&
        Date.parse(plan.current_period_ends_at) > now));
  if (!trial && !paid) {
    return json({ error: "ATHLTH+ is required for AI exercise drafting.", code: "PREMIUM_REQUIRED" }, 403);
  }

  let payload: any;
  try { payload = await request.json(); } catch { return json({ error: "Invalid input." }, 400); }
  const description = typeof payload?.description === "string" ? payload.description.trim() : "";
  if (description.length < 12 || description.length > 800) {
    return json({ error: "Describe the exercise in 12 to 800 characters." }, 400);
  }
  const language = payload?.language === "en" ? "English" : "Norwegian Bokmål";
  const budget = await enforceAIRequestBudget(() =>
    supabase.rpc("consume_ai_request_budget", {
      p_user_id: user.id,
      p_feature: "strength-exercise-planner",
    })
  );
  if (budget) return budget;

  const instructions = [
    "You are ATHLTH exercise editor creating a DRAFT, not a verified training demonstration.",
    "Describe one realistic strength or mobility exercise from the person's description.",
    "Never fabricate an unsafe complex stunt or imply a video exists.",
    "If user description is ambiguous, choose a safer conventional variant.",
    "Do not diagnose, provide injury treatment, or promise outcomes.",
    "Only use the exact allowed primary and secondary muscle group names.",
    "Give 1-3 primary muscles, up to 3 secondary muscles, no overlap.",
    "Keep equipment to familiar descriptive names, max 5.",
    "Return 3-6 numbered-in-order instruction sentences without embedded numbers.",
    "Use plain language appropriate for a novice, with neutral form cues and no absolute anatomy claims.",
    "videoBrief describes 2-3 camera shots a coach could record, not a ready-made AI video.",
    "Write every free-text field in " + language + ".",
  ].join("\n");

  let ai: Response;
  try {
    ai = await fetch("https://api.groq.com/openai/v1/responses", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + aiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("GROQ_TRAINING_MODEL") ?? "openai/gpt-oss-120b",
        reasoning: { effort: "low" },
        instructions,
        input: JSON.stringify({ description: description.slice(0, 800), language }),
        text: { format: { type: "json_schema", name: "athlth_exercise_draft", strict: true, schema } },
      }),
      signal: AbortSignal.timeout(26000),
    });
  } catch {
    return json({ error: "AI service could not be reached." }, 502);
  }
  if (!ai.ok) return json({ error: "ATHLTH AI could not draft this exercise." }, 502);
  let draft: any;
  try {
    const value = outputText(await ai.json());
    draft = JSON.parse(value ?? "");
  } catch {
    return json({ error: "AI returned an invalid draft." }, 502);
  }
  const muscles = (value: unknown): string[] =>
    Array.isArray(value) ? [...new Set(value.filter((x): x is string =>
      typeof x === "string" && allowedMuscles.includes(x)))].slice(0, 3) : [];
  const primary = muscles(draft.primaryMuscles);
  const secondary = muscles(draft.secondaryMuscles).filter(x => !primary.includes(x));
  const equipment = Array.isArray(draft.equipment) ? draft.equipment
    .filter((x: unknown) => typeof x === "string")
    .map((x: string) => x.trim().slice(0, 50)).filter(Boolean).slice(0, 5) : [];
  const steps = Array.isArray(draft.instructions) ? draft.instructions
    .filter((x: unknown) => typeof x === "string")
    .map((x: string) => x.trim().slice(0, 230)).filter(Boolean).slice(0, 6) : [];
  const name = typeof draft.name === "string" ? draft.name.trim().slice(0, 90) : "";
  if (!name || !primary.length || steps.length < 2) {
    return json({ error: "AI draft needs review; try describing the movement more clearly." }, 422);
  }
  return json({
    name,
    primaryMuscles: primary,
    secondaryMuscles: secondary,
    equipment,
    instructions: steps,
    videoBrief: typeof draft.videoBrief === "string" ? draft.videoBrief.trim().slice(0, 500) : "",
  });
});
