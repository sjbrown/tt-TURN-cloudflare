#!/usr/bin/env bash
# Rotate the TURN key without dropping live sessions.
#   rotate.sh           create a new key, deploy it, keep the old one around
#   rotate.sh --finish  delete the old key (run after credentials minted from
#                       it have expired: TTL_SECONDS, default 24h)
. "$(dirname "$0")/lib.sh"

if [ "${1:-}" = "--finish" ]; then
  [ -f "$OLDKEYFILE" ] || { echo "nothing to finish (no $OLDKEYFILE)" >&2; exit 1; }
  id=$(jq -r .id "$OLDKEYFILE")
  cf DELETE "/$id" >/dev/null
  rm -f "$OLDKEYFILE"
  echo "deleted old key $id"
  exit 0
fi

[ -f "$KEYFILE" ] || { echo "no $KEYFILE — run setup.sh first" >&2; exit 1; }
[ -e "$OLDKEYFILE" ] && { echo "a rotation is pending; run rotate.sh --finish first" >&2; exit 1; }

mv "$KEYFILE" "$OLDKEYFILE"
create_key "${TURN_KEY_NAME:-togetherness}" "$KEYFILE" || { mv "$OLDKEYFILE" "$KEYFILE"; exit 1; }
echo "new key $(jq -r .id "$KEYFILE"); old key $(jq -r .id "$OLDKEYFILE") kept for now"

"$ROOT/scripts/deploy.sh"
echo "after the TTL has elapsed, run: scripts/rotate.sh --finish"
