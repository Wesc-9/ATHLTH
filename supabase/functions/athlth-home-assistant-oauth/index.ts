import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const REDIRECT_URI = "athlth://home-assistant";

const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="robots" content="noindex,nofollow">
  <link rel="redirect_uri" href="${REDIRECT_URI}">
  <title>ATHLTH Home Assistant Authorization</title>
</head>
<body>
  <p>ATHLTH Home Assistant authorization client.</p>
</body>
</html>`;

Deno.serve((request: Request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: {
        Allow: "GET, HEAD",
        "Cache-Control": "public, max-age=300",
      },
    });
  }

  return new Response(request.method === "HEAD" ? null : html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "X-Content-Type-Options": "nosniff",
      "Content-Security-Policy": "default-src 'none'; style-src 'none'; img-src 'none'; frame-ancestors 'none'",
      "Referrer-Policy": "no-referrer",
    },
  });
});
