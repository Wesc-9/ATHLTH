import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CLIENT_ID = "https://hnkybbzxffvyhzrstqdo.supabase.co/functions/v1/athlth-home-assistant-oauth";

const metadata = {
  client_id: CLIENT_ID,
  client_name: "ATHLTH",
  client_uri: "https://github.com/Wesc-9/ATHLTH",
  redirect_uris: ["athlth://home-assistant"],
  grant_types: ["authorization_code"],
  response_types: ["code"],
  token_endpoint_auth_method: "none",
};

Deno.serve((request: Request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        Allow: "GET, HEAD",
        "Cache-Control": "public, max-age=300",
      },
    });
  }

  const body = request.method === "HEAD" ? null : JSON.stringify(metadata);

  return new Response(body, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
