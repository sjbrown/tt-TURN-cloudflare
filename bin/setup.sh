#!/usr/bin/env bash
# Setup: asks for the four settings, creates a NEW TURN key, and saves it all
# to tt-turn.env. Then run bin/deploy.sh to publish the Worker.
#
# Run it again any time to change a setting or rotate the key. An existing
# tt-turn.env is first COPIED to /tmp/tt-turn.env-<timestamp> (path printed), so
# you can look up your old values while answering. The original stays in place
# until the new one is written, so a failed run changes nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/tt-turn.env"

for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "missing dependency: $dep" >&2; exit 1; }
done

if [ -e "$CONFIG" ]; then
  bak="/tmp/tt-turn.env-$(date +%Y%m%d-%H%M%S)"
  cp "$CONFIG" "$bak"
  echo "copied the existing tt-turn.env to $bak (it holds secrets; delete it when you're done with it)"
fi

read -r -p "Cloudflare account ID: " CF_ACCOUNT_ID || true
[ -n "$CF_ACCOUNT_ID" ] || { echo "account ID is required" >&2; exit 1; }

read -r -s -p "Cloudflare API token (Realtime/Calls: Edit, Workers Scripts: Edit): " CF_API_TOKEN || true
echo
[ -n "$CF_API_TOKEN" ] || { echo "API token is required" >&2; exit 1; }

read -r -s -p "Analytics token for the usage cap (Account Analytics: Read): " CF_ANALYTICS_TOKEN || true
echo
[ -n "$CF_ANALYTICS_TOKEN" ] || { echo "analytics token is required" >&2; exit 1; }

read -r -p "Allowed origins, comma-separated (e.g. apps.example.com,user.github.io): " origins || true

# Normalize: bare hosts get https://, ends trimmed, lowercased, no paths. "*" allowed.
list=()
IFS=',' read -ra parts <<<"$origins" || true
for o in ${parts[@]+"${parts[@]}"}; do
  o=${o#"${o%%[![:space:]]*}"}; o=${o%"${o##*[![:space:]]}"}
  o=$(printf %s "$o" | tr '[:upper:]' '[:lower:]'); o=${o%/}
  [ -z "$o" ] && continue
  if [ "$o" != "*" ]; then
    [[ $o =~ ^https?:// ]] || o="https://$o"
    [[ $o =~ ^https?://[a-z0-9.-]+(:[0-9]+)?$ ]] || {
      echo "bad origin: $o (expected host or scheme://host[:port], no path)" >&2; exit 1; }
  fi
  list+=("$o")
done
[ "${#list[@]}" -gt 0 ] || { echo "at least one origin is required" >&2; exit 1; }
ALLOWED_ORIGINS=$(IFS=,; printf %s "${list[*]}")
case ",$ALLOWED_ORIGINS," in *,'*',*) echo "warning: '*' lets any website request credentials" >&2 ;; esac

TURN_KEY_NAME=togetherness
res=$(curl -sS --fail-with-body -X POST \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/calls/turn_keys" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "$(jq -n --arg n "$TURN_KEY_NAME" '{name:$n}')") || {
  echo "creating the TURN key failed:" >&2; echo "$res" >&2; exit 1; }
TURN_KEY_ID=$(jq -r '.result.uid // empty' <<<"$res")
TURN_KEY_SECRET=$(jq -r '.result.secret // empty' <<<"$res")
[ -n "$TURN_KEY_ID" ] && [ -n "$TURN_KEY_SECRET" ] || {
  # Field names only: the response can carry the key's secret, which stays off the terminal.
  echo "unexpected response shape from create (field names only):" >&2
  jq -c '{success, errors, result_fields: (try (.result | keys) catch null)}' <<<"$res" >&2; exit 1; }
echo "created TURN key $TURN_KEY_ID"

umask 077
{
  echo "# Written by bin/setup.sh. Holds secrets; never commit."
  printf 'CF_ACCOUNT_ID=%q\n'      "$CF_ACCOUNT_ID"
  printf 'CF_API_TOKEN=%q\n'       "$CF_API_TOKEN"
  printf 'CF_ANALYTICS_TOKEN=%q\n' "$CF_ANALYTICS_TOKEN"
  printf 'ALLOWED_ORIGINS=%q\n'    "$ALLOWED_ORIGINS"
  printf 'TURN_KEY_NAME=%q\n'      "$TURN_KEY_NAME"
  printf 'TURN_KEY_ID=%q\n'        "$TURN_KEY_ID"
  printf 'TURN_KEY_SECRET=%q\n'    "$TURN_KEY_SECRET"
} > "$CONFIG"
echo "saved settings and key to $CONFIG (mode 600, gitignored)"
