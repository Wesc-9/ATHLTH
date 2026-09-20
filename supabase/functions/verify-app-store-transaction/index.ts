import { Buffer } from "node:buffer";
import { withSupabase } from "npm:@supabase/server@1.7.0";
import {
  Environment,
  SignedDataVerifier,
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

type VerificationRequest = {
  transactionID?: string;
  originalTransactionID?: string;
  productID?: string;
  appAccountToken?: string | null;
  signedTransactionInfo?: string;
};

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

async function verifySignedTransaction(signedTransactionInfo: string) {
  const roots = await loadAppleRootCertificates();

  const sandboxVerifier = new SignedDataVerifier(
    roots,
    true,
    Environment.SANDBOX,
    BUNDLE_ID,
  );

  try {
    return await sandboxVerifier.verifyAndDecodeTransaction(signedTransactionInfo);
  } catch (sandboxError) {
    const appAppleIdValue = Deno.env.get("APPLE_APP_ID");
    const appAppleId = appAppleIdValue ? Number(appAppleIdValue) : NaN;

    if (!Number.isSafeInteger(appAppleId) || appAppleId <= 0) {
      throw sandboxError;
    }

    const productionVerifier = new SignedDataVerifier(
      roots,
      true,
      Environment.PRODUCTION,
      BUNDLE_ID,
      appAppleId,
    );

    return await productionVerifier.verifyAndDecodeTransaction(
      signedTransactionInfo,
    );
  }
}

async function markRejected(
  supabaseAdmin: any,
  userID: string,
  transactionID: string | undefined,
  reason: string,
) {
  if (!transactionID) return;

  await supabaseAdmin
    .from("app_store_transaction_submissions")
    .update({
      status: "rejected",
      processed_at: new Date().toISOString(),
      verification_error: reason.slice(0, 500),
    })
    .eq("user_id", userID)
    .eq("transaction_id", transactionID);
}

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    if (req.method !== "POST") {
      return Response.json({ error: "Method not allowed." }, { status: 405 });
    }

    const userID = ctx.userClaims?.sub;
    if (!userID) {
      return Response.json({ error: "Missing authenticated user." }, { status: 401 });
    }

    let body: VerificationRequest;
    try {
      body = await req.json();
    } catch {
      return Response.json({ error: "Invalid JSON body." }, { status: 400 });
    }

    const signedTransactionInfo = body.signedTransactionInfo?.trim();
    if (!signedTransactionInfo || signedTransactionInfo.length > 100_000) {
      return Response.json(
        { error: "Missing or invalid signed transaction." },
        { status: 400 },
      );
    }

    try {
      const transaction = await verifySignedTransaction(signedTransactionInfo);

      if (
        !transaction.transactionId ||
        !transaction.originalTransactionId ||
        !transaction.productId
      ) {
        throw new Error("Verified transaction is missing required identifiers.");
      }

      if (!PRODUCT_IDS.has(transaction.productId)) {
        throw new Error("Verified transaction is not an ATHLTH+ product.");
      }

      if (transaction.bundleId !== BUNDLE_ID) {
        throw new Error("Verified transaction belongs to another app.");
      }

      const verifiedUserID = normalizedUUID(transaction.appAccountToken);
      if (verifiedUserID !== normalizedUUID(userID)) {
        throw new Error("App Store transaction is not bound to this ATHLTH account.");
      }

      if (
        body.transactionID &&
        body.transactionID !== transaction.transactionId
      ) {
        throw new Error("Transaction identifier does not match the signed payload.");
      }

      if (
        body.originalTransactionID &&
        body.originalTransactionID !== transaction.originalTransactionId
      ) {
        throw new Error("Original transaction identifier does not match the signed payload.");
      }

      if (body.productID && body.productID !== transaction.productId) {
        throw new Error("Product identifier does not match the signed payload.");
      }

      if (
        body.appAccountToken &&
        normalizedUUID(body.appAccountToken) !== verifiedUserID
      ) {
        throw new Error("Account token does not match the signed payload.");
      }

      const expiresAt = transaction.expiresDate
        ? new Date(transaction.expiresDate)
        : null;
      const revoked = transaction.revocationDate != null;
      const expired = expiresAt != null && expiresAt.getTime() <= Date.now();
      const status = revoked ? "revoked" : expired ? "expired" : "active";
      const environment = environmentName(transaction.environment);

      if (!environment) {
        throw new Error("Verified transaction has an unsupported App Store environment.");
      }

      const signedAt = transaction.signedDate
        ? new Date(transaction.signedDate)
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

      if (!lastVerifiedAt || lastVerifiedAt.getTime() <= signedAt.getTime()) {
        const entitlementUpdate = {
          tier: "athlth_plus",
          status,
          source: "app_store",
          app_store_product_id: transaction.productId,
          app_store_original_transaction_id: transaction.originalTransactionId,
          app_store_environment: environment,
          current_period_ends_at: expiresAt?.toISOString() ?? null,
          last_verified_at: signedAt.toISOString(),
        };

        const { error: entitlementError } = await ctx.supabaseAdmin
          .from("subscription_entitlements")
          .update(entitlementUpdate)
          .eq("user_id", userID);

        if (entitlementError) {
          throw new Error("Unable to persist verified entitlement.");
        }
      }

      const { error: submissionError } = await ctx.supabaseAdmin
        .from("app_store_transaction_submissions")
        .update({
          status: "verified",
          processed_at: new Date().toISOString(),
          verification_error: null,
        })
        .eq("user_id", userID)
        .eq("transaction_id", transaction.transactionId);

      if (submissionError) {
        throw new Error("Unable to finalize transaction verification.");
      }

      return Response.json({
        verified: true,
        status,
        productID: transaction.productId,
        currentPeriodEndsAt: expiresAt?.toISOString() ?? null,
        environment,
      });
    } catch (error) {
      const message = error instanceof Error
        ? error.message || "App Store transaction verification failed."
        : "App Store transaction verification failed.";

      await markRejected(
        ctx.supabaseAdmin,
        userID,
        body.transactionID,
        message,
      );

      return Response.json(
        { verified: false, error: message },
        { status: 422 },
      );
    }
  }),
};
