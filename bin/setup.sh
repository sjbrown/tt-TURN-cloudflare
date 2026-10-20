#!/usr/bin/env bash
# Setup: asks for the four settings, creates a NEW TURN key, and saves it all
# to tt-turn.env. Then run bin/deploy.sh to publish the Worker.
#
# Run it again any time to change a setting or rotate the key. An existing
# tt-turn.env is never overwritten: it's moved to /tmp/tt-turn.env-<timestamp>
# and the path is printed.
. "$(dirname "$0")/lib.sh"

read -r -p "Cloudflare account ID: " CF_ACCOUNT_ID || true
[ -n "$CF_ACCOUNT_ID" ] || { echo "account ID is required" >&2; exit 1; }

read -r -s -p "Cloudflare API token (Realtime/Calls: Edit, Workers Scripts: Edit): " CF_API_TOKEN || true
echo
[ -n "$CF_API_TOKEN" ] || { echo "API token is required" >&2; exit 1; }

read -r -s -p "Analytics token for the usage cap (Account Analytics: Read): " CF_ANALYTICS_TOKEN || true
echo
[ -n "$CF_ANALYTICS_TOKEN" ] || { echo "analytics token is required" >&2; exit 1; }

read -r -p "Allowed origins, comma-separated (e.g. apps.example.com,user.github.io): " origins || true
ALLOWED_ORIGINS=$(normalize_origins "$origins")
case ",$ALLOWED_ORIGINS," in *,'*',*) echo "warning: '*' lets any website request credentials" >&2 ;; esac

# Create the new key first: if anything above or here fails, the old config is untouched.
cf_api_init
TURN_KEY_NAME=togetherness
create_key
echo "created TURN key $TURN_KEY_ID"

backup_config
write_config
echo "saved settings and key to $CONFIG (mode 600, gitignored)"
