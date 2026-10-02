import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type TrophyRequest = {
  trophyID?: string;
  username?: string;
  achievementTitle?: string;
  achievementDetail?: string;
  unlockedAt?: string | null;
  language?: "en" | "nb";
};

const TROPHY_FACTS = {
  "signature.half-marathon": {
    detail:
      "A verified single running workout of at least 21.0975 kilometres.",
  },
  "signature.long-run-30k": {
    detail:
      "A verified single running workout of at least 30 kilometres.",
  },
  "signature.marathon": {
    detail:
      "A verified single running workout of at least 42.195 kilometres.",
  },
  "signature.ultra-50k": {
    detail:
      "A verified single running workout of at least 50 kilometres.",
  },
} as const;

const ALLOWED_TROPHIES = new Set(
  Object.keys(TROPHY_FACTS),
);

const ENGRAVING_VERSION = 1;

const json = (
  body: Record<string, unknown>,
  status = 200,
) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

async function recordGroqQuota(
  response: Response,
  feature: string,
) {
  try {
    const supabaseURL =
      Deno.env.get("SUPABASE_URL");
    const serviceRoleKey =
      Deno.env.get(
        "SUPABASE_SERVICE_ROLE_KEY",
      );

    if (!supabaseURL || !serviceRoleKey) {
      return;
    }

    const parseHeader = (
      name: string,
    ) => {
      const raw =
        response.headers.get(name);
      if (!raw) return null;

      const value = Number(raw);
      return Number.isFinite(value)
        ? Math.max(
            0,
            Math.round(value),
          )
        : null;
    };

    const limitRequests =
      parseHeader(
        "x-ratelimit-limit-requests",
      );
    const remainingRequests =
      parseHeader(
        "x-ratelimit-remaining-requests",
      );
    const resetRequests =
      response.headers.get(
        "x-ratelimit-reset-requests",
      );

    if (
      limitRequests == null &&
      remainingRequests == null
    ) {
      return;
    }

    const admin = createClient(
      supabaseURL,
      serviceRoleKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    const model =
      Deno.env.get(
        "GROQ_TRAINING_MODEL",
      ) ??
      "openai/gpt-oss-120b";

    const { error } =
      await admin
        .from(
          "ai_provider_quota_snapshots",
        )
        .upsert(
          {
            provider: "groq",
            model,
            limit_requests:
              limitRequests,
            remaining_requests:
              remainingRequests,
            reset_requests:
              resetRequests,
            last_feature: feature,
            updated_at:
              new Date()
                .toISOString(),
          },
          {
            onConflict:
              "provider,model",
          },
        );

    if (error) {
      console.error(
        "Unable to record AI quota",
        {
          feature,
          message: error.message,
        },
      );
    }
  } catch (error) {
    console.error(
      "AI quota telemetry skipped",
      {
        feature,
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );
  }
}

function extractOutputText(
  payload: any,
): string | null {
  if (
    typeof payload?.output_text ===
    "string"
  ) {
    return payload.output_text;
  }

  for (
    const item of payload?.output ?? []
  ) {
    for (
      const content of
        item?.content ?? []
    ) {
      if (
        content?.type ===
          "output_text" &&
        typeof content?.text ===
          "string"
      ) {
        return content.text;
      }
    }
  }

  return null;
}

function cleanText(
  value: unknown,
  maximum: number,
) {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maximum);
}

const schema = {
  type: "object",
  additionalProperties: false,
  required: [
    "athlete",
    "achievement",
    "inscription",
  ],
  properties: {
    athlete: {
      type: "string",
    },
    achievement: {
      type: "string",
    },
    inscription: {
      type: "string",
    },
  },
};

Deno.serve(
  async (req: Request) => {
    if (req.method !== "POST") {
      return json(
        {
          error:
            "Method not allowed.",
        },
        405,
      );
    }

    const authorization =
      req.headers.get(
        "Authorization",
      );

    if (
      !authorization?.startsWith(
        "Bearer ",
      )
    ) {
      return json(
        {
          error:
            "Missing authenticated user.",
        },
        401,
      );
    }

    const supabaseURL =
      Deno.env.get("SUPABASE_URL");
    const serviceRoleKey =
      Deno.env.get(
        "SUPABASE_SERVICE_ROLE_KEY",
      );
    const groqKey =
      Deno.env.get("GROQ_API_KEY");

    if (
      !supabaseURL ||
      !serviceRoleKey
    ) {
      return json(
        {
          error:
            "ATHLTH backend is unavailable.",
        },
        503,
      );
    }

    if (!groqKey) {
      return json(
        {
          error:
            "ATHLTH AI is not configured yet.",
          code:
            "AI_NOT_CONFIGURED",
        },
        503,
      );
    }

    const token =
      authorization
        .slice(7)
        .trim();

    const admin = createClient(
      supabaseURL,
      serviceRoleKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    const {
      data: { user },
      error: userError,
    } =
      await admin.auth.getUser(
        token,
      );

    if (
      userError ||
      !user
    ) {
      return json(
        {
          error:
            "Your sign-in session is no longer valid.",
        },
        401,
      );
    }

    let body: TrophyRequest;

    try {
      body = await req.json();
    } catch {
      return json(
        {
          error:
            "Invalid request body.",
        },
        400,
      );
    }

    const trophyID =
      cleanText(
        body.trophyID,
        80,
      );

    if (
      !ALLOWED_TROPHIES.has(
        trophyID,
      )
    ) {
      return json(
        {
          error:
            "This achievement is not eligible for a gold trophy.",
        },
        400,
      );
    }

    const {
      data: award,
      error: awardError,
    } =
      await admin
        .from(
          "athlth_award_unlocks",
        )
        .select(
          "stage_key,title,unlocked_at,username_at_unlock,engraving_achievement,engraving_text,engraving_generated_at,engraving_version",
        )
        .eq(
          "user_id",
          user.id,
        )
        .eq(
          "award_id",
          trophyID,
        )
        .eq(
          "award_class",
          "trophy",
        )
        .order(
          "unlocked_at",
          {
            ascending: true,
          },
        )
        .limit(1)
        .maybeSingle();

    if (
      awardError ||
      !award
    ) {
      return json(
        {
          error:
            "This trophy has not been verified for the signed-in athlete.",
        },
        409,
      );
    }

    if (
      award.engraving_achievement &&
      award.engraving_text
    ) {
      return json({
        athlete:
          cleanText(
            award.username_at_unlock,
            24,
          ) ||
          "ATHLTH ATHLETE",
        achievement:
          cleanText(
            award.engraving_achievement,
            28,
          ),
        inscription:
          cleanText(
            award.engraving_text,
            48,
          ),
      });
    }

    const {
      data: profile,
    } =
      await admin
        .from("profiles")
        .select(
          "username,display_name",
        )
        .eq("id", user.id)
        .maybeSingle();

    const username =
      cleanText(
        award.username_at_unlock ||
          profile?.username ||
          profile?.display_name ||
          body.username ||
          "ATHLTH ATHLETE",
        24,
      );
    const achievementTitle =
      cleanText(
        award.title ||
          body.achievementTitle,
        80,
      );
    const achievementDetail =
      TROPHY_FACTS[
        trophyID as
          keyof typeof TROPHY_FACTS
      ]?.detail ??
      "";
    const unlockedAt =
      cleanText(
        award.unlocked_at ||
          body.unlockedAt,
        64,
      );
    const language =
      body.language === "nb"
        ? "Norwegian Bokmål"
        : "English";

    const instructions = `
You write the engraving for a premium gold ATHLTH sports trophy.

Return exactly three short fields:
- athlete: the supplied username exactly as written.
- achievement: a factual trophy label, max 28 characters.
- inscription: an understated achievement line, max 48 characters.

Rules:
- Write achievement and inscription in ${language}.
- Never invent a distance, time, ranking, date, record or fact.
- Base the wording only on the supplied achievement title and detail.
- No emojis, hashtags, exclamation marks or motivational clichés.
- Keep it elegant enough to engrave on a physical trophy.
- The inscription should feel earned and specific, not generic.
- Do not change or decorate the username.
`.trim();

    const aiResponse =
      await fetch(
        "https://api.groq.com/openai/v1/responses",
        {
          method: "POST",
          headers: {
            "Authorization":
              `Bearer ${groqKey}`,
            "Content-Type":
              "application/json",
          },
          body: JSON.stringify({
            model:
              Deno.env.get(
                "GROQ_TRAINING_MODEL",
              ) ??
              "openai/gpt-oss-120b",
            reasoning: {
              effort: "low",
            },
            instructions,
            input: JSON.stringify({
              trophyID,
              username,
              achievementTitle,
              achievementDetail,
              unlockedAt:
                unlockedAt ||
                null,
            }),
            text: {
              format: {
                type:
                  "json_schema",
                name:
                  "athlth_trophy_inscription",
                strict: true,
                schema,
              },
            },
          }),
        },
      );

    await recordGroqQuota(
      aiResponse,
      "trophy-inscription",
    );

    if (!aiResponse.ok) {
      const failure =
        await aiResponse.text();

      console.error(
        "Trophy inscription generation failed",
        {
          userID: user.id,
          status:
            aiResponse.status,
          body:
            failure.slice(
              0,
              1200,
            ),
        },
      );

      return json(
        {
          error:
            "Trophy engraving is temporarily unavailable.",
        },
        502,
      );
    }

    const payload =
      await aiResponse.json();
    const outputText =
      extractOutputText(payload);

    if (!outputText) {
      return json(
        {
          error:
            "ATHLTH AI returned an empty engraving.",
        },
        502,
      );
    }

    try {
      const result =
        JSON.parse(
          outputText,
        );

      const achievement =
        cleanText(
          result.achievement,
          28,
        );
      const inscription =
        cleanText(
          result.inscription,
          48,
        );

      if (
        !achievement ||
        !inscription
      ) {
        throw new Error(
          "Empty engraving field.",
        );
      }

      const generatedAt =
        new Date()
          .toISOString();

      const {
        error: persistError,
      } =
        await admin
          .from(
            "athlth_award_unlocks",
          )
          .update({
            engraving_achievement:
              achievement,
            engraving_text:
              inscription,
            engraving_generated_at:
              generatedAt,
            engraving_version:
              ENGRAVING_VERSION,
          })
          .eq(
            "user_id",
            user.id,
          )
          .eq(
            "stage_key",
            award.stage_key,
          );

      if (persistError) {
        console.error(
          "Unable to persist trophy engraving",
          {
            userID: user.id,
            trophyID,
            message:
              persistError.message,
          },
        );

        return json(
          {
            error:
              "Trophy engraving could not be saved.",
          },
          502,
        );
      }

      return json({
        athlete: username,
        achievement,
        inscription,
      });
    } catch (error) {
      console.error(
        "Unable to parse trophy engraving",
        {
          userID: user.id,
          message:
            error instanceof Error
              ? error.message
              : String(error),
          output:
            outputText.slice(
              0,
              1200,
            ),
        },
      );

      return json(
        {
          error:
            "ATHLTH AI returned an invalid engraving.",
        },
        502,
      );
    }
  },
);
