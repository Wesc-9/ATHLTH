# Garmin Connect integration — phase 1

Status: development only. No production access, OAuth credentials, live requests, database changes or third-party transfers.

## Existing architecture
- `WearableDataSource` and `WearableWorkoutRecord` are the shared contract.
- `GarminImportNormalizer` maps an internal staging schema into that contract. It is not a decoder for an unverified Garmin response. Preserve original sport type and device model; do not classify unknown sports as runs.
- `GarminDataSource` fails closed until Business access and the transport are approved.
- Keep Garmin's existing Coming Soon UI until a working authorization/revocation flow is verified.

## Private exploration (not part of the shipped app)
Garmin's official client: https://github.com/garmin/connect-personal-api-python
Garmin's Personal API FAQ: https://developer.garmin.com/gc-developer-program/personal/personal-faq/

Only use the Personal API for the account holder's own personal exploration within Garmin's terms. Use a private local environment with Python 3.12+, install the official package, and keep the key in the client’s private key file (permissions 0600). Do not use app credentials, repository secrets, public CI, shared ATHLTH infrastructure or AI providers for this exploration. Never paste a key into chat, source, or logs. Use synthetic fixtures in the commercial project.

Example read-only local commands (output contains private data; do not upload it):
```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install garmin-connect-personal-api-python
gc-personal --quiet activities --limit 5
```

## Release gates
1. Obtain Garmin Business approval and confirmed scopes, endpoint contract, environment and redistribution/processing terms. Personal API keys are not Business credentials.
2. Implement server-authorized OAuth and revocation with account isolation, scoped encrypted credentials and a deletion workflow. No secrets in the iOS binary.
3. Map verified activity payloads to normalized records; preserve device attribution and sport type; implement paging, retries, checkpoints and idempotent account-scoped upserts.
4. Implement health coverage (steps, rest, sleep, HRV, stress, Body Battery) with explicit units, source, timestamps and missing data. Do not equate Garmin HRV metrics with HealthKit SDNN without verifying comparability. Do not mix or sum overlapping daily measurements.
5. Match duplicate Apple Health records with explicit source/identity evidence. Time/distance matching only identifies candidates; it must never automatically delete data.
6. Confirm data storage, AI/analytics processors and all downstream uses against Garmin terms before enabling them. No forwarding to Coach, speech or analytics by default.
7. Add a native connection UI, consent and disconnect controls, Garmin attribution, history import and source selection. Run physical device/account tests.
8. Live tracking and sending workouts to the watch are separate capabilities requiring the relevant approved API/SDK and supported hardware. No live start is promised by this phase.
