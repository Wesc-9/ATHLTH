Deno.serve(async () =>
  Response.json(
    {
      ok: false,
      disabled: true,
      message: "Trail discovery preflight disabled.",
    },
    { status: 410 },
  )
);
