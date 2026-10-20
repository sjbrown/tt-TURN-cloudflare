#!/usr/bin/env bash
# Month-to-date TURN egress for the account (the metric Cloudflare bills on).
# Same query the Worker's usage cap uses, so run this to verify it before relying on the cap.
. "$(dirname "$0")/lib.sh"
load_config

tok=$CF_ANALYTICS_TOKEN   # needs "Account Analytics: Read"
to=$(date -u +%Y-%m-%d); from="${to%-*}-01"

body=$(jq -n --arg acc "$CF_ACCOUNT_ID" --arg f "$from" --arg t "$to" '{query:
  "query { viewer { accounts(filter: {accountTag: \($acc|@json)}) { callsTurnUsageAdaptiveGroups(filter: {date_geq: \($f|@json), date_leq: \($t|@json)}, limit: 1000) { sum { egressBytes } } } } }"}')

res=$(curl -sS --fail-with-body -X POST https://api.cloudflare.com/client/v4/graphql \
  -H "Authorization: Bearer $tok" -H "Content-Type: application/json" --data "$body")

jq -e '(.errors // []) | length == 0' <<<"$res" >/dev/null || { jq .errors <<<"$res" >&2; exit 1; }
jq -r --arg f "$from" --arg t "$to" \
  '[.data.viewer.accounts[0].callsTurnUsageAdaptiveGroups[]?.sum.egressBytes] | add // 0
   | "\($f) .. \($t): \((. / 1e7 | round) / 100) GB TURN egress"' <<<"$res"
