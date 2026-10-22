# tt-TURN-cloudflare

Scripts to set up, configure and maintain a Cloudflare-hosted
[TURN](https://developers.cloudflare.com/realtime/turn/) fallback for
[Togetherness Table](https://github.com/sjbrown/togetherness).

TURN relays traffic when two peers can't connect directly (symmetric NAT,
corporate and hotel networks). Document content stays end-to-end encrypted
(DTLS) and the relay forwards ciphertext. With TURN in place, those peers
connect through the relay.

Licensed under the GPLv3 (see `LICENSE`). Forks welcome; the Worker serves ICE
servers to any WebRTC app.

## What's in the box

| Path | Purpose |
|---|---|
| `bin/setup.sh` | Ask four questions, create a new TURN key, save everything to `tt-turn.env`. Re-run to change a setting or rotate the key |
| `bin/deploy.sh` | Push the key into the Worker's secrets and run `wrangler deploy` (run after setup) |
| `bin/status.sh` | List the account's TURN keys and mark the current one |
| `bin/check_usage.sh` | Print month-to-date TURN egress, the number Cloudflare bills on |
| `bin/test.sh` | Ask Cloudflare for credentials, and with `WORKER_URL=...` test the deployed Worker's `/ice` and `/mock-cap-hit` too. Prints each request, what it expects and a PASS/FAIL per check |
| `bin/teardown.sh` | Delete the key and the Worker |
| `bin/read_config.sh` | Sourced by every script except `setup.sh`; loads `tt-turn.env` |
| `worker/` | Stateless Worker: `GET /ice` returns short-lived ICE servers |

Your settings (account ID, API tokens, allowed origins) and the long-lived
TURN key live in one file, `tt-turn.env` (mode 600, gitignored), plus the
Worker's secrets. Browsers receive short-lived credentials (default 24h).

## Dependencies

`bash`, `curl` and `jq`, plus `node` for `deploy.sh` and `teardown.sh`.
wrangler runs on demand through `npx`.

## Quick start

```sh
bin/setup.sh    # asks for your settings, makes the key
bin/deploy.sh   # publishes the Worker
bin/test.sh
```

`setup.sh` asks for your Cloudflare account ID, an API token, an analytics
token (for the usage cap below), and which sites may call `/ice`. Those
answers live in `tt-turn.env`, which is gitignored.

## Changing settings and rotating the key

Run `bin/setup.sh` again. It asks the four questions, creates a **new** TURN
key, and writes a fresh `tt-turn.env`. Before prompting, it copies the old file
to `/tmp/tt-turn.env-<timestamp>` and prints that path, so you can look up your
old values while answering. The original is replaced only after the new key
exists. Run `bin/deploy.sh` afterwards to publish the change. Earlier keys stay
active on Cloudflare until you delete them in the
[dashboard](https://dash.cloudflare.com/?to=/:account/calls); `bin/status.sh`
lists them.

## Cost

Cloudflare Realtime TURN costs $0.05/GB egress after a 1,000 GB/month free tier
([FAQ](https://developers.cloudflare.com/realtime/turn/faq/)). Document sync
traffic is small, so typical usage fits within the free tier.

## Using it from Togetherness

Fetch ICE servers before constructing the provider, with a short timeout and a
STUN fallback that keeps the app offline-first:

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

Cloudflare offers informational email budget alerts and leaves spending
uncapped, so the Worker enforces its own cap. Once month-to-date TURN egress
reaches `USAGE_LIMIT_GB` (default 600 of the 1,000 GB free), `/ice` returns
STUN only instead of TURN credentials. Peers that connect directly play on;
peers that need the relay wait for the next month or a higher limit.

Both responses are HTTP 200 with the same fields, so one client code path
handles them:

```jsonc
{ "iceServers": [...], "ttl": 86400, "relay": true }                         // normal
{ "iceServers": [{ "urls": ["stun:..."] }], "ttl": 0, "relay": false,
  "reason": "usage-cap" }                                                    // capped
```

To exercise the capped-state UI without reaching the cap, call
`GET /mock-cap-hit` on the Worker (same origin rules as `/ice`). It returns the
capped response above, byte for byte, mints no credentials and reads no usage.

Check `relay === false` (and `reason`) to show a notice. Errors (403 for an
unlisted origin, 502 for an upstream failure) return plain text. When the
usage check can't run, the Worker serves credentials as usual (fail open), and
the response looks like any normal one.

- Usage comes from the
  [TURN analytics](https://developers.cloudflare.com/realtime/turn/analytics/)
  GraphQL dataset, refreshed in the background at most every 10 minutes per
  Worker isolate, so requests return immediately. If analytics is unavailable,
  TURN keeps serving credentials.
- The cap applies to new credentials. Credentials already issued work until
  `TTL_SECONDS` expires, so a short TTL tightens the cap. Deleting the key in
  the dashboard (or `bin/teardown.sh`) cuts off everything immediately.
- The Worker uses the analytics token (Account Analytics: Read) you give
  `bin/setup.sh`. Check the numbers with `bin/check_usage.sh`.
- The cap measures calendar-month (UTC) egress across the account's TURN keys;
  SFU traffic is outside this dataset. Cloudflare's billing cycle and rounding
  may differ slightly, so the default limit leaves headroom.

## Hardening notes

- `ALLOWED_ORIGINS` restricts which websites' browsers may call `/ice`. Add a
  Cloudflare rate-limiting rule on the Worker route to cover scripts and other
  non-browser callers.
- Lower `TTL_SECONDS` for shorter-lived credentials, and refresh them
  mid-session with `RTCPeerConnection.setConfiguration()`.
- For a fully self-hosted path, run [coturn](https://github.com/coturn/coturn)
  and point `iceServers` at it; Togetherness accepts any ICE server list.
