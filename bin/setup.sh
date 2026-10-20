#!/usr/bin/env bash
# One-time setup: create a Cloudflare Realtime TURN key, then deploy the
# credential-minting Worker (unless --no-deploy).
. "$(dirname "$0")/lib.sh"

[ -e "$KEYFILE" ] && { echo "$KEYFILE already exists. Use rotate.sh to replace it." >&2; exit 1; }

create_key "${TURN_KEY_NAME:-togetherness}" "$KEYFILE"
echo "created TURN key $(jq -r .id "$KEYFILE") -> $KEYFILE (secret, mode 600, gitignored)"

if [ "${1:-}" != "--no-deploy" ]; then
  "$ROOT/bin/deploy.sh"
fi
