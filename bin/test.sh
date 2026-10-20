#!/usr/bin/env bash
# Smoke test. Mints credentials straight from Cloudflare; if WORKER_URL is set
# in the environment, also hits the deployed Worker. Never prints credentials.
#   bin/test.sh
#   WORKER_URL=https://tt-turn-credentials.<you>.workers.dev bin/test.sh
. "$(dirname "$0")/read_config.sh"

labels=("cloudflare direct")
bodies=("$(curl -sS --fail-with-body -X POST \
  "https://rtc.live.cloudflare.com/v1/turn/keys/$TURN_KEY_ID/credentials/generate-ice-servers" \
  -H "Authorization: Bearer $TURN_KEY_SECRET" \
  -H "Content-Type: application/json" \
  --data '{"ttl": 300}')")

if [ -n "${WORKER_URL:-}" ]; then
  # Default test origin: the first one chosen in setup.sh.
  labels+=("worker $WORKER_URL")
  bodies+=("$(curl -sS --fail-with-body "${WORKER_URL%/}/ice" \
    -H "Origin: ${TEST_ORIGIN:-${ALLOWED_ORIGINS%%,*}}")")
fi

for i in "${!labels[@]}"; do
  read -r n_stun n_turn n_turns n_cred < <(jq -r '
    [.iceServers | (if type == "array" then .[] else . end)] as $s
    | [$s[].urls | (if type == "array" then .[] else . end)] as $u
    | [ ($u | map(select(startswith("stun:")))  | length),
        ($u | map(select(startswith("turn:")))  | length),
        ($u | map(select(startswith("turns:"))) | length),
        ($s | map(select(.username and .credential)) | length) ] | @tsv' <<<"${bodies[$i]}")
  [ "$n_cred" -gt 0 ] || { echo "FAIL ${labels[$i]}: no credentialed entries"; exit 1; }
  echo "ok   ${labels[$i]}: stun=$n_stun turn=$n_turn turns=$n_turns"
done
