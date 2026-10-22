#!/usr/bin/env bash
# Smoke test. For each test it prints what the test proves, the exact request,
# what it expects, what came back, and one PASS/FAIL line per check.
# Usernames, passwords and secrets are never printed.
#
#   bin/test.sh
#   WORKER_URL=https://tt-turn-credentials.<you>.workers.dev bin/test.sh
#
# TEST_ORIGIN=https://x.example.org picks the Origin header sent to the Worker
# (default: the first allowed origin from setup).
. "$(dirname "$0")/read_config.sh"

titles=(); proves=(); requests=(); expects=(); statuses=(); bodies=()
expect_common='HTTP 200 and a JSON body whose "iceServers" include a stun: URL, a turn: URL, a turns: URL, and an entry with a username + credential'

# TEST 1: ask Cloudflare directly, with the TURN key from tt-turn.env.
url="https://rtc.live.cloudflare.com/v1/turn/keys/$TURN_KEY_ID/credentials/generate-ice-servers"
raw=$(curl -sS -w $'\n%{http_code}' -X POST "$url" \
  -H "Authorization: Bearer $TURN_KEY_SECRET" \
  -H "Content-Type: application/json" \
  --data '{"ttl": 300}') || raw=$'\n000'
titles+=("Cloudflare issues TURN credentials for your TURN key")
proves+=("the TURN key ID and secret in tt-turn.env are valid")
requests+=("POST $url   (sends the TURN key secret, hidden; body {\"ttl\": 300} = a credential that expires in 5 minutes)")
expects+=("$expect_common")
statuses+=("${raw##*$'\n'}"); bodies+=("${raw%$'\n'*}")

# TEST 2 (only with WORKER_URL): ask the deployed Worker, as a browser would.
if [ -n "${WORKER_URL:-}" ]; then
  origin=${TEST_ORIGIN:-${ALLOWED_ORIGINS%%,*}}
  url="${WORKER_URL%/}/ice"
  raw=$(curl -sS -w $'\n%{http_code}' "$url" -H "Origin: $origin") || raw=$'\n000'
  titles+=("Your deployed Worker serves credentials to an allowed website")
  proves+=("the Worker is deployed, holds the right key, and accepts the origin $origin")
  requests+=("GET $url   (header Origin: $origin)")
  expects+=("$expect_common. A Worker over its usage cap answers with STUN only (relay=false), which fails the turn:, turns: and credential checks")
  statuses+=("${raw##*$'\n'}"); bodies+=("${raw%$'\n'*}")
fi

pass=0; fail=0
echo "tt-turn smoke test"
echo "TURN key under test: $TURN_KEY_ID   (usernames, passwords and secrets are never printed)"

for i in "${!titles[@]}"; do
  status=${statuses[$i]}; body=${bodies[$i]}
  echo
  echo "TEST $((i + 1)): ${titles[$i]}"
  echo "  Proves  : ${proves[$i]}"
  echo "  Request : ${requests[$i]}"
  echo "  Expects : ${expects[$i]}"
  echo "  Received: HTTP $status"

  n_stun=0; n_turn=0; n_turns=0; n_cred=0
  read -r n_stun n_turn n_turns n_cred < <(jq -r '
    [(.iceServers // []) | (if type == "array" then .[] else . end) | select(type == "object")] as $s
    | [$s[] | (.urls // empty) | (if type == "array" then .[] else . end) | select(type == "string")] as $u
    | [ ($u | map(select(startswith("stun:")))  | length),
        ($u | map(select(startswith("turn:")))  | length),
        ($u | map(select(startswith("turns:"))) | length),
        ($s | map(select(.username and .credential)) | length) ] | @tsv' <<<"$body" 2>/dev/null || true) || true
  n_stun=${n_stun:-0}; n_turn=${n_turn:-0}; n_turns=${n_turns:-0}; n_cred=${n_cred:-0}

  names=("HTTP status is 200" "response has a stun: URL" "response has a turn: URL" "response has a turns: URL" "an entry has a username + credential")
  oks=("$([ "$status" = 200 ] && echo 1 || echo 0)" "$((n_stun > 0))" "$((n_turn > 0))" "$((n_turns > 0))" "$((n_cred > 0))")
  details=("got $status" "$n_stun found" "$n_turn found" "$n_turns found" "$n_cred found")
  for j in "${!names[@]}"; do
    if [ "${oks[$j]}" = 1 ]; then
      echo "  PASS  ${names[$j]} (${details[$j]})"; pass=$((pass + 1))
    else
      echo "  FAIL  ${names[$j]} (${details[$j]})"; fail=$((fail + 1))
    fi
  done

  urls=$({ jq -r '[(.iceServers // []) | (if type == "array" then .[] else . end) | (.urls // empty) | (if type == "array" then .[] else . end)] | .[]' <<<"$body" 2>/dev/null || true; })
  echo "  URLs in the response:"
  if [ -n "$urls" ]; then sed 's/^/      /' <<<"$urls"; else echo "      (none)"; fi
  { jq -r 'select(type == "object" and has("relay")) | "  Worker flags: relay=\(.relay) ttl=\(.ttl) reason=\(.reason // "none")"' <<<"$body" 2>/dev/null || true; }
  { jq -r 'select(type == "object") | (.errors // [])[]? | "  Cloudflare error: \(.message // .)"' <<<"$body" 2>/dev/null || true; }
  if [ "$status" = 000 ]; then
    echo "  (no response: the server could not be reached)"
  elif [ -n "$body" ] && ! jq -e . >/dev/null 2>&1 <<<"$body"; then
    echo "  Response body (not JSON): $(printf %s "$body" | head -c 200)"
  fi
done

echo
if [ -z "${WORKER_URL:-}" ]; then
  echo "NOT RUN: Worker test. To include it: WORKER_URL=https://tt-turn-credentials.<you>.workers.dev bin/test.sh"
fi
echo "RESULT: $pass checks passed, $fail failed"
[ "$fail" -eq 0 ]
