#!/usr/bin/env bash
# Setup. Also how you change settings or rotate the key: just run it again.
#
# Asks for every setting, creates a NEW TURN key, saves everything to
# tt-turn.env, and deploys the Worker. An existing tt-turn.env is never
# overwritten: it's moved to /tmp/tt-turn.env-<timestamp> and the path is printed.
#
#   bin/setup.sh [--no-deploy]
#   CF_ACCOUNT_ID=... CF_API_TOKEN=... ALLOWED_ORIGINS=a.com,b.io bin/setup.sh   # no prompts
. "$(dirname "$0")/lib.sh"

# ask VAR LABEL SECRET(0|1) REQUIRED(0|1) — a value already in the environment skips the prompt
ask() {
  local var=$1 label=$2 secret=$3 required=$4 val=""
  [ -n "${!var-}" ] && return 0
  if [ -t 0 ]; then
    if [ "$secret" = 1 ]; then read -r -s -p "$label: " val; echo
    else read -r -p "$label: " val; fi
  fi
  if [ -z "$val" ] && [ "$required" = 1 ]; then
    echo "$var is required (set it in the environment when there's no terminal)" >&2; exit 1
  fi
  printf -v "$var" %s "$val"
}

ask CF_ACCOUNT_ID      "Cloudflare account ID" 0 1
ask CF_API_TOKEN       "Cloudflare API token (Realtime/Calls: Edit, Workers Scripts: Edit)" 1 1
ask CF_ANALYTICS_TOKEN "Analytics token for the usage cap (Account Analytics: Read; Enter to skip)" 1 0
ask ALLOWED_ORIGINS    "Allowed origins, comma-separated (e.g. apps.example.com,user.github.io)" 0 1

ALLOWED_ORIGINS=$(normalize_origins "$ALLOWED_ORIGINS")
case ",$ALLOWED_ORIGINS," in *,'*',*) echo "warning: '*' lets any website request credentials" >&2 ;; esac
[ -n "${CF_ANALYTICS_TOKEN:-}" ] || echo "note: no analytics token; the usage cap will be off" >&2

# Create the new key first: if anything above or here fails, the old config is untouched.
cf_api_init
TURN_KEY_NAME=${TURN_KEY_NAME:-togetherness}
create_key
echo "created TURN key $TURN_KEY_ID"

backup_config
write_config
echo "saved settings and key to $CONFIG (mode 600, gitignored)"

if [ "${1:-}" != "--no-deploy" ]; then
  "$ROOT/bin/deploy.sh"
fi
