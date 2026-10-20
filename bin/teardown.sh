#!/usr/bin/env bash
# Delete the current TURN key and the Worker, then back up tt-turn.env to /tmp and remove it.
# Asks first. (Older keys from earlier setup runs: see bin/status.sh.)
. "$(dirname "$0")/read_config.sh"

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

# The key in the config no longer exists, so don't leave it lying around:
# back it up to /tmp, then remove the original.
bak="/tmp/tt-turn.env-$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG" "$bak"
rm "$CONFIG"
echo "copied the existing tt-turn.env to $bak and removed the original (it holds secrets; delete the copy when you're done with it)"
