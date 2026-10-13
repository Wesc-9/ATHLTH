export async function enforceAIRequestBudget(
  consume: () => PromiseLike<{ data: unknown; error: unknown }>,
): Promise<Response | null> {
  try {
    const { data, error } = await consume();
    const row = Array.isArray(data) ? data[0] : null;
    if (error || !row || typeof row.allowed !== "boolean") throw new Error("Invalid AI budget");
    if (row.allowed) return null;
    if (!Number.isFinite(row.retry_after)) throw new Error("Invalid AI retry");
    return Response.json({
      error: "AI request limit reached.", code: "AI_RATE_LIMIT",
    }, {
      status: 429,
      headers: { "Retry-After": String(Math.min(86400, Math.max(1, Math.ceil(row.retry_after)))), "Cache-Control": "no-store" },
    });
  } catch {
    return Response.json({ error: "AI access temporarily unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
