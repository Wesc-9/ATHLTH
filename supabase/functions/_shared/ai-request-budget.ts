export async function enforceAIRequestBudget(
  consume: () => PromiseLike<{ data: unknown; error: unknown }>,
): Promise<Response | null> {
  try {
    const { data, error } = await consume();
    const row = Array.isArray(data) ? data[0] : null;
    if (error || !row || typeof row.allowed !== "boolean") throw new Error("Invalid budget response");
    if (row.allowed) return null;
    if (!Number.isFinite(row.retry_after)) throw new Error("Invalid retry interval");
    return Response.json({ error: "AI request limit reached. Please try again later.", code: "AI_RATE_LIMIT" }, {
      status: 429,
      headers: { "Retry-After": String(Math.min(86400, Math.max(1, Math.ceil(row.retry_after)))), "Cache-Control": "no-store" },
    });
  } catch {
    // Never call the paid provider when the server budget cannot be checked.
    return Response.json({ error: "AI access is temporarily unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
