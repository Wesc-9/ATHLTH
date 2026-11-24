# Private Garmin surfaces

The opt-in owner-only build shares a single, account-bound, in-memory Garmin
preview between Settings, Home, Insights and a private history destination.
The cache is cleared and in-flight work cancelled on background/sign-out/account
switch or disconnect. Keychain credentials are device-only and account scoped.
Only the active signed-in account can display the preview. The cache does not
feed HealthKitManager, ordinary training totals, AI readiness, export, backup,
competition, social or any backend. History shows possible matches to existing
records, never silently merges or deletes. No new commercial scopes or claims.

Automatic refresh uses a five-minute attempt cooldown and only runs in the
foreground with an explicitly connected key. Missing/stale measurements are
shown as unavailable; overnight Garmin HRV is not combined with HealthKit SDNN.
Normal builds retain the existing Coming Soon behavior.

Remaining: verify response fields and compile the opt-in build, test a real
account/device, confirm commercial processing terms, implement approved OAuth,
account-scoped durable import, actual per-metric source priority and safe
cross-source identity reconciliation before merging core readiness and history.

A separate compile-only GitHub workflow checks the opt-in code with no Garmin
keys, no authenticated account, no signing, and no distributed binary.
