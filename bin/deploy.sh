#!/usr/bin/env bash
# Push the TURN key into the Worker's secrets and deploy the Worker.
# Refuses to run until bin/setup.sh has been run. Only extra dependency: node
# (for `npx wrangler`).
. "$(dirname "$0")/lib.sh"
need npx

# Setup must have run: it records the allowed origins and creates the TURN key.
missing=()
[ -f "$SETUPFILE" ] && jq -e '(.allowed_origins // "") != ""' "$SETUPFILE" >/dev/null 2>&1 \
  || missing+=("allowed origins ($SETUPFILE)")
[ -f "$KEYFILE" ] || missing+=("TURN key ($KEYFILE)")
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'setup has not been run; missing: %s\n' "${missing[*]}" >&2
  echo "run bin/setup.sh first" >&2
  exit 1
fi
origins=$(jq -r .allowed_origins "$SETUPFILE")

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

# ALLOWED_ORIGINS is deliberately not in wrangler.toml; it comes from setup.sh.
npx --yes wrangler deploy --var "ALLOWED_ORIGINS:$origins"
