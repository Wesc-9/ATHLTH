import { withSupabase } from "npm:@supabase/server@1.7.0";

type DeleteAccountRequest = {
  confirm?: boolean;
};

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    if (req.method !== "POST") {
      return Response.json({ error: "Method not allowed." }, { status: 405 });
    }

    const userID = ctx.userClaims?.sub;
    if (!userID) {
      return Response.json({ error: "Missing authenticated user." }, { status: 401 });
    }

    let body: DeleteAccountRequest;
    try {
      body = await req.json();
    } catch {
      return Response.json({ error: "Invalid request body." }, { status: 400 });
    }

    if (body.confirm !== true) {
      return Response.json(
        { error: "Account deletion was not confirmed." },
        { status: 400 },
      );
    }

    const { error } = await ctx.supabaseAdmin.auth.admin.deleteUser(userID);

    if (error) {
      console.error("ATHLTH account deletion failed", {
        userID,
        message: error.message,
      });

      return Response.json(
        { error: "Unable to delete the ATHLTH account." },
        { status: 500 },
      );
    }

    return Response.json({ deleted: true });
  }),
};
