#!/usr/bin/env bash
# Shared helpers. Source me; don't run me.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYFILE="$ROOT/.turn-key.json"       # current TURN key (secret!) — gitignored
OLDKEYFILE="$ROOT/.turn-key.old.json" # previous key during a rotation
SETUPFILE="$ROOT/.setup.json"        # choices made in setup.sh (allowed origins) — gitignored

if [ -f "$ROOT/.env" ]; then set -a; . "$ROOT/.env"; set +a; fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need curl; need jq

: "${CF_ACCOUNT_ID:?set CF_ACCOUNT_ID in .env (see .env.example)}"
: "${CF_API_TOKEN:?set CF_API_TOKEN in .env (see .env.example)}"

CF_API="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/calls/turn_keys"
RTC_API="https://rtc.live.cloudflare.com/v1/turn/keys"

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

# create_key NAME OUTFILE — creates a TURN key, writes {id,secret,name} (mode 600)
create_key() {
  local name=$1 out=$2 res
  res=$(cf POST "" "$(jq -n --arg n "$name" '{name:$n}')")
  umask 077
  jq '{id: (.result.uid // .result.id), secret: .result.key, name: .result.name}' <<<"$res" > "$out"
  jq -e '.id and .secret' "$out" >/dev/null || {
    rm -f "$out"; echo "unexpected response shape from create:" >&2
    jq 'del(.result.key)' <<<"$res" >&2; exit 1; }
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
