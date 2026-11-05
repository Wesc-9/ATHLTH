#!/usr/bin/env bash
set -euo pipefail

: "${ASC_KEY_ID:?Missing ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Missing ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?Missing ASC_KEY_PATH}"
: "${GITHUB_ENV:?Missing GITHUB_ENV}"

python3 -m venv "$RUNNER_TEMP/asc-signing-venv"
source "$RUNNER_TEMP/asc-signing-venv/bin/activate"
python -m pip install --quiet pyjwt cryptography

make_token() {
  python - <<'PY'
import os, time, jwt
with open(os.environ["ASC_KEY_PATH"], "r", encoding="utf-8") as handle:
    key = handle.read()
now = int(time.time())
print(jwt.encode(
    {
        "iss": os.environ["ASC_ISSUER_ID"],
        "iat": now - 30,
        "exp": now + 600,
        "aud": "appstoreconnect-v1",
    },
    key,
    algorithm="ES256",
    headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
))
PY
}

# Reuse the private key as well as its Apple Distribution certificate.
# The encrypted envelope is restored from the previous GitHub Actions run.
SIGNING_ENVELOPE_DIR="$RUNNER_TEMP/athlth-reusable-signing"
ENCRYPTED_SIGNING_DIR="$RUNNER_TEMP/athlth-ci-signing-output"
SIGNING_PASSWORD_FILE="$RUNNER_TEMP/athlth-dist-password"
mkdir -p "$SIGNING_ENVELOPE_DIR" "$ENCRYPTED_SIGNING_DIR"
chmod 700 "$SIGNING_ENVELOPE_DIR" "$ENCRYPTED_SIGNING_DIR"

if [ -s "$SIGNING_ENVELOPE_DIR/signing-envelope.json" ]; then
  echo "::notice::Reusing previously stored ATHLTH Apple Distribution identity."
  python scripts/reusable_apple_signing_identity.py unseal \
    "$SIGNING_ENVELOPE_DIR/signing-envelope.json" \
    "$RUNNER_TEMP/athlth-dist.p12" \
    "$SIGNING_PASSWORD_FILE" \
    "$RUNNER_TEMP/athlth-dist-cert-id"
  CERT_ID="$(cat "$RUNNER_TEMP/athlth-dist-cert-id")"
  TOKEN="$(make_token)"
  LOOKUP_HTTP="$(curl --silent --show-error --retry 2 --retry-delay 3 \
    --output "$RUNNER_TEMP/reused-ci-certificate.json" \
    --write-out '%{http_code}' \
    --header "Authorization: Bearer $TOKEN" \
    "https://api.appstoreconnect.apple.com/v1/certificates/$CERT_ID")"
  if [ "$LOOKUP_HTTP" != "200" ]; then
    echo "::error::Stored ATHLTH Distribution certificate unavailable at Apple (HTTP $LOOKUP_HTTP). No certificates created or revoked."
    exit 1
  fi
  python scripts/reusable_apple_signing_identity.py verify \
    "$RUNNER_TEMP/reused-ci-certificate.json" \
    "$RUNNER_TEMP/athlth-dist.p12" \
    "$SIGNING_PASSWORD_FILE" \
    "$RUNNER_TEMP/athlth-dist-cert-id"
  P12_PASSWORD="$(cat "$SIGNING_PASSWORD_FILE")"
else
  echo "::notice::First reusable signing identity bootstrap; generating Apple Distribution certificate."
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$RUNNER_TEMP/athlth-dist.key" \
  -out "$RUNNER_TEMP/athlth-dist.csr" \
  -subj "/CN=ATHLTH CI Distribution"

TOKEN="$(make_token)"

python - "$RUNNER_TEMP/athlth-dist.csr" "$RUNNER_TEMP/certificate-request.json" <<'PY'
import json, sys
csr_path, out_path = sys.argv[1:3]
with open(csr_path, "r", encoding="utf-8") as handle:
    csr = handle.read()
payload = {
    "data": {
        "type": "certificates",
        "attributes": {
            "certificateType": "DISTRIBUTION",
            "csrContent": csr,
        },
    }
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY

HTTP_CODE="$(curl --silent --show-error \
  --output "$RUNNER_TEMP/certificate-response.json" \
  --write-out '%{http_code}' \
  --request POST \
  --header "Authorization: Bearer $TOKEN" \
  --header "Content-Type: application/json" \
  --data-binary "@$RUNNER_TEMP/certificate-request.json" \
  "https://api.appstoreconnect.apple.com/v1/certificates")"

# The ATHLTH 2.1.3 export (GitHub run 42122394376) created an
# ephemeral distribution certificate at 2026-11-05 22:33 UTC, after it
# verified and retired the prior CI-owned certificate 9285X3798K.
# That build archived and exported successfully, but its TestFlight upload
# was blocked by failing unit tests. Cleanup retains the distribution cert,
# while its private key was discarded with the temporary CI keychain.
# Only this exact verified ATHLTH CI certificate is eligible for rotation.
# This is a one-time repair; subsequent releases need a persistent securely
# stored signing identity rather than creating disposable certificates.
# On Apple's certificate quota error, rotate ONLY the exact known ATHLTH CI
# certificate and ONLY after verifying its id, type and narrow X.509 issuance
# window against that successful GitHub run. Never touch other certs.
# For future releases use a persistent encrypted distribution identity;
# one-off CI signing without retaining its private key is not sustainable.
if [ "$HTTP_CODE" = "409" ] \
  && grep -q "already have a current Distribution certificate" "$RUNNER_TEMP/certificate-response.json"; then
  echo "::notice::Apple signing certificate limit reached; checking the verified previous ATHLTH CI certificate."
  STALE_CERT_ID="9SPQDF8X2J"
  LOOKUP_HTTP="$(curl --silent --show-error --retry 2 --retry-delay 3 \
    --output "$RUNNER_TEMP/known-ci-certificate.json" \
    --write-out '%{http_code}' \
    --header "Authorization: Bearer $TOKEN" \
    "https://api.appstoreconnect.apple.com/v1/certificates/$STALE_CERT_ID")"

  if [ "$LOOKUP_HTTP" != "200" ]; then
    echo "::error::Could not verify the previous ATHLTH CI signing certificate (HTTP $LOOKUP_HTTP); refusing to touch any other certificates."
    exit 1
  fi

  python - "$RUNNER_TEMP/known-ci-certificate.json" "$STALE_CERT_ID" <<'PY'
import base64
from datetime import datetime, timezone
import json
import sys
from cryptography import x509

with open(sys.argv[1], encoding="utf-8") as handle:
    item = json.load(handle)["data"]
attrs = item["attributes"]
if item.get("id") != sys.argv[2] or attrs.get("certificateType") != "DISTRIBUTION":
    raise SystemExit("Previous ATHLTH CI certificate identity/type mismatch; no revocation performed")
certificate = x509.load_der_x509_certificate(base64.b64decode(attrs["certificateContent"]))
issued = certificate.not_valid_before_utc
# Apple normally backdates the certificate validity by about ten minutes.
# GitHub run 42122394376 created this cert at 2026-11-05 22:33 UTC.
# Require the exact logged ID, distribution type and X.509 issuance window.
start = datetime(2026, 11, 5, 22, 20, tzinfo=timezone.utc)
end = datetime(2026, 11, 5, 22, 36, tzinfo=timezone.utc)
if not start <= issued <= end:
    raise SystemExit(f"Certificate issued {issued} outside verified ATHLTH CI run; no revocation performed")
print("Verified previous ATHLTH CI distribution certificate; safe targeted rotation.")
PY

  DELETE_HTTP="$(curl --silent --show-error \
    --output "$RUNNER_TEMP/known-ci-delete-response.txt" \
    --write-out '%{http_code}' \
    --request DELETE \
    --header "Authorization: Bearer $TOKEN" \
    "https://api.appstoreconnect.apple.com/v1/certificates/$STALE_CERT_ID")"
  if [ "$DELETE_HTTP" != "204" ]; then
    echo "::error::Could not retire the verified CI certificate (HTTP $DELETE_HTTP); refusing any other certificate revocations."
    exit 1
  fi
  echo "::notice::Retired only the verified old ATHLTH CI certificate. Retrying distribution signing."
  TOKEN="$(make_token)"
  HTTP_CODE="$(curl --silent --show-error \
    --output "$RUNNER_TEMP/certificate-response.json" \
    --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $TOKEN" \
    --header "Content-Type: application/json" \
    --data-binary "@$RUNNER_TEMP/certificate-request.json" \
    "https://api.appstoreconnect.apple.com/v1/certificates")"
fi

if [ "$HTTP_CODE" != "201" ]; then
  echo "::error::Could not create Apple Distribution certificate (HTTP $HTTP_CODE)."
  cat "$RUNNER_TEMP/certificate-response.json"
  exit 1
fi

CERT_ID="$(python - "$RUNNER_TEMP/certificate-response.json" "$RUNNER_TEMP/athlth-dist.cer" <<'PY'
import base64, json, sys
response_path, cert_path = sys.argv[1:3]
with open(response_path, "r", encoding="utf-8") as handle:
    item = json.load(handle)["data"]
with open(cert_path, "wb") as handle:
    handle.write(base64.b64decode(item["attributes"]["certificateContent"]))
print(item["id"])
PY
)"
export TEMP_CERT_ID="$CERT_ID"
echo "TEMP_CERT_ID=$CERT_ID" >> "$GITHUB_ENV"

openssl x509 -inform DER -in "$RUNNER_TEMP/athlth-dist.cer" -out "$RUNNER_TEMP/athlth-dist.pem"

P12_PASSWORD="$(openssl rand -hex 16)"
  printf '%s\n' "$P12_PASSWORD" > "$SIGNING_PASSWORD_FILE"
  chmod 600 "$SIGNING_PASSWORD_FILE"
fi

# Store ONLY the AES-GCM authenticated ciphertext; never upload a private
# key, raw P12, encryption secret, password or unencrypted provisioning data.
python scripts/reusable_apple_signing_identity.py seal \
  "$RUNNER_TEMP/athlth-dist.p12" \
  "$SIGNING_PASSWORD_FILE" \
  "$CERT_ID" \
  "$ENCRYPTED_SIGNING_DIR/signing-envelope.json"

KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
KEYCHAIN_PATH="$RUNNER_TEMP/athlth-signing.keychain-db"

openssl pkcs12 -export -legacy \
  -inkey "$RUNNER_TEMP/athlth-dist.key" \
  -in "$RUNNER_TEMP/athlth-dist.pem" \
  -out "$RUNNER_TEMP/athlth-dist.p12" \
  -passout "pass:$P12_PASSWORD"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$RUNNER_TEMP/athlth-dist.p12" \
  -k "$KEYCHAIN_PATH" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null

ORIGINAL_KEYCHAINS="$(security list-keychains -d user | tr -d '"')"
security list-keychains -d user -s "$KEYCHAIN_PATH" $ORIGINAL_KEYCHAINS
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q "Apple Distribution"

export SIGNING_KEYCHAIN="$KEYCHAIN_PATH"
echo "SIGNING_KEYCHAIN=$KEYCHAIN_PATH" >> "$GITHUB_ENV"

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"

create_profile() {
  local identifier="$1"
  local label="$2"
  local env_prefix="$3"
  local lookup="$RUNNER_TEMP/bundle-$env_prefix.json"

  TOKEN="$(make_token)"

  curl --fail-with-body --silent --show-error --get \
    --output "$lookup" \
    --header "Authorization: Bearer $TOKEN" \
    --data-urlencode "filter[identifier]=$identifier" \
    --data-urlencode "limit=200" \
    "https://api.appstoreconnect.apple.com/v1/bundleIds"

  local bundle_id
  bundle_id="$(python - "$lookup" "$identifier" <<'PY'
import json, sys
path, identifier = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle).get("data", [])
matches = [
    item for item in data
    if item.get("attributes", {}).get("identifier") == identifier
]
print(matches[0]["id"] if matches else "")
PY
  )"

  if [ -z "$bundle_id" ] && [ "$identifier" = "com.wesc9.athlth.watchkitapp.widgets" ]; then
    # The Watch Widget is its own signed app extension and needs a distinct
    # explicit Apple Developer bundle ID even though it lives inside the Watch app.
    local registration="$RUNNER_TEMP/register-watch-widgets.json"
    python - "$registration" "$identifier" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"data": {"type": "bundleIds", "attributes": {
        "identifier": sys.argv[2],
        "name": "ATHLTH Watch Widgets",
        "platform": "IOS"
    }}}, handle)
PY
    local registered="$RUNNER_TEMP/register-watch-widgets-response.json"
    local registration_code
    registration_code="$(curl --silent --show-error --retry 3 --retry-delay 5 \
      --output "$registered" --write-out '%{http_code}' --request POST \
      --header "Authorization: Bearer $TOKEN" \
      --header "Content-Type: application/json" \
      --data-binary "@$registration" \
      "https://api.appstoreconnect.apple.com/v1/bundleIds")"
    if [ "$registration_code" != "201" ]; then
      echo "::error::Could not register $identifier with Apple (HTTP $registration_code)."
      cat "$registered"
      exit 1
    fi
    bundle_id="$(python - "$registered" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["data"]["id"])
PY
    )"
    echo "Registered Watch Widget App ID: $identifier"
  fi

  if [ -z "$bundle_id" ]; then
    echo "::error::Missing Apple bundle ID: $identifier. Register it before TestFlight signing."
    exit 1
  fi

  local profile_name="ATHLTH CI $label ${GITHUB_RUN_ID:-manual}"
  local request="$RUNNER_TEMP/profile-$env_prefix-request.json"
  local response="$RUNNER_TEMP/profile-$env_prefix-response.json"

  python - "$request" "$profile_name" "$bundle_id" "$CERT_ID" <<'PY'
import json, sys
path, name, bundle_id, cert_id = sys.argv[1:5]
payload = {
    "data": {
        "type": "profiles",
        "attributes": {
            "name": name,
            "profileType": "IOS_APP_STORE",
        },
        "relationships": {
            "bundleId": {
                "data": {"type": "bundleIds", "id": bundle_id}
            },
            "certificates": {
                "data": [{"type": "certificates", "id": cert_id}]
            },
        },
    }
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY

  local http_code
  http_code="$(curl --silent --show-error \
    --output "$response" \
    --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $TOKEN" \
    --header "Content-Type: application/json" \
    --data-binary "@$request" \
    "https://api.appstoreconnect.apple.com/v1/profiles")"

  if [ "$http_code" != "201" ]; then
    echo "::error::Could not create App Store profile for $identifier (HTTP $http_code)."
    cat "$response"
    exit 1
  fi

  local mobileprovision="$RUNNER_TEMP/$env_prefix.mobileprovision"
  local values
  values="$(python - "$response" "$mobileprovision" <<'PY'
import base64, json, sys
response_path, output_path = sys.argv[1:3]
with open(response_path, "r", encoding="utf-8") as handle:
    item = json.load(handle)["data"]
attrs = item["attributes"]
with open(output_path, "wb") as handle:
    handle.write(base64.b64decode(attrs["profileContent"]))
print(item["id"])
print(attrs["name"])
PY
  )"

  local profile_id
  local resolved_name
  profile_id="$(printf '%s\n' "$values" | sed -n '1p')"
  resolved_name="$(printf '%s\n' "$values" | sed -n '2p')"

  local plist="$RUNNER_TEMP/$env_prefix-profile.plist"
  security cms -D -i "$mobileprovision" > "$plist"
  local uuid
  uuid="$(/usr/libexec/PlistBuddy -c "Print :UUID" "$plist")"
  cp "$mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"

  export "TEMP_PROFILE_${env_prefix}_ID=$profile_id"
  export "PROFILE_${env_prefix}_NAME=$resolved_name"
  echo "TEMP_PROFILE_${env_prefix}_ID=$profile_id" >> "$GITHUB_ENV"
  echo "PROFILE_${env_prefix}_NAME=$resolved_name" >> "$GITHUB_ENV"

  echo "$identifier -> $resolved_name ($uuid)"
}

create_profile "com.wesc9.athlth" "Main" "MAIN"
create_profile "com.wesc9.athlth.widgets" "Widgets" "WIDGET"
create_profile "com.wesc9.athlth.watchkitapp" "Watch" "WATCH"
create_profile "com.wesc9.athlth.watchkitapp.widgets" "Watch Widgets" "WATCH_WIDGET"

echo "Reusable Apple Distribution signing identity and profiles ready for all four signed bundles."
