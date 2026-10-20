#!/usr/bin/env bash
# Delete the current TURN key and the Worker, then move tt-turn.env to /tmp.
# Asks first. (Older keys from earlier setup runs: see bin/status.sh.)
. "$(dirname "$0")/lib.sh"

read -r -p "Delete TURN key $TURN_KEY_ID and the Worker? [y/N] " ans
[ "$ans" = "y" ] || { echo "aborted"; exit 1; }

curl -sS --fail-with-body -X DELETE "$CF_API/$TURN_KEY_ID" \
  -H "Authorization: Bearer $CF_API_TOKEN" >/dev/null
echo "deleted key $TURN_KEY_ID"

if command -v npx >/dev/null 2>&1; then
  ( cd "$ROOT/worker" &&
    CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID" CLOUDFLARE_API_TOKEN="$CF_API_TOKEN" \
    npx --yes wrangler delete --force )
else
  echo "npx not found; delete the Worker yourself (tt-turn-credentials) in the dashboard" >&2
fi

# The key in the config no longer exists; move it aside rather than delete it.
bak="/tmp/tt-turn.env-$(date +%Y%m%d-%H%M%S)"
mv "$CONFIG" "$bak"
echo "moved the existing tt-turn.env to $bak (it holds secrets; delete it when you're done with it)"
