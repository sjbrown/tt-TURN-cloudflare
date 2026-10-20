# tt-TURN-cloudflare

Scripts to set up, configure and maintain a Cloudflare-hosted
[TURN](https://developers.cloudflare.com/realtime/turn/) fallback for
[Togetherness Table](https://github.com/sjbrown/togetherness).

TURN is only used when two peers can't connect directly (symmetric NAT,
corporate/hotel networks). Document content is still end-to-end encrypted
(DTLS); the relay just forwards bytes. Without TURN, those users fail to
connect at all. With it, they connect via relay.

Licensed under the GPLv3 (see `LICENSE`). Forks welcome — nothing here is
Togetherness-specific.

## What's in the box

| Path | Purpose |
|---|---|
| `bin/setup.sh` | Ask for the four settings, create a new TURN key, save it all. Re-run to change anything or rotate the key |
| `bin/deploy.sh` | Push the key into Worker secrets, `wrangler deploy`; refuses to run before setup |
| `bin/status.sh` | List keys on the account, mark the current one |
| `bin/check_usage.sh` | Month-to-date TURN egress (what Cloudflare bills on) |
| `bin/test.sh` | Mint credentials, check for `turn:`/`turns:` URLs |
| `bin/teardown.sh` | Delete the key and Worker |
| `worker/` | Tiny stateless Worker: `GET /ice` → short-lived ICE servers |

Everything you enter (account ID, API tokens, allowed origins) and the
long-lived TURN key live in one file, `tt-turn.env` (mode 600, gitignored),
plus the Worker's secrets. Browsers only ever see credentials that expire
(default 24h).

## Dependencies

`bash`, `curl`, `jq`. `node` only for `npx wrangler` when deploying the
Worker. Nothing is installed globally.

## Quick start

```sh
bin/setup.sh    # asks for your settings, makes the key
bin/deploy.sh   # publishes the Worker
bin/test.sh
```

`setup.sh` asks for four things: your Cloudflare account ID, an API token, an
analytics token (for the usage cap below), and which sites may call `/ice`.
No site names or secrets live in the repo.

## Changing settings / rotating the key

Run `bin/setup.sh` again. It asks for everything again (no defaults), creates
a **new** TURN key, and first copies the old `tt-turn.env` to
`/tmp/tt-turn.env-<timestamp>`, printing that path so you can look up your old
values while answering. The original stays in place until the new file is
written, so a failed run changes nothing. Run `bin/deploy.sh` afterwards to publish the change. Earlier
keys stay active on Cloudflare until you delete them in
the [dashboard](https://dash.cloudflare.com/?to=/:account/calls);
`bin/status.sh` lists them.

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
  delete the key in the dashboard (or `bin/teardown.sh`).
- It uses the analytics token (Account Analytics: Read) you give
  `bin/setup.sh`. Check the numbers with `bin/check_usage.sh`.
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
the create call in `bin/setup.sh` if the shape differs. The usage-cap GraphQL
query (dataset and field names from the docs) is likewise untested; run
`bin/check_usage.sh` before relying on it.
