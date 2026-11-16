import { createClient } from "npm:@supabase/supabase-js@2.57.4";

/**
 * Account support is intentionally separate from workouts, messages and
 * HealthKit. Only a verified Owner may suspend/restore accounts or submit a
 * deletion-review request. No direct account deletion is exposed here.
 * The service-role key never leaves this server-side Edge Function.
 */
type Action = "suspend" | "restore" | "request_deletion";
type Input = {
  action?: Action;
  user_id?: string;
  confirm_username?: string;
  reason?: string;
};

function reply(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

const UUID = /^[a-f\d]{8}-[a-f\d]{4}-[1-8][a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/i;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return reply({ error: "Authentication required" }, 401);
  }
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return reply({ error: "Not configured" }, 503);

  const admin = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: actorError } =
    await admin.auth.getUser(authorization.substring(7));
  if (actorError || !user || user.is_anonymous) {
    return reply({ error: "Invalid session" }, 401);
  }
  const { data: actorRole, error: roleError } = await admin
    .from("account_roles").select("role")
    .eq("user_id", user.id).maybeSingle();
  if (roleError || actorRole?.role !== "owner") {
    return reply({ error: "Only the ATHLTH owner can manage accounts" }, 403);
  }

  let input: Input;
  try {
    const raw = await req.text();
    if (raw.length > 3_000) return reply({ error: "Request too long" }, 413);
    input = JSON.parse(raw) as Input;
  } catch {
    return reply({ error: "Invalid input" }, 400);
  }
  const target = typeof input.user_id === "string"
    ? input.user_id.trim().toLowerCase() : "";
  const reason = typeof input.reason === "string" ? input.reason.trim() : "";
  const confirm = typeof input.confirm_username === "string"
    ? input.confirm_username.trim() : "";
  const action = input.action;
  if (
    !UUID.test(target) ||
    !["suspend", "restore", "request_deletion"].includes(action ?? "") ||
    target === user.id.toLowerCase() ||
    reason.length < 10 || reason.length > 500
  ) {
    return reply({ error: "Invalid account-support request" }, 422);
  }

  const { data: targetRole, error: targetRoleError } = await admin
    .from("account_roles").select("role")
    .eq("user_id", target).maybeSingle();
  if (targetRoleError || !targetRole || targetRole.role === "owner") {
    return reply({ error: "Account is protected or unavailable" }, 403);
  }

  const { data: targetProfile, error: profileError } = await admin
    .from("profiles").select("username")
    .eq("id", target).maybeSingle();
  if (profileError || !targetProfile ||
      targetProfile.username?.toLowerCase() !== confirm.toLowerCase()) {
    return reply({ error: "Please confirm the account username" }, 422);
  }

  if (action === "request_deletion") {
    // GDPR: deletion requires an individual review of lawful retention and
    // ancillary storage / Apple sign-in token cleanup. This ONLY queues it.
    const { error: queueError } = await admin
      .from("athlth_admin_deletion_requests")
      .insert({ requested_by: user.id, target_id: target, reason });
    if (queueError) {
      return reply({ error: queueError.code === "23505"
        ? "A deletion request is already pending"
        : "Unable to queue deletion review" }, queueError.code === "23505" ? 409 : 503);
    }
    await admin.from("athlth_admin_account_audit").insert({
      actor_id: user.id, target_id: target,
      action: "deletion_review_requested", reason,
    });
    return reply({ requested: true, deleted: false });
  }

  // Reserve a traceable audit event before touching Supabase Auth.
  const { data: audit, error: auditError } = await admin
    .from("athlth_admin_account_audit")
    .insert({
      actor_id: user.id, target_id: target,
      action: action === "suspend" ? "suspend_requested" : "restore_requested",
      reason,
    }).select("id").single();
  if (auditError || !audit?.id) {
    return reply({ error: "Could not create security audit record" }, 503);
  }

  // Bans block new sign-ins and token refresh. Existing JWT access tokens may
  // remain valid until their expiry; don't claim instantaneous revocation.
  const { error: changeError } = await admin.auth.admin.updateUserById(
    target,
    { ban_duration: action === "suspend" ? "876000h" : "none" },
  );
  if (changeError) {
    await admin.from("athlth_admin_account_audit").update({
      action: "account_change_failed",
      metadata: { kind: action },
    }).eq("id", audit.id);
    return reply({ error: "Account status was not changed" }, 503);
  }
  await admin.from("athlth_admin_account_audit").update({
    action: action === "suspend" ? "account_suspended" : "account_restored",
  }).eq("id", audit.id);
  return reply({
    success: true,
    account_state: action === "suspend" ? "suspended" : "active",
  });
});
