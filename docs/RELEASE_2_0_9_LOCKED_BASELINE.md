# ATHLTH 2.0.9 — locked baseline

- Release branch: `release/v2.0.9` (leave unchanged)
- Frozen source snapshot branch: `locked/v2.0.9`
- Verified TestFlight workflow source commit: `1505c07743d54f930d4342d44ade6e81437d435b`
- Marketing version: `2.0.9`
- Build: `117`
- TestFlight workflow: https://github.com/Wesc-9/ATHLTH/actions/runs/41644705904 (success, 2026-11-03)
- Next active development branch: `release/v2.1.0`
- Next marketing version / build: `2.1.0 (118)`

The code for 2.0.9 should not be changed after this checkpoint.
Continue all new implementation exclusively on `release/v2.1.0`. This
document and the frozen branch are release bookkeeping, not an enforced
GitHub branch-protection rule.

Do not upload 2.1.0 to TestFlight until expressly requested. The upload
workflow is restricted to the explicit `.github/testflight-trigger` path
for push-triggered uploads.
