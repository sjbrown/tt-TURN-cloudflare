#!/usr/bin/env bash
# List TURN keys on the account and flag the one in tt-turn.env. Anything not
# marked CURRENT is left over from an earlier setup run and can be deleted in
# the dashboard: https://dash.cloudflare.com/?to=/:account/calls
. "$(dirname "$0")/lib.sh"

curl -sS --fail-with-body "$CF_API" -H "Authorization: Bearer $CF_API_TOKEN" |
  jq -r --arg cur "$TURN_KEY_ID" '
    .result[]? |
    (.uid // .id) as $id |
    [$id, (.name // "-"), (.created // "-"), (if $id == $cur then "CURRENT" else "" end)]
    | @tsv'
