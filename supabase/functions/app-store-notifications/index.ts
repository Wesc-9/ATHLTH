import { Buffer } from "node:buffer";
import { withSupabase } from "npm:@supabase/server@1.7.0";
import {
  Environment,
  SignedDataVerifier,
  Status,
} from "npm:@apple/app-store-server-library@3.1.0";

const BUNDLE_ID = "com.wesc9.athlth";
const PRODUCT_IDS = new Set([
  "com.wesc9.athlth.paid.monthly",
  "com.wesc9.athlth.paid.yearly",
]);

const APPLE_ROOTS = [
  {
    url: "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
    sha256: "B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024",
  },
  {
    url: "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
    sha256: "C2B9B042DD57830E7D117DAC55AC8AE19407D38E41D88F3215BC3A890444A050",
  },
  {
    url: "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
    sha256: "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179",
  },
] as const;

let rootCertificatesPromise: Promise<Buffer[]> | undefined;

function hex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
}

async function loadAppleRootCertificates(): Promise<Buffer[]> {
  rootCertificatesPromise ??= Promise.all(
    APPLE_ROOTS.map(async ({ url, sha256 }) => {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error("Unable to load an Apple root certificate.");
      }

      const certificate = await response.arrayBuffer();
      const fingerprint = hex(await crypto.subtle.digest("SHA-256", certificate));

      if (fingerprint !== sha256) {
        throw new Error("Apple root certificate fingerprint mismatch.");
      }

      return Buffer.from(certificate);
    }),
  );

  return rootCertificatesPromise;
}

function normalizedUUID(value: string | undefined | null): string | null {
  return value?.trim().toLowerCase() || null;
}

function environmentName(value: string | undefined): "sandbox" | "production" | null {
  const normalized = value?.trim().toLowerCase();
  if (normalized === "sandbox") return "sandbox";
  if (normalized === "production") return "production";
  return null;
}

async function createVerifiers() {
  const roots = await loadAppleRootCertificates();
  const sandbox = new SignedDataVerifier(
    roots,
    true,
    Environment.SANDBOX,
    BUNDLE_ID,
  );

  const appAppleIdValue = Deno.env.get("APPLE_APP_ID");
  const appAppleId = appAppleIdValue ? Number(appAppleIdValue) : NaN;
  const production = Number.isSafeInteger(appAppleId) && appAppleId > 0
    ? new SignedDataVerifier(
        roots,
        true,
        Environment.PRODUCTION,
        BUNDLE_ID,
        appAppleId,
      )
    : null;

  return { sandbox, production };
}

async function verifyNotification(signedPayload: string) {
  const verifiers = await createVerifiers();

  try {
    return await verifiers.sandbox.verifyAndDecodeNotification(signedPayload);
  } catch (sandboxError) {
    if (!verifiers.production) throw sandboxError;
    return await verifiers.production.verifyAndDecodeNotification(signedPayload);
  }
}

async function verifyTransaction(signedTransactionInfo: string) {
  const verifiers = await createVerifiers();

  try {
    return await verifiers.sandbox.verifyAndDecodeTransaction(signedTransactionInfo);
  } catch (sandboxError) {
    if (!verifiers.production) throw sandboxError;
    return await verifiers.production.verifyAndDecodeTransaction(signedTransactionInfo);
  }
}

async function verifyRenewalInfo(signedRenewalInfo: string) {
  const verifiers = await createVerifiers();

  try {
    return await verifiers.sandbox.verifyAndDecodeRenewalInfo(signedRenewalInfo);
  } catch (sandboxError) {
    if (!verifiers.production) throw sandboxError;
    return await verifiers.production.verifyAndDecodeRenewalInfo(signedRenewalInfo);
  }
}

function subscriptionState(
  appleStatus: number | undefined,
  revoked: boolean,
  expiresAt: Date | null,
): "active" | "expired" | "revoked" {
  if (appleStatus === Status.REVOKED || revoked) return "revoked";

  if (
    appleStatus === Status.ACTIVE ||
    appleStatus === Status.BILLING_GRACE_PERIOD
  ) {
    return "active";
  }

  if (
    appleStatus === Status.EXPIRED ||
    appleStatus === Status.BILLING_RETRY
  ) {
    return "expired";
  }

  return expiresAt && expiresAt.getTime() > Date.now() ? "active" : "expired";
}

export default {
  fetch: withSupabase({ auth: "none" }, async (req, ctx) => {
    if (req.method !== "POST") {
      return Response.json({ error: "Method not allowed." }, { status: 405 });
    }

    let signedPayload: string | undefined;
    try {
      const body = await req.json();
      signedPayload = typeof body?.signedPayload === "string"
        ? body.signedPayload.trim()
        : undefined;
    } catch {
      return Response.json({ error: "Invalid JSON body." }, { status: 400 });
    }

    if (!signedPayload || signedPayload.length > 250_000) {
      return Response.json(
        { error: "Missing or invalid signedPayload." },
        { status: 400 },
      );
    }

    try {
      const notification = await verifyNotification(signedPayload);
      const transactionJWS = notification.data?.signedTransactionInfo;

      if (!transactionJWS) {
        return Response.json({
          received: true,
          notificationUUID: notification.notificationUUID ?? null,
          ignored: "Notification has no subscription transaction.",
        });
      }

      const transaction = await verifyTransaction(transactionJWS);

      if (
        !transaction.transactionId ||
        !transaction.originalTransactionId ||
        !transaction.productId ||
        transaction.bundleId !== BUNDLE_ID ||
        !PRODUCT_IDS.has(transaction.productId)
      ) {
        return Response.json({
          received: true,
          notificationUUID: notification.notificationUUID ?? null,
          ignored: "Notification is not for an ATHLTH+ subscription.",
        });
      }

      const userID = normalizedUUID(transaction.appAccountToken);
      if (!userID) {
        return Response.json({
          received: true,
          notificationUUID: notification.notificationUUID ?? null,
          ignored: "Transaction is not bound to an ATHLTH account.",
        });
      }

      let gracePeriodEndsAt: Date | null = null;
      if (notification.data?.signedRenewalInfo) {
        const renewal = await verifyRenewalInfo(
          notification.data.signedRenewalInfo,
        );
        if (renewal.gracePeriodExpiresDate) {
          gracePeriodEndsAt = new Date(renewal.gracePeriodExpiresDate);
        }
      }

      const transactionExpiresAt = transaction.expiresDate
        ? new Date(transaction.expiresDate)
        : null;

      const status = subscriptionState(
        notification.data?.status,
        transaction.revocationDate != null,
        transactionExpiresAt,
      );

      const periodEndsAt =
        notification.data?.status === Status.BILLING_GRACE_PERIOD &&
          gracePeriodEndsAt
        ? gracePeriodEndsAt
        : transactionExpiresAt;

      const environment = environmentName(transaction.environment);
      if (!environment) {
        throw new Error("Verified transaction has an unsupported environment.");
      }

      const signedAt = notification.signedDate
        ? new Date(notification.signedDate)
        : new Date();

      const { data: current, error: currentError } = await ctx.supabaseAdmin
        .from("subscription_entitlements")
        .select("last_verified_at")
        .eq("user_id", userID)
        .maybeSingle();

      if (currentError) {
        throw new Error("Unable to read current subscription entitlement.");
      }

      const lastVerifiedAt = current?.last_verified_at
        ? new Date(current.last_verified_at)
        : null;

      if (lastVerifiedAt && lastVerifiedAt.getTime() > signedAt.getTime()) {
        return Response.json({
          received: true,
          notificationUUID: notification.notificationUUID ?? null,
          ignored: "Older notification.",
        });
      }

      const { error: entitlementError } = await ctx.supabaseAdmin
        .from("subscription_entitlements")
        .update({
          tier: "athlth_plus",
          status,
          source: "app_store",
          app_store_product_id: transaction.productId,
          app_store_original_transaction_id: transaction.originalTransactionId,
          app_store_environment: environment,
          current_period_ends_at: periodEndsAt?.toISOString() ?? null,
          last_verified_at: signedAt.toISOString(),
        })
        .eq("user_id", userID);

      if (entitlementError) {
        throw new Error("Unable to update subscription entitlement.");
      }

      await ctx.supabaseAdmin
        .from("app_store_transaction_submissions")
        .update({
          status: "verified",
          processed_at: new Date().toISOString(),
          verification_error: null,
        })
        .eq("user_id", userID)
        .eq("transaction_id", transaction.transactionId);

      return Response.json({
        received: true,
        notificationUUID: notification.notificationUUID ?? null,
        notificationType: notification.notificationType ?? null,
        status,
      });
    } catch (error) {
      const message = error instanceof Error
        ? error.message || "App Store notification verification failed."
        : "App Store notification verification failed.";

      return Response.json({ error: message }, { status: 401 });
    }
  }),
};
