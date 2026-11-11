/** One provider contract for Coach plans. Chat Completions supports strict
 * GPT-OSS JSON schemas without depending on the Responses compatibility layer. */
export function coachProgramRequest(model: string, instructions: string, constraints: unknown, schema: unknown) {
  return {
    model,
    reasoning_effort: "medium",
    messages: [
      { role: "system", content: instructions },
      { role: "user", content: JSON.stringify(constraints) },
    ],
    response_format: {
      type: "json_schema",
      json_schema: { name: "athlth_training_program", strict: true, schema },
    },
  };
}

export function coachProgramOutput(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const choices = (payload as { choices?: { message?: { content?: unknown; refusal?: unknown } }[] }).choices;
  const message = Array.isArray(choices) ? choices[0]?.message : undefined;
  if (message?.refusal) return null;
  return typeof message?.content === "string" && message.content.trim() ? message.content : null;
}

/** Never persist provider prose or generated content: either may echo user notes. */
export function coachProviderErrorCode(payload: unknown): string {
  const code = (payload as { error?: { code?: unknown } } | null)?.error?.code;
  const allowed = ["invalid_request_error", "model_not_found", "model_decommissioned", "json_validate_failed", "rate_limit_exceeded", "context_length_exceeded"];
  return typeof code === "string" && allowed.includes(code) ? code : "provider_rejected_request";
}
