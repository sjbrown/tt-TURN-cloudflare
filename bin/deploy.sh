#!/usr/bin/env bash
# Push the TURN key into the Worker's secrets and deploy the Worker.
# Refuses to run until bin/setup.sh has completed. Only extra dependency: node
# (for `npx wrangler`).
. "$(dirname "$0")/lib.sh"
load_config   # exits with "run bin/setup.sh first" if setup hasn't run
need npx

cd "$ROOT/worker"
export CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID"
export CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"

printf %s "$TURN_KEY_ID"     | npx --yes wrangler secret put TURN_KEY_ID
printf %s "$TURN_KEY_SECRET" | npx --yes wrangler secret put TURN_KEY_API_TOKEN

# Usage cap: needs the account id and the Account Analytics: Read token.
printf %s "$CF_ACCOUNT_ID"      | npx --yes wrangler secret put CF_ACCOUNT_ID
printf %s "$CF_ANALYTICS_TOKEN" | npx --yes wrangler secret put ANALYTICS_TOKEN

# ALLOWED_ORIGINS is deliberately not in wrangler.toml; it comes from setup.sh.
npx --yes wrangler deploy --var "ALLOWED_ORIGINS:$ALLOWED_ORIGINS"
