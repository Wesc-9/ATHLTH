import { createClient } from "npm:@supabase/supabase-js@2";

type DeleteAccountRequest = {
  confirm?: boolean;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Missing authenticated user." }, 401);
  }

  const token = authorization.slice("Bearer ".length).trim();
  if (!token) {
    return json({ error: "Missing authenticated user." }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    console.error("delete-account is missing required Supabase environment variables.");
    return json({ error: "Account deletion is temporarily unavailable." }, 500);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const {
    data: { user },
    error: userError,
  } = await admin.auth.getUser(token);

  if (userError || !user) {
    console.warn("delete-account rejected an invalid user token.", {
      message: userError?.message ?? "No user returned",
    });
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

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);

  if (deleteError) {
    console.error("ATHLTH account deletion failed.", {
      userID: user.id,
      message: deleteError.message,
    });
    return json({ error: "Unable to delete the ATHLTH account." }, 500);
  }

  return json({ deleted: true });
});
