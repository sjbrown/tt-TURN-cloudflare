#!/usr/bin/env bash
# Sourced by every script except setup.sh (which creates the config).
# Strict mode, dependency check, then load tt-turn.env or stop.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/tt-turn.env"

for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "missing dependency: $dep" >&2; exit 1; }
done

[ -f "$CONFIG" ] || { echo "no $CONFIG; run bin/setup.sh first" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONFIG"

missing=""
for v in CF_ACCOUNT_ID CF_API_TOKEN CF_ANALYTICS_TOKEN ALLOWED_ORIGINS TURN_KEY_ID TURN_KEY_SECRET; do
  [ -n "${!v:-}" ] || missing="$missing $v"
done
[ -z "$missing" ] || { echo "$CONFIG is incomplete (missing:$missing); run bin/setup.sh again" >&2; exit 1; }

CF_API="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/calls/turn_keys"
