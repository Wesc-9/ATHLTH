import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type Operation =
  | "load"
  | "sync_achievements"
  | "claim_prestige"
  | "save_cabinet";

type AchievementUnlock = {
  stage_key?: string;
  award_id?: string;
  award_class?: string;
  stage_title?: string;
  title?: string;
  rarity?: string;
  category?: string;
  verification_source?: string;
  system_image?: string;
  unlocked_at?: string;
};

type PrestigeEvidence = {
  workout_id?: string;
  activity_type?: string;
  distance_meters?: number;
  duration_seconds?: number;
  started_at?: string;
  ended_at?: string;
  source_bundle_identifier?: string;
  source_name?: string;
  is_indoor?: boolean | null;
  was_user_entered?: boolean;
};

type TrophyStateRequest = {
  operation?: Operation;
  username?: string | null;
  unlocks?: AchievementUnlock[] | null;
  trophy_id?: string | null;
  evidence?: PrestigeEvidence | null;
  showcase_ids?: string[] | null;
};

const PRESTIGE = {
  "signature.half-marathon": {
    title: "Half Marathon",
    threshold: 21_097.5,
    icon: "figure.run",
  },
  "signature.marathon": {
    title: "Marathon",
    threshold: 42_195,
    icon: "flag.checkered",
  },
} as const;

const ACHIEVEMENT_IDS = new Set([
  "consistency.workout-momentum",
  "walking.total-distance",
  "walking.sessions",
  "endurance.running-distance",
  "consistency.training-streak",
  "strength.sessions",
  "strength.total-volume",
  "recovery.restored-nights",
  "goals.completed",
  "challenges.participation",
  "challenges.wins",
  "challenges.friends-invited",
  "signature.first-5k",
  "signature.first-10k",
  "signature.walk-5k",
  "signature.walk-10k",
  "signature.first-strength-log",
  "signature.route-rival",
  "signature.strength-rival",
]);

const RARITIES = new Set([
  "core",
  "rare",
  "epic",
  "signature",
]);

const CATEGORIES = new Set([
  "signature",
  "walking",
  "endurance",
  "strength",
  "consistency",
  "goals",
  "recovery",
  "challenges",
]);

const VERIFICATION_SOURCES = new Set([
  "appleHealth",
  "athlth",
  "goal",
  "challenge",
  "mixed",
]);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const json = (
  body: Record<string, unknown>,
  status = 200,
) =>
  new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        "Content-Type":
          "application/json",
        "Cache-Control":
          "no-store",
      },
    },
  );

const clean = (
  value: unknown,
  max: number,
) =>
  String(value ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);

const isAchievementID = (
  value: string,
) =>
  ACHIEVEMENT_IDS.has(value) ||
  value.startsWith(
    "goal.journey.",
  );

const rarityRank = (
  rarity: string,
) => {
  switch (
    rarity.toLowerCase()
  ) {
    case "signature":
      return 3;
    case "epic":
      return 2;
    case "rare":
      return 1;
    default:
      return 0;
  }
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
      Deno.env.get(
        "SUPABASE_URL",
      );
    const serviceRoleKey =
      Deno.env.get(
        "SUPABASE_SERVICE_ROLE_KEY",
      );

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

    const token =
      authorization
        .slice(7)
        .trim();

    const admin =
      createClient(
        supabaseURL,
        serviceRoleKey,
        {
          auth: {
            autoRefreshToken:
              false,
            persistSession:
              false,
          },
        },
      );

    const {
      data: { user },
      error: authError,
    } =
      await admin.auth.getUser(
        token,
      );

    if (
      authError ||
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

    let body:
      TrophyStateRequest;

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

    const operation =
      body.operation;

    if (!operation) {
      return json(
        {
          error:
            "Missing operation.",
        },
        400,
      );
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

    const usernameAtUnlock =
      clean(
        profile?.username ||
          profile
            ?.display_name ||
          "ATHLTH ATHLETE",
        24,
      );

    if (operation === "load") {
      const [
        unlockResult,
        preferenceResult,
        legacyShowcaseResult,
      ] =
        await Promise.all([
          admin
            .from(
              "athlth_award_unlocks",
            )
            .select(
              "stage_key,award_id,award_class,stage_title,title,rarity,category,verification_source,system_image,unlocked_at,username_at_unlock,engraving_achievement,engraving_text,engraving_generated_at,engraving_version",
            )
            .eq(
              "user_id",
              user.id,
            )
            .order(
              "unlocked_at",
              {
                ascending:
                  true,
              },
            ),
          admin
            .from(
              "user_award_preferences",
            )
            .select(
              "showcase_ids,updated_at",
            )
            .eq(
              "user_id",
              user.id,
            )
            .maybeSingle(),
          admin
            .from(
              "social_trophy_showcases",
            )
            .select(
              "items,updated_at",
            )
            .eq(
              "user_id",
              user.id,
            )
            .maybeSingle(),
        ]);

      if (
        unlockResult.error
      ) {
        return json(
          {
            error:
              unlockResult
                .error
                .message,
          },
          500,
        );
      }

      if (
        preferenceResult.error
      ) {
        return json(
          {
            error:
              preferenceResult
                .error
                .message,
          },
          500,
        );
      }

      if (
        legacyShowcaseResult.error
      ) {
        return json(
          {
            error:
              legacyShowcaseResult
                .error
                .message,
          },
          500,
        );
      }

      const legacyItems =
        Array.isArray(
          legacyShowcaseResult
            .data
            ?.items,
        )
          ? legacyShowcaseResult
              .data
              .items
          : [];
      const legacyIDs =
        legacyItems
          .map(
            (item: any) =>
              clean(
                item?.trophy_id,
                160,
              ),
          )
          .filter(Boolean)
          .slice(0, 4);

      const hasPreferences =
        Boolean(
          preferenceResult.data,
        );

      return json({
        unlocks:
          unlockResult.data ??
          [],
        showcase_ids:
          hasPreferences
            ? preferenceResult
                .data
                ?.showcase_ids ??
              []
            : legacyIDs,
        cabinet_updated_at:
          hasPreferences
            ? preferenceResult
                .data
                ?.updated_at ??
              null
            : legacyShowcaseResult
                .data
                ?.updated_at ??
              null,
      });
    }

    if (
      operation ===
      "sync_achievements"
    ) {
      const unlocks =
        Array.isArray(
          body.unlocks,
        )
          ? body.unlocks
              .slice(0, 160)
          : [];

      const rows = [];

      for (
        const unlock
        of unlocks
      ) {
        const stageKey =
          clean(
            unlock.stage_key,
            180,
          );
        const awardID =
          clean(
            unlock.award_id,
            160,
          );
        const stageTitle =
          clean(
            unlock.stage_title,
            100,
          );
        const title =
          clean(
            unlock.title,
            160,
          );
        const rarity =
          clean(
            unlock.rarity,
            24,
          )
          .toLowerCase();
        const category =
          clean(
            unlock.category,
            40,
          );
        const verificationSource =
          clean(
            unlock
              .verification_source,
            40,
          );
        const systemImage =
          clean(
            unlock
              .system_image,
            100,
          ) ||
          "medal.fill";
        const unlockedAt =
          new Date(
            String(
              unlock
                .unlocked_at ??
              "",
            ),
          );

        if (
          !stageKey ||
          !isAchievementID(
            awardID,
          ) ||
          awardID in
            PRESTIGE ||
          unlock.award_class !==
            "achievement" ||
          !stageTitle ||
          !title ||
          !RARITIES.has(
            rarity,
          ) ||
          !CATEGORIES.has(
            category,
          ) ||
          !VERIFICATION_SOURCES.has(
            verificationSource,
          ) ||
          Number.isNaN(
            unlockedAt
              .getTime(),
          )
        ) {
          continue;
        }

        rows.push({
          user_id: user.id,
          stage_key:
            stageKey,
          award_id: awardID,
          award_class:
            "achievement",
          stage_title:
            stageTitle,
          title,
          rarity,
          category,
          verification_source:
            verificationSource,
          system_image:
            systemImage,
          unlocked_at:
            unlockedAt
              .toISOString(),
          evidence: {},
          username_at_unlock:
            usernameAtUnlock,
        });
      }

      if (rows.length > 0) {
        const { error } =
          await admin
            .from(
              "athlth_award_unlocks",
            )
            .upsert(
              rows,
              {
                onConflict:
                  "user_id,stage_key",
                ignoreDuplicates:
                  true,
              },
            );

        if (error) {
          return json(
            {
              error:
                error.message,
            },
            500,
          );
        }
      }

      return json({
        unlocks: [],
      });
    }

    if (
      operation ===
      "claim_prestige"
    ) {
      const trophyID =
        clean(
          body.trophy_id,
          160,
        );
      const definition =
        PRESTIGE[
          trophyID as
            keyof typeof PRESTIGE
        ];
      const evidence =
        body.evidence;

      if (
        !definition ||
        !evidence
      ) {
        return json(
          {
            error:
              "This trophy is not claimable.",
          },
          400,
        );
      }

      const workoutID =
        clean(
          evidence.workout_id,
          64,
        );
      const sourceBundle =
        clean(
          evidence
            .source_bundle_identifier,
          180,
        );
      const sourceName =
        clean(
          evidence
            .source_name,
          120,
        );
      const distance =
        Number(
          evidence
            .distance_meters,
        );
      const duration =
        Number(
          evidence
            .duration_seconds,
        );
      const startedAt =
        new Date(
          String(
            evidence
              .started_at ??
            "",
          ),
        );
      const endedAt =
        new Date(
          String(
            evidence
              .ended_at ??
            "",
          ),
        );

      if (
        evidence.activity_type !==
          "running" ||
        !UUID_PATTERN.test(
          workoutID,
        ) ||
        !sourceBundle ||
        evidence
          .was_user_entered !==
          false ||
        !Number.isFinite(
          distance,
        ) ||
        distance <
          definition
            .threshold ||
        !Number.isFinite(
          duration,
        ) ||
        duration <= 0 ||
        Number.isNaN(
          startedAt
            .getTime(),
        ) ||
        Number.isNaN(
          endedAt
            .getTime(),
        ) ||
        endedAt <=
          startedAt ||
        Math.abs(
          (
            endedAt.getTime() -
            startedAt.getTime()
          ) /
            1000 -
          duration,
        ) > 600
      ) {
        return json(
          {
            error:
              "The workout does not meet ATHLTH trophy verification rules.",
          },
          400,
        );
      }

      const stageKey =
        `${trophyID}.unlocked`;
      const row = {
        user_id: user.id,
        stage_key:
          stageKey,
        award_id:
          trophyID,
        award_class:
          "trophy",
        stage_title:
          "Signature",
        title:
          definition.title,
        rarity:
          "signature",
        category:
          "signature",
        verification_source:
          "appleHealth",
        system_image:
          definition.icon,
        unlocked_at:
          endedAt
            .toISOString(),
        evidence: {
          workout_id:
            workoutID,
          activity_type:
            "running",
          distance_meters:
            distance,
          duration_seconds:
            duration,
          started_at:
            startedAt
              .toISOString(),
          ended_at:
            endedAt
              .toISOString(),
          source_bundle_identifier:
            sourceBundle,
          source_name:
            sourceName,
          is_indoor:
            evidence
              .is_indoor ??
            null,
          was_user_entered:
            false,
        },
        username_at_unlock:
          usernameAtUnlock,
      };

      const { error } =
        await admin
          .from(
            "athlth_award_unlocks",
          )
          .upsert(
            row,
            {
              onConflict:
                "user_id,stage_key",
              ignoreDuplicates:
                true,
            },
          );

      if (error) {
        return json(
          {
            error:
              error.message,
          },
          500,
        );
      }

      const {
        data: persisted,
        error:
          persistedError,
      } =
        await admin
          .from(
            "athlth_award_unlocks",
          )
          .select(
            "stage_key,award_id,award_class,stage_title,title,rarity,category,verification_source,system_image,unlocked_at",
          )
          .eq(
            "user_id",
            user.id,
          )
          .eq(
            "stage_key",
            stageKey,
          )
          .single();

      if (persistedError) {
        return json(
          {
            error:
              persistedError
                .message,
          },
          500,
        );
      }

      return json({
        unlock:
          persisted,
      });
    }

    if (
      operation ===
      "save_cabinet"
    ) {
      const incoming =
        Array.isArray(
          body.showcase_ids,
        )
          ? body
              .showcase_ids
              .map(
                (value) =>
                  clean(
                    value,
                    160,
                  ),
              )
              .filter(
                Boolean,
              )
          : [];
      const showcaseIDs =
        [...new Set(incoming)]
          .slice(0, 4);

      let selectedRows:
        any[] = [];

      if (
        showcaseIDs.length >
        0
      ) {
        const {
          data,
          error,
        } =
          await admin
            .from(
              "athlth_award_unlocks",
            )
            .select(
              "award_id,title,stage_title,rarity,category,system_image,unlocked_at",
            )
            .eq(
              "user_id",
              user.id,
            )
            .in(
              "award_id",
              showcaseIDs,
            );

        if (error) {
          return json(
            {
              error:
                error.message,
            },
            500,
          );
        }

        const best =
          new Map<
            string,
            any
          >();

        for (
          const row
          of data ?? []
        ) {
          const current =
            best.get(
              row.award_id,
            );

          if (
            !current ||
            rarityRank(
              row.rarity,
            ) >
              rarityRank(
                current.rarity,
              ) ||
            (
              rarityRank(
                row.rarity,
              ) ===
                rarityRank(
                  current.rarity,
                ) &&
              new Date(
                row.unlocked_at,
              ) >
                new Date(
                  current
                    .unlocked_at,
                )
            )
          ) {
            best.set(
              row.award_id,
              row,
            );
          }
        }

        if (
          showcaseIDs.some(
            (id) =>
              !best.has(id),
          )
        ) {
          return json(
            {
              error:
                "The cabinet can only contain awards you have unlocked.",
            },
            400,
          );
        }

        selectedRows =
          showcaseIDs.map(
            (id) =>
              best.get(id),
          );
      }

      const updatedAt =
        new Date()
          .toISOString();

      const {
        error:
          preferenceError,
      } =
        await admin
          .from(
            "user_award_preferences",
          )
          .upsert({
            user_id: user.id,
            showcase_ids:
              showcaseIDs,
            updated_at:
              updatedAt,
          });

      if (
        preferenceError
      ) {
        return json(
          {
            error:
              preferenceError
                .message,
          },
          500,
        );
      }

      const socialItems =
        selectedRows.map(
          (row) => ({
            trophy_id:
              row.award_id,
            title:
              row.title,
            stage_label:
              row.stage_title,
            rarity:
              String(
                row.rarity ??
                  "",
              ),
            category:
              String(
                row.category ??
                  "",
              ),
            system_image:
              row.system_image,
            unlocked_at:
              row.unlocked_at,
          }),
        );

      const {
        error:
          socialError,
      } =
        await admin
          .from(
            "social_trophy_showcases",
          )
          .upsert({
            user_id: user.id,
            items:
              socialItems,
            updated_at:
              updatedAt,
          });

      if (socialError) {
        return json(
          {
            error:
              socialError
                .message,
          },
          500,
        );
      }

      return json({
        showcase_ids:
          showcaseIDs,
        cabinet_updated_at:
          updatedAt,
      });
    }

    return json(
      {
        error:
          "Unsupported operation.",
      },
      400,
    );
  },
);
