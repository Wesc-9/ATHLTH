import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type DeleteAccountRequest = { confirm?: boolean };

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

async function revokeAppleRefreshToken(refreshToken: string): Promise<boolean> {
  const clientID = Deno.env.get("APPLE_CLIENT_ID") ?? "com.wesc9.athlth";
  const clientSecret = await appleClientSecret();

  const response = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientID,
      client_secret: clientSecret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
  });

  if (response.ok) return true;

  console.error("Apple token revocation failed", {
    status: response.status,
    body: await response.text(),
  });
  return false;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Missing authenticated user." }, 401);
  }

  const token = authorization.slice(7).trim();
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "Account deletion is temporarily unavailable." }, 500);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: userError } = await admin.auth.getUser(token);
  if (userError || !user) {
    return json({ error: "Your sign-in session is no longer valid. Please sign in again." }, 401);
  }

  let body: DeleteAccountRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  if (body.confirm !== true) {
    return json({ error: "Account deletion was not confirmed." }, 400);
  }

  const isAppleUser =
    user.app_metadata?.provider === "apple" ||
    user.identities?.some((identity) => identity.provider === "apple") === true;

  let appleRefreshToken: string | null = null;
  let appleTokenLookupFailed = false;

  if (isAppleUser) {
    const { data: appleTokenRow, error: appleTokenError } = await admin
      .from("apple_sign_in_tokens")
      .select("refresh_token")
      .eq("user_id", user.id)
      .maybeSingle();

    if (appleTokenError) {
      console.error("Unable to load Apple revocation token.", {
        userID: user.id,
        message: appleTokenError.message,
      });
      appleTokenLookupFailed = true;
    } else {
      appleRefreshToken = appleTokenRow?.refresh_token ?? null;
    }
  }

  const avatarPath = `${user.id}/avatar.jpg`;
  const { error: avatarDeleteError } = await admin.storage
    .from("profile-avatars")
    .remove([avatarPath]);

  if (avatarDeleteError) {
    console.error("ATHLTH avatar cleanup failed.", {
      userID: user.id,
      message: avatarDeleteError.message,
    });
    return json({ error: "Unable to remove profile media before account deletion." }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("ATHLTH account deletion failed.", {
      userID: user.id,
      message: deleteError.message,
    });
    return json({ error: "Unable to delete the ATHLTH account." }, 500);
  }

  // The ATHLTH account is gone at this point. Apple revocation is intentionally
  // performed afterwards so a temporary Apple/API failure can never block the
  // user's account-deletion request.
  let appleRevoked = !isAppleUser;
  let appleManualRevokeRequired =
    isAppleUser && (appleTokenLookupFailed || !appleRefreshToken);

  if (isAppleUser && appleRefreshToken) {
    try {
      appleRevoked = await revokeAppleRefreshToken(appleRefreshToken);
      appleManualRevokeRequired = !appleRevoked;
    } catch (error) {
      const message = error instanceof Error ? error.message : "UNKNOWN";
      console.error("Apple revocation could not be completed after account deletion.", {
        userID: user.id,
        reason: message,
      });
      appleManualRevokeRequired = true;
    }
  }

  return json({
    deleted: true,
    apple_revoked: appleRevoked,
    apple_manual_revoke_required: appleManualRevokeRequired,
  });
});
