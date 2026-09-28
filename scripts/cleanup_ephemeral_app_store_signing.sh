#!/usr/bin/env bash
set +e

if [ -n "${ASC_KEY_PATH:-}" ] && [ -s "${ASC_KEY_PATH:-}" ] && [ -d "$RUNNER_TEMP/asc-signing-venv" ]; then
  source "$RUNNER_TEMP/asc-signing-venv/bin/activate" 2>/dev/null || true

  TOKEN="$(python - <<'PY'
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
  )"

  for id_var in TEMP_PROFILE_MAIN_ID TEMP_PROFILE_WIDGET_ID TEMP_PROFILE_WATCH_ID; do
    resource_id="${!id_var:-}"
    if [ -n "$resource_id" ]; then
      curl --silent --show-error --request DELETE \
        --header "Authorization: Bearer $TOKEN" \
        "https://api.appstoreconnect.apple.com/v1/profiles/$resource_id" >/dev/null
    fi
  done

  # Never revoke a distribution certificate implicitly after a successful
  # TestFlight/App Store upload. Apple may still be processing or validating
  # builds signed with it. Revocation is now an explicit maintenance action.
  if [ "${ATHLTH_REVOKE_TEMP_CERT:-0}" = "1" ] && [ -n "${TEMP_CERT_ID:-}" ]; then
    curl --silent --show-error --request DELETE \
      --header "Authorization: Bearer $TOKEN" \
      "https://api.appstoreconnect.apple.com/v1/certificates/$TEMP_CERT_ID" >/dev/null
  fi
fi

if [ -n "${SIGNING_KEYCHAIN:-}" ]; then
  security delete-keychain "$SIGNING_KEYCHAIN" 2>/dev/null || true
fi
