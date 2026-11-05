# ATHLTH reusable Apple Distribution signing

## Why the old certificate appeared to expire after one build

The old TestFlight job created a **new** Distribution certificate and private
key on each run. GitHub's temporary keychain and the only copy of the private
key were deleted at the end of the job. The Apple certificate did **not**
expire: its matching private key was missing in the next job, forcing another
creation and eventually exhausting Apple's certificate quota.

## New implementation

1. The workflow restores `athlth-ci-signing-v1` from the last available
   GitHub Actions run. The artifact contains **only** a cryptographically
   authenticated AES-256-GCM envelope, never an unencrypted P12, private key or
   password.
2. A domain-separated HKDF-SHA256 key is derived from the existing
   `ASC_API_KEY_P8` repository secret. Thus no additional secret setup is
   required, but changing that API key invalidates old encrypted artifacts.
   For stronger separation, future hardening should introduce a distinct
   `ATHLTH_CI_SIGNING_WRAP_KEY` secret and migrate carefully.
3. The envelope decrypts only in `$RUNNER_TEMP` on the trusted signing
   runner. ATHLTH verifies that the P12 private key matches its certificate,
   and that the **exact certificate ID, X.509 fingerprint and type** match the
   current Apple Developer certificate. Identity must remain valid at least
   30 more days; otherwise the workflow **stops**, rather than silently
   revoking something.
4. The same P12 is imported into the temporary macOS keychain for each build.
   Only the four app-specific provisioning profiles are recreated. The keychain
   is removed after the job but the encrypted identity survives.
5. Immediately after successful signing setup, the encrypted artifact is
   re-uploaded. GitHub artifact retention is **90 days** or the repository's
   configured maximum. A run at least once within that period refreshes it.

A future bootstrap creates **one** new Apple Distribution certificate only
when no protected artifact exists. The currently known one-time recovery
still contains an exact, narrowly timestamp-verified previous CI certificate
ID. It must be adjusted to the actual latest orphaned CI certificate after
the ongoing legacy TestFlight job completes. **Never revoke arbitrary
Apple team certificates.**

## Operational controls

- Do not add `signing-envelope.json`, `*.p12`, `*.key`, key passwords,
  encrypted artifact archive or raw provisioning profiles to source control.
- GitHub workflow token needs `actions:read`, already set on the TestFlight
  job. Only push events on the explicitly selected release branch trigger the
  upload (in addition to an intentionally dispatched workflow).
- GitHub Actions artifact access should be limited to trusted repository
  workflows and administrators. If `ASC_API_KEY_P8` is replaced or exposed,
  old envelopes can no longer be restored safely, and the signing identity
  must be intentionally migrated or replaced.
- Automatic Apple certificate revocation remains disabled during cleanup.
- If the last encrypted artifact has expired, **stop** and perform a
  narrowly verified one-time rebootstrap. Do not iterate through certificates
  looking for one to revoke.
- Keep a separately secured backup of the signing identity for disaster
  recovery if the release cadence may exceed 90 days. This integration does
  not provide a permanent backup.
- Do not confuse signing success with Apple TestFlight acceptance. The main
  Build ATHLTH and backend quality gates still need to pass, and the final
  App Store Connect transport step must report success.

## Regression verification

`Verify reusable signing identity` runs offline shell syntax and Python
cryptography tests on signing-related changes. It proves P12
encrypt/decrypt roundtrip, Apple certificate verification, rejected tampering
and rejected API-key changes without touching real Apple signing resources.

The canonical release workflow is `.github/workflows/testflight.yml`.
