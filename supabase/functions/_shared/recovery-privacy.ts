// Only an explicit per-request confirmation can release health metrics
// to the external AI model. Insight and chat have different UI flows,
// but must share this non-negotiable transport rule.
export function canForwardRecoveryHealth(
  shareHealthData: boolean | undefined,
): boolean {
  return shareHealthData === true;
}

export function mustRejectUnconsentedInsight(
  mode: string | undefined,
  shareHealthData: boolean | undefined,
): boolean {
  return mode === "insight" && !canForwardRecoveryHealth(shareHealthData);
}

// Reject every request that attempts to use continuous Coach sharing.
// Client consent alone is insufficient: release requires reviewed legal
// documentation and a separate server-side authorization implementation.
export function mustRejectUnreleasedAutomaticCoachSharing(
  mode: string | undefined,
  healthSharingMode: string | undefined,
): boolean {
  return mode === "ask" && healthSharingMode === "automatic";
}
