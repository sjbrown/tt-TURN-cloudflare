#!/usr/bin/env bash
# Delete the current TURN key and the Worker, then move tt-turn.env to /tmp.
# Asks first. (Older keys from earlier setup runs: see bin/status.sh.)
. "$(dirname "$0")/lib.sh"
load_config

read -r -p "Delete TURN key $TURN_KEY_ID and the Worker? [y/N] " ans
[ "$ans" = "y" ] || { echo "aborted"; exit 1; }

cf DELETE "/$TURN_KEY_ID" >/dev/null && echo "deleted key $TURN_KEY_ID"

if command -v npx >/dev/null 2>&1; then
  ( cd "$ROOT/worker" &&
    CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID" CLOUDFLARE_API_TOKEN="$CF_API_TOKEN" \
    npx --yes wrangler delete --force )
else
  echo "npx not found; delete the Worker yourself (tt-turn-credentials) in the dashboard" >&2
fi

backup_config   # the key in it no longer exists
