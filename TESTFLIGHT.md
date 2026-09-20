# ATHLTH V0.1 — TestFlight setup

ATHLTH uses Xcode 27 and GitHub Actions for archive validation and, once Apple credentials are configured, signed upload to App Store Connect.

## Permanent identifiers

- Product name: **ATHLTH**
- Version: **0.1.0**
- Apple Developer Team ID: **D3AX7B6RMW**
- iOS Bundle ID: **com.wesc9.athlth**
- watchOS Bundle ID: **com.wesc9.athlth.watchkitapp**
- Platforms: iPhone + iPad + Apple Watch companion

ATHLTH uses Apple's modern single-target watchOS app structure. There is no separate WatchKit extension App ID.

Do not create the App Store Connect app with a different iOS bundle ID.

## One-time Apple Developer setup

### 1. Register the iOS App ID

Apple Developer → Certificates, Identifiers & Profiles → Identifiers:

1. Add a new **App ID**.
2. Choose **App**.
3. Description: `ATHLTH`.
4. Bundle ID: `com.wesc9.athlth` (Explicit).
5. Enable **HealthKit**.
6. Enable **Sign in with Apple**.
7. Register.

### 2. Register the watchOS companion App ID

Create another explicit App ID:

- Description: `ATHLTH Watch`
- Bundle ID: `com.wesc9.athlth.watchkitapp`
- Enable **HealthKit**

### 3. Create the App Store Connect app

App Store Connect → Apps → **+** → New App:

- Platform: iOS
- Name: ATHLTH
- Primary language: English
- Bundle ID: `com.wesc9.athlth`
- SKU: `ATHLTH-IOS-001`

The Apple Watch companion is embedded in the iOS app. Do not create it as a separate App Store Connect app.

### 4. Create a Team App Store Connect API key

App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys.

Create a dedicated CI key and download its `.p8` file. Apple only allows the private key to be downloaded once.

Keep:

- Key ID
- Issuer ID
- Full contents of the `AuthKey_*.p8` file

Treat the private key as a high-value credential. Revoke it immediately if exposed.

## GitHub secrets

Repository → Settings → Secrets and variables → Actions → New repository secret.

Create:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_API_KEY_P8`

The Team ID is already configured in the project as `D3AX7B6RMW`.

For `ASC_API_KEY_P8`, paste the entire key, including the BEGIN/END PRIVATE KEY lines.

Never commit these values to the repository.

## Local signed archive

Requirements:

1. Xcode 27 stable installed.
2. Apple ID signed in under Xcode → Settings → Accounts.
3. Team `D3AX7B6RMW` available to Xcode.
4. XcodeGen installed with `brew install xcodegen`.

From the repository root:

```bash
bash scripts/testflight_archive.sh
```

The script creates:

```
build/ATHLTH.xcarchive
```

Then open Xcode → Window → Organizer → Archives → ATHLTH → Distribute App.

For the first hardware beta use **TestFlight Internal Only** with automatic signing.

## Automated TestFlight upload

After the three App Store Connect API secrets exist:

GitHub → ATHLTH → Actions → **Upload ATHLTH to TestFlight** → Run workflow.

The workflow:

1. Uses the dedicated Xcode 27 GitHub runner.
2. Generates the project with XcodeGen.
3. Creates a signed Release archive for iOS with the embedded Watch app.
4. Uses automatic signing for Team `D3AX7B6RMW`.
5. Exports and uploads the archive to App Store Connect/TestFlight.
6. Uses the GitHub run number as the TestFlight build number.

## Archive preflight

`Archive Preflight` creates an unsigned Release archive for a physical iOS destination.

This validates:

- Release configuration
- physical-device architecture
- iPhone app archive
- embedded single-target watchOS app
- HealthKit/watchOS project structure

It deliberately does not contain Apple private signing credentials.

## Export compliance

V0.1 sets `ITSAppUsesNonExemptEncryption = NO`.

## Never commit or share

- App Store Connect `.p8` private keys
- private signing keys
- exported `.p12` files
- Apple ID passwords
- two-factor authentication codes
