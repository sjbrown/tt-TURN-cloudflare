#!/usr/bin/env bash
# Delete the TURN key and the Worker. Asks first.
. "$(dirname "$0")/lib.sh"

read -r -p "Delete TURN key(s) and the Worker? [y/N] " ans
[ "$ans" = "y" ] || { echo "aborted"; exit 1; }

for f in "$KEYFILE" "$OLDKEYFILE"; do
  [ -f "$f" ] || continue
  id=$(jq -r .id "$f")
  cf DELETE "/$id" >/dev/null && echo "deleted key $id"
  rm -f "$f"
done

if command -v npx >/dev/null 2>&1; then
  ( cd "$ROOT/worker" &&
    CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID" CLOUDFLARE_API_TOKEN="$CF_API_TOKEN" \
    npx --yes wrangler delete --force )
fi
