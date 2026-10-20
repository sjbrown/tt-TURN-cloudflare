#!/usr/bin/env bash
# List TURN keys on the account and flag which one this repo is using.
. "$(dirname "$0")/lib.sh"

current=""; [ -f "$KEYFILE" ] && current=$(jq -r .id "$KEYFILE")
old="";     [ -f "$OLDKEYFILE" ] && old=$(jq -r .id "$OLDKEYFILE")

cf GET | jq -r --arg cur "$current" --arg old "$old" '
  .result[]? |
  (.uid // .id) as $id |
  [$id, (.name // "-"), (.created // "-"),
   (if $id == $cur then "CURRENT" elif $id == $old then "OLD (pending delete)" else "" end)]
  | @tsv'
