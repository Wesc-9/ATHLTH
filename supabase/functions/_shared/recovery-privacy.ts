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
