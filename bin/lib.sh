#!/usr/bin/env bash
# Shared helpers. Source me; don't run me.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Every setting plus the TURN key (secret!). Written by setup.sh, gitignored.
CONFIG="$ROOT/tt-turn.env"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need curl; need jq

RTC_API="https://rtc.live.cloudflare.com/v1/turn/keys"

cf_api_init() { CF_API="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/calls/turn_keys"; }

# load_config — every script except setup.sh starts with this. Fails with a
# pointer to setup.sh if setup hasn't completed.
load_config() {
  [ -f "$CONFIG" ] || { echo "no $CONFIG; run bin/setup.sh first" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "$CONFIG"
  local v missing=()
  for v in CF_ACCOUNT_ID CF_API_TOKEN CF_ANALYTICS_TOKEN ALLOWED_ORIGINS TURN_KEY_ID TURN_KEY_SECRET; do
    [ -n "${!v:-}" ] || missing+=("$v")
  done
  [ "${#missing[@]}" -eq 0 ] || {
    echo "$CONFIG is incomplete (missing: ${missing[*]}); run bin/setup.sh again" >&2; exit 1; }
  cf_api_init
}

# cf METHOD [PATH] [JSON_BODY]  — management API (create/list/delete keys)
cf() {
  local method=$1 path=${2:-} body=${3:-}
  curl -sS --fail-with-body -X "$method" "$CF_API$path" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    ${body:+--data "$body"}
}

# mint KEY_ID KEY_SECRET [TTL] — short-lived ICE servers JSON
mint() {
  local id=$1 secret=$2 ttl=${3:-86400}
  curl -sS --fail-with-body -X POST "$RTC_API/$id/credentials/generate-ice-servers" \
    -H "Authorization: Bearer $secret" \
    -H "Content-Type: application/json" \
    --data "$(jq -n --argjson t "$ttl" '{ttl:$t}')"
}

# create_key — creates a TURN key; sets TURN_KEY_ID and TURN_KEY_SECRET
create_key() {
  local res
  res=$(cf POST "" "$(jq -n --arg n "$TURN_KEY_NAME" '{name:$n}')") || {
    echo "creating the TURN key failed:" >&2; echo "$res" >&2; exit 1; }
  TURN_KEY_ID=$(jq -r '.result.uid // .result.id // empty' <<<"$res")
  TURN_KEY_SECRET=$(jq -r '.result.key // empty' <<<"$res")
  [ -n "$TURN_KEY_ID" ] && [ -n "$TURN_KEY_SECRET" ] || {
    echo "unexpected response shape from create:" >&2
    jq 'del(.result.key)' <<<"$res" >&2; exit 1; }
}

# backup_config — move any existing config out of the way. Never overwrites or
# deletes it: it goes to /tmp/<name>-<timestamp>, and we say where.
backup_config() {
  [ -e "$CONFIG" ] || return 0
  local bak
  bak="/tmp/$(basename "$CONFIG")-$(date +%Y%m%d-%H%M%S)"
  mv "$CONFIG" "$bak"
  echo "moved the existing $(basename "$CONFIG") to $bak (it holds secrets; delete it when you're done with it)"
}

# write_config — save every setting and the key (mode 600) from the variables
write_config() {
  (
    umask 077
    {
      echo "# Written by bin/setup.sh. Holds secrets; never commit."
      for v in CF_ACCOUNT_ID CF_API_TOKEN CF_ANALYTICS_TOKEN ALLOWED_ORIGINS \
               TURN_KEY_NAME TURN_KEY_ID TURN_KEY_SECRET; do
        printf '%s=%q\n' "$v" "${!v:-}"
      done
    } > "$CONFIG"
  )
}

# normalize_origins "a.com, https://b.io/" -> "https://a.com,https://b.io"
# Accepts bare hosts (https assumed) or scheme://host[:port]; no paths. "*" allowed.
# Prints the comma-joined list on stdout; returns 1 with a message on bad input.
normalize_origins() {
  local out=() raw=() o
  IFS=',' read -ra raw <<<"$1" || true
  for o in ${raw[@]+"${raw[@]}"}; do
    o=${o#"${o%%[![:space:]]*}"}; o=${o%"${o##*[![:space:]]}"}   # trim ends only
    o=$(printf %s "$o" | tr '[:upper:]' '[:lower:]'); o=${o%/}
    [ -z "$o" ] && continue
    if [ "$o" = "*" ]; then out+=("*"); continue; fi
    [[ $o =~ ^https?:// ]] || o="https://$o"
    [[ $o =~ ^https?://[a-z0-9.-]+(:[0-9]+)?$ ]] || {
      echo "bad origin: $o (expected host or scheme://host[:port], no path)" >&2; return 1; }
    out+=("$o")
  done
  [ "${#out[@]}" -gt 0 ] || { echo "at least one origin is required" >&2; return 1; }
  local IFS=,; printf %s "${out[*]}"
}
