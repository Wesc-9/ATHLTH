import { createClient } from "npm:@supabase/supabase-js@2";

type RegisterRequest = { authorization_code?: string };

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const encoder = new TextEncoder();

function b64url(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function pemBytes(pem: string): Uint8Array {
  const cleaned = pem
    .replaceAll("\\n", "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function appleClientSecret(): Promise<string> {
  const teamID = Deno.env.get("APPLE_TEAM_ID") ?? "D3AX7B6RMW";
  const keyID = Deno.env.get("APPLE_KEY_ID");
  const clientID = Deno.env.get("APPLE_CLIENT_ID") ?? "com.wesc9.athlth";
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!keyID || !privateKey) throw new Error("CONFIG_MISSING");

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const payload = b64url(JSON.stringify({
    iss: teamID,
    iat: now,
    exp: now + 60 * 60 * 24 * 30,
    aud: "https://appleid.apple.com",
    sub: clientID,
  }));
  const signingInput = `${header}.${payload}`;
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  ));
  return `${signingInput}.${b64url(signature)}`;
}

async function exchangeCode(code: string): Promise<string> {
  const clientID = Deno.env.get("APPLE_CLIENT_ID") ?? "com.wesc9.athlth";
  const clientSecret = await appleClientSecret();

  const response = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientID,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    }),
  });

  const raw = await response.text();
  if (!response.ok) {
    console.error("Apple token exchange failed", { status: response.status, body: raw });
    throw new Error("EXCHANGE_FAILED");
  }

  const payload = JSON.parse(raw) as { refresh_token?: string };
  if (!payload.refresh_token) throw new Error("REFRESH_TOKEN_MISSING");
  return payload.refresh_token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Missing authenticated user." }, 401);
  }

  const jwt = authorization.slice(7).trim();
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!jwt || !supabaseURL || !serviceRoleKey) {
    return json({ error: "Apple authorization registration is unavailable." }, 500);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !user) {
    return json({ error: "Your sign-in session is no longer valid." }, 401);
  }

  let body: RegisterRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const authorizationCode = body.authorization_code?.trim();
  if (!authorizationCode) return json({ error: "Missing Apple authorization code." }, 400);

  try {
    const refreshToken = await exchangeCode(authorizationCode);
    const { error: upsertError } = await admin
      .from("apple_sign_in_tokens")
      .upsert({
        user_id: user.id,
        refresh_token: refreshToken,
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });

    if (upsertError) {
      console.error("Unable to store Apple revocation token", {
        userID: user.id,
        message: upsertError.message,
      });
      return json({ error: "Unable to prepare Apple account revocation." }, 500);
    }

    return json({ registered: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN";
    if (message === "CONFIG_MISSING") {
      console.error("Apple revocation secrets are not configured.");
      return json({ error: "Apple account revocation is not configured." }, 503);
    }
    return json({ error: "Unable to prepare Apple account revocation." }, 502);
  }
});
