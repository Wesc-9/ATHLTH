# Private Garmin integration

Personal API is for an individual's own personal applications only.
Normal builds do not include the client, Keychain access or private settings screen.
For an owner-only local Debug build, add ATHLTH_GARMIN_PERSONAL to the app target's
SWIFT_ACTIVE_COMPILATION_CONDITIONS while retaining DEBUG and inherited flags.
Do not enable this in ordinary Release, external TestFlight, App Store,
distributed project settings or normal CI builds. For strictly personal admin
testing, the manual TestFlight workflow on release/v3.0.2 has an explicit
garmin_internal_test option, which compiles the settings-only personal client
and forces Apple's TestFlight internal-testing-only export. It cannot be used
for App Store release or external testing. Use only your own Garmin data and
confirm your Personal API terms allow this private development use. The
ordinary commercial integration remains disabled pending Garmin approval. A separate unsigned, simulator-only compile check may use
the flags with synthetic/no data and no credentials; it never publishes an app.
Install locally on your own device using Xcode, sign into your own ATHLTH account,
and open Settings > Health & connections > Garmin (admin/owner account). Create a personal key on Garmin Connect once.
The key is stored only after a successful preview in a device-only Keychain item
scoped to the ATHLTH account. Disconnect removes the local key; revoke on Garmin
to invalidate it server-side. Data stays in the private screen's memory.
No cross-account, HealthKit, Coach, backend, backup or analytics writes.
The preview refreshes when opened, on demand, and when foregrounded after 5 minutes.
Activity history is bounded to 30 days and 500 records. Some wellness response
fields require real-device verification; missing values are shown as missing.
No claim that Garmin HRV is equivalent to HealthKit HRV.

## Business connection (future)
User taps Connect Garmin, then authenticates and consents on Garmin's official
OAuth page. The approved ATHLTH backend must exchange the authorization code,
verify state, use PKCE where supported/required, associate tokens with the
authenticated ATHLTH account, support revocation/deletion, and expose connection
status to the iOS app. No Garmin password or personal key collection for users.
Do not invent OAuth endpoints or ship an OAuth client before Garmin provisions
the app's client credentials, redirect registration, scopes and documentation.
The existing GarminDataSource remains fail-closed until approved Business access.
No personal API key extraction, password interception or automated key creation.
Official sources:
https://developer.garmin.com/gc-developer-program/personal/personal-faq/
https://github.com/garmin/connect-personal-api-python
