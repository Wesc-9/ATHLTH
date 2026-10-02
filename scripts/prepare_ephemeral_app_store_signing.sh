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

  if [ -z "$bundle_id" ]; then
    echo "::error::Missing Apple bundle ID: $identifier"
    exit 1
  fi

  local profile_name="ATHLTH CI $label ${GITHUB_RUN_ID:-manual}"
  local request="$RUNNER_TEMP/profile-$env_prefix-request.json"
  local response="$RUNNER_TEMP/profile-$env_prefix-response.json"

  python - "$request" "$profile_name" "$bundle_id" "$TEMP_CERT_ID" <<'PY'
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

echo "Ephemeral Apple Distribution signing material prepared."
