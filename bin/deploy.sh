#!/usr/bin/env bash
# Push the TURN key into the Worker's secrets and deploy the Worker.
# Only extra dependency: node (for `npx wrangler`).
. "$(dirname "$0")/lib.sh"
need npx
[ -f "$KEYFILE" ] || { echo "no $KEYFILE — run setup.sh first" >&2; exit 1; }

cd "$ROOT/worker"
export CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID"
export CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"

jq -r .id     "$KEYFILE" | npx --yes wrangler secret put TURN_KEY_ID
jq -r .secret "$KEYFILE" | npx --yes wrangler secret put TURN_KEY_API_TOKEN

# Usage cap (optional): needs the account id and a token with Account Analytics: Read.
if [ -n "${CF_ANALYTICS_TOKEN:-}" ]; then
  printf %s "$CF_ACCOUNT_ID"      | npx --yes wrangler secret put CF_ACCOUNT_ID
  printf %s "$CF_ANALYTICS_TOKEN" | npx --yes wrangler secret put ANALYTICS_TOKEN
else
  echo "note: CF_ANALYTICS_TOKEN not set; usage cap is disabled" >&2
fi

npx --yes wrangler deploy
