# tt-TURN-cloudflare

Scripts to set up, configure and maintain a Cloudflare-hosted
[TURN](https://developers.cloudflare.com/realtime/turn/) fallback for
[Togetherness Table](https://github.com/sjbrown/togetherness).

TURN is only used when two peers can't connect directly (symmetric NAT,
corporate/hotel networks). Document content is still end-to-end encrypted
(DTLS); the relay just forwards bytes. Without TURN, those users fail to
connect at all. With it, they connect via relay.

Licensed under the GPLv3 (see `LICENSE`). Forks welcome — nothing here is
Togetherness-specific except the default allowed origin.

## What's in the box

| Path | Purpose |
|---|---|
| `bin/setup.sh` | Create a TURN key, deploy the Worker |
| `bin/deploy.sh` | Push key into Worker secrets, `wrangler deploy` |
| `bin/rotate.sh` | New key → deploy → later `--finish` deletes the old one |
| `bin/status.sh` | List keys on the account, mark current/old |
| `bin/usage.sh` | Month-to-date TURN egress (what Cloudflare bills on) |
| `bin/test.sh` | Mint credentials, check for `turn:`/`turns:` URLs |
| `bin/teardown.sh` | Delete keys and Worker |
| `worker/` | Tiny stateless Worker: `GET /ice` → short-lived ICE servers |

The long-lived TURN key lives only in `.turn-key.json` (mode 600, gitignored)
and in the Worker's secrets. Browsers only ever see credentials that expire
(default 24h).

## Dependencies

`bash`, `curl`, `jq`. `node` only for `npx wrangler` when deploying the
Worker. Nothing is installed globally.

## Quick start

```sh
cp .env.example .env      # fill in CF_ACCOUNT_ID and CF_API_TOKEN
$EDITOR worker/wrangler.toml   # set ALLOWED_ORIGINS
bin/setup.sh
bin/test.sh
```

Cloudflare Realtime TURN: $0.05/GB egress after a 1,000 GB/month free tier
([FAQ](https://developers.cloudflare.com/realtime/turn/faq/)). Document sync
is tiny; expect to stay free.

## Using it from Togetherness

Fetch ICE servers before constructing the provider, with a short timeout
that falls back to plain STUN so offline-first behavior is preserved:

```js
async function iceServers() {
  try {
    const r = await fetch('https://tt-turn-credentials.<you>.workers.dev/ice',
                          { signal: AbortSignal.timeout(2000) });
    return (await r.json()).iceServers;
  } catch {
    return [{ urls: 'stun:stun.cloudflare.com:3478' }];
  }
}

const provider = new WebrtcProvider(tableId, ydoc, {
  signaling: signalingUrls,
  peerOpts: { config: { iceServers: await iceServers() } },
});
```

`peerOpts` is spread into `simple-peer`'s options (see `src/lib/y-webrtc.js`),
so `config.iceServers` replaces its built-in Google/Twilio STUN default.

## Rotation

```sh
bin/rotate.sh            # new key live immediately
# ...wait TTL_SECONDS (24h by default)...
bin/rotate.sh --finish   # delete the old key
```

## Usage cap (stay in the free tier)

Cloudflare's budget alerts are email-only and informational; there is no
hard spending cap. So the Worker enforces its own: once month-to-date TURN
egress reaches `USAGE_LIMIT_GB` (default 600 of the 1,000 GB free), `/ice`
returns STUN only instead of TURN credentials. Clients keep working; peers
who need the relay just can't connect.

Response shape (both are HTTP 200, same fields, so clients need no changes):

```jsonc
{ "iceServers": [...], "ttl": 86400, "relay": true }                         // normal
{ "iceServers": [{ "urls": ["stun:..."] }], "ttl": 0, "relay": false,
  "reason": "usage-cap" }                                                    // capped
```

Check `relay === false` (and `reason`) to show a notice. Errors (403 bad
origin, 502 upstream) are plain-text, not JSON. A fail-open response is
indistinguishable from a normal one.

- Usage comes from the
  [TURN analytics](https://developers.cloudflare.com/realtime/turn/analytics/)
  GraphQL dataset, refreshed in the background at most every 10 minutes per
  Worker isolate. It never delays a request and fails open: if analytics is
  down or unconfigured, TURN keeps working.
- It only stops *new* credentials. Ones already issued work until
  `TTL_SECONDS` expires, so keep the TTL short. For an immediate cutoff,
  delete the key (`bin/teardown.sh`, or `bin/rotate.sh` then `--finish`).
- Enable it: set `CF_ANALYTICS_TOKEN` (Account Analytics: Read) in `.env`
  and re-run `bin/deploy.sh`. Check the numbers with `bin/usage.sh`.
- Counts the calendar month (UTC) and the whole account's TURN egress, and
  ignores SFU traffic; Cloudflare's billing cycle and rounding may differ,
  hence the headroom.

## Hardening notes

- `ALLOWED_ORIGINS` blocks other websites' browsers, not scripts. Add a
  Cloudflare rate-limiting rule on the Worker route if abuse matters.
- Lower `TTL_SECONDS` if you'd rather refresh via
  `RTCPeerConnection.setConfiguration()` than hand out day-long credentials.
- Prefer a fully self-hosted path? Run [coturn](https://github.com/coturn/coturn)
  and point `iceServers` at it; nothing in Togetherness depends on Cloudflare.

## Status

The Cloudflare API response shape for key creation (`uid`/`key`) and the exact
API-token permission name are written from docs, not yet exercised against a
live account — run `bin/setup.sh` and `bin/test.sh` first and fix
`create_key` in `bin/lib.sh` if the shape differs. The usage-cap GraphQL
query (dataset and field names from the docs) is likewise untested; run
`bin/usage.sh` before relying on it.
