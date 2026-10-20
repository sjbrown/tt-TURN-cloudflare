#!/usr/bin/env bash
# Setup (safe to re-run): choose which sites may call /ice, create the TURN key
# if there isn't one yet, then deploy the Worker (unless --no-deploy).
# Re-run it any time to change the allowed origins.
#
#   bin/setup.sh
#   ALLOWED_ORIGINS="apps.example.com,user.github.io" bin/setup.sh   # no prompt
. "$(dirname "$0")/lib.sh"

current=""
[ -f "$SETUPFILE" ] && current=$(jq -r '.allowed_origins // ""' "$SETUPFILE")

input=${ALLOWED_ORIGINS:-}
if [ -z "$input" ]; then
  [ -t 0 ] || { echo "no terminal to prompt on; set ALLOWED_ORIGINS=host1,host2" >&2; exit 1; }
  echo "Which sites will call this Worker? Comma-separated hosts, e.g. apps.example.com,user.github.io"
  echo "(https:// is assumed; use http://localhost:8000 for local dev)"
  read -r -p "Allowed origins${current:+ [$current]}: " input
  input=${input:-$current}
fi

# Validate before creating anything on the account.
origins=$(normalize_origins "$input")
case ",$origins," in *,'*',*) echo "warning: '*' lets any website request credentials" >&2 ;; esac

jq -n --arg o "$origins" '{allowed_origins: $o}' > "$SETUPFILE"
echo "allowed origins: $origins"

if [ -e "$KEYFILE" ]; then
  echo "TURN key $(jq -r .id "$KEYFILE") already exists; keeping it (bin/rotate.sh replaces it)"
else
  create_key "${TURN_KEY_NAME:-togetherness}" "$KEYFILE"
  echo "created TURN key $(jq -r .id "$KEYFILE") -> $KEYFILE (secret, mode 600, gitignored)"
fi

if [ "${1:-}" != "--no-deploy" ]; then
  "$ROOT/bin/deploy.sh"
fi
