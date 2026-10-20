#!/usr/bin/env bash
# Smoke test. Mints credentials straight from Cloudflare; if WORKER_URL is set,
# also hits the deployed Worker. Never prints credentials.
. "$(dirname "$0")/lib.sh"
[ -f "$KEYFILE" ] || { echo "no $KEYFILE — run setup.sh first" >&2; exit 1; }

check() { # label json
  local n_stun n_turn n_turns
  n_stun=$(jq  '[.iceServers | (if type=="array" then .[] else . end) | .urls | (if type=="array" then .[] else . end) | select(startswith("stun:"))]  | length' <<<"$2")
  n_turn=$(jq  '[.iceServers | (if type=="array" then .[] else . end) | .urls | (if type=="array" then .[] else . end) | select(startswith("turn:"))]  | length' <<<"$2")
  n_turns=$(jq '[.iceServers | (if type=="array" then .[] else . end) | .urls | (if type=="array" then .[] else . end) | select(startswith("turns:"))] | length' <<<"$2")
  jq -e '[.iceServers | (if type=="array" then .[] else . end) | select(.username and .credential)] | length > 0' <<<"$2" >/dev/null \
    || { echo "FAIL $1: no credentialed entries"; exit 1; }
  echo "ok   $1: stun=$n_stun turn=$n_turn turns=$n_turns"
}

check "cloudflare direct" "$(mint "$(jq -r .id "$KEYFILE")" "$(jq -r .secret "$KEYFILE")" 300)"

if [ -n "${WORKER_URL:-}" ]; then
  check "worker $WORKER_URL" "$(curl -sS --fail-with-body "${WORKER_URL%/}/ice" -H "Origin: ${TEST_ORIGIN:-https://www.1kfa.com}")"
fi
