# ATHLTH V0.1 — TestFlight setup

ATHLTH uses GitHub Actions to archive, sign, and upload V0.1 to App Store Connect.

## Permanent identifiers

- Product name: **ATHLTH**
- Version: **0.1.0**
- Bundle ID: **com.wesc9.athlth**
- Platforms: iPhone + iPad

Do not create the App Store Connect app with a different bundle ID.

## One-time Apple setup

### 1. Register the App ID

Apple Developer → Certificates, Identifiers & Profiles → Identifiers:

1. Add a new **App ID**.
2. Choose **App**.
3. Description: `ATHLTH`.
4. Bundle ID: `com.wesc9.athlth` (Explicit).
5. Enable **HealthKit**.
6. Register.

### 2. Create the App Store Connect app

App Store Connect → Apps → **+** → New App:

- Platform: iOS
- Name: ATHLTH
- Primary language: English
- Bundle ID: com.wesc9.athlth
- SKU: ATHLTH-IOS-001

### 3. Create a Team App Store Connect API key

Use a **Team API key**, not an Individual key, because automatic signing needs provisioning access.

App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys.

Create a dedicated CI key and download its `.p8` file. Apple only allows the private key to be downloaded once.

Keep:
- Key ID
- Issuer ID
- Full contents of the AuthKey_*.p8 file

Treat the key as a high-value credential. Revoke it immediately if exposed.

### 4. Find your Team ID

Apple Developer → Membership details → **Team ID**.

## GitHub secrets

Repository → Settings → Secrets and variables → Actions → New repository secret.

Create:
- `APPLE_TEAM_ID`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_API_KEY_P8`

For `ASC_API_KEY_P8`, paste the entire key, including the BEGIN/END PRIVATE KEY lines.

Never commit these values to the repository.

## Upload

GitHub → ATHLTH → Actions → **Upload ATHLTH to TestFlight** → Run workflow.

After Apple processes the build, open App Store Connect → ATHLTH → TestFlight. Create an Internal Testing group, add your App Store Connect user, and add the processed build.

## If cloud signing is denied

If Xcode reports no access to cloud-managed distribution certificates, the CI key/account needs appropriate distribution signing access. Do not commit a certificate or private key to source control as a workaround.

## Export compliance

V0.1 has no custom encryption/networking layer and sets `ITSAppUsesNonExemptEncryption = NO`.
