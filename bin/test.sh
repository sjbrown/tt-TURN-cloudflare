#!/usr/bin/env bash
# Smoke test. Mints credentials straight from Cloudflare; if WORKER_URL is set
# in the environment, also hits the deployed Worker. Never prints credentials.
#   bin/test.sh
#   WORKER_URL=https://tt-turn-credentials.<you>.workers.dev bin/test.sh
. "$(dirname "$0")/lib.sh"
load_config

check() { # label json
  local urls='[.iceServers | (if type=="array" then .[] else . end) | .urls | (if type=="array" then .[] else . end)]'
  local n_stun n_turn n_turns
  n_stun=$(jq  "$urls | map(select(startswith(\"stun:\")))  | length" <<<"$2")
  n_turn=$(jq  "$urls | map(select(startswith(\"turn:\")))  | length" <<<"$2")
  n_turns=$(jq "$urls | map(select(startswith(\"turns:\"))) | length" <<<"$2")
  jq -e '[.iceServers | (if type=="array" then .[] else . end) | select(.username and .credential)] | length > 0' <<<"$2" >/dev/null \
    || { echo "FAIL $1: no credentialed entries"; exit 1; }
  echo "ok   $1: stun=$n_stun turn=$n_turn turns=$n_turns"
}

check "cloudflare direct" "$(mint "$TURN_KEY_ID" "$TURN_KEY_SECRET" 300)"

if [ -n "${WORKER_URL:-}" ]; then
  # Default test origin: the first one chosen in setup.sh.
  check "worker $WORKER_URL" "$(curl -sS --fail-with-body "${WORKER_URL%/}/ice" -H "Origin: ${TEST_ORIGIN:-${ALLOWED_ORIGINS%%,*}}")"
fi
