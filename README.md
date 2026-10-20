# tt-TURN-cloudflare

Scripts to set up, configure and maintain a Cloudflare-hosted
[TURN](https://developers.cloudflare.com/realtime/turn/) fallback for
[Togetherness Table](https://github.com/sjbrown/togetherness).

TURN is only used when two peers can't connect directly (symmetric NAT,
corporate/hotel networks). Document content is still end-to-end encrypted
(DTLS); the relay just forwards bytes. Without TURN, those users fail to
connect at all. With it, they connect via relay.

Public domain. Forks welcome — nothing here is Togetherness-specific except
the default allowed origin.

## What's in the box

| Path | Purpose |
|---|---|
| `scripts/setup.sh` | Create a TURN key, deploy the Worker |
| `scripts/deploy.sh` | Push key into Worker secrets, `wrangler deploy` |
| `scripts/rotate.sh` | New key → deploy → later `--finish` deletes the old one |
| `scripts/status.sh` | List keys on the account, mark current/old |
| `scripts/test.sh` | Mint credentials, check for `turn:`/`turns:` URLs |
| `scripts/teardown.sh` | Delete keys and Worker |
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
scripts/setup.sh
scripts/test.sh
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
scripts/rotate.sh            # new key live immediately
# ...wait TTL_SECONDS (24h by default)...
scripts/rotate.sh --finish   # delete the old key
```

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
live account — run `scripts/setup.sh` and `scripts/test.sh` first and fix
`create_key` in `scripts/lib.sh` if the shape differs.
