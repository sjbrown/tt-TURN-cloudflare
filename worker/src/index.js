// Mints short-lived Cloudflare Realtime TURN credentials so the long-lived
// TURN key never reaches the browser. No state, no logging of requests.
//
//   GET /ice  ->  { "iceServers": [ { urls: [...], username, credential }, ... ] }
//
// Secrets: TURN_KEY_ID, TURN_KEY_API_TOKEN
//          CF_ACCOUNT_ID, ANALYTICS_TOKEN   (optional: enable the usage cap)
// Vars:    ALLOWED_ORIGINS, TTL_SECONDS, USAGE_LIMIT_GB
//
// Usage cap (lazy kill switch): once month-to-date TURN egress reaches
// USAGE_LIMIT_GB, /ice stops minting TURN credentials and returns STUN only.
// Usage is read from Cloudflare's TURN analytics at most once per REFRESH_MS
// per Worker isolate, in the background — never on the request path — so the
// check adds no latency and fails open (analytics errors never block joins).

const UPSTREAM = 'https://rtc.live.cloudflare.com/v1/turn/keys';
const GRAPHQL = 'https://api.cloudflare.com/client/v4/graphql';
const STUN_ONLY = [{ urls: ['stun:stun.cloudflare.com:3478'] }];
const REFRESH_MS = 10 * 60 * 1000;
const RETRY_MS = 60 * 1000;

// Per-isolate memory. Cold isolates start unknown (fail open) and refresh.
const usage = { bytes: null, month: '', at: 0, pending: null };

async function fetchUsage(env) {
  const now = new Date();
  const to = now.toISOString().slice(0, 10);
  const from = `${to.slice(0, 8)}01`; // calendar month, UTC (billing cycle may differ)
  const query = `query { viewer { accounts(filter: {accountTag: ${JSON.stringify(env.CF_ACCOUNT_ID)}}) {
    callsTurnUsageAdaptiveGroups(filter: {date_geq: ${JSON.stringify(from)}, date_leq: ${JSON.stringify(to)}}, limit: 1000) {
      sum { egressBytes } } } } }`;
  const res = await fetch(GRAPHQL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.ANALYTICS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const json = await res.json();
  if (!res.ok || (json.errors && json.errors.length)) throw new Error('analytics query failed');
  const rows = json.data.viewer.accounts[0].callsTurnUsageAdaptiveGroups || [];
  return { bytes: rows.reduce((n, r) => n + (r.sum.egressBytes || 0), 0), month: to.slice(0, 7) };
}

// Returns the last known month-to-date bytes (or null) and kicks off a
// background refresh when it's stale. Never waits on the network.
function knownUsageBytes(env, ctx) {
  const stale = Date.now() - usage.at > REFRESH_MS;
  if (stale && !usage.pending) {
    usage.pending = fetchUsage(env)
      .then((u) => Object.assign(usage, u, { at: Date.now() }))
      .catch(() => { usage.at = Date.now() - REFRESH_MS + RETRY_MS; }) // keep last value, retry soon
      .finally(() => { usage.pending = null; });
    ctx.waitUntil(usage.pending);
  }
  // A value from a previous month no longer counts.
  return usage.month === new Date().toISOString().slice(0, 7) ? usage.bytes : null;
}

function overLimit(env, ctx) {
  const limitGB = Number(env.USAGE_LIMIT_GB);
  if (!(limitGB > 0) || !env.ANALYTICS_TOKEN || !env.CF_ACCOUNT_ID) return false; // cap not configured
  const bytes = knownUsageBytes(env, ctx);
  // 1 GB = 1e9 bytes: if Cloudflare uses GiB this errs on the early side.
  return bytes !== null && bytes >= limitGB * 1e9;
}

export default {
  async fetch(req, env, ctx) {
    const origin = req.headers.get('Origin');
    const allowed = (env.ALLOWED_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
    const anyOrigin = allowed.includes('*');

    // Browsers always send Origin on cross-origin fetches; reject unlisted ones.
    // (Non-browser callers send none — pair this with a rate-limit rule.)
    if (origin && !anyOrigin && !allowed.includes(origin)) {
      return new Response('forbidden', { status: 403 });
    }
    const cors = {
      'Access-Control-Allow-Origin': anyOrigin ? '*' : origin || '',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      Vary: 'Origin',
    };
    const json = { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };

    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

    const { pathname } = new URL(req.url);
    if (req.method !== 'GET' || pathname !== '/ice') {
      return new Response('not found', { status: 404, headers: cors });
    }

    // Kill switch: STUN only. Same response shape, so clients need no changes.
    if (overLimit(env, ctx)) {
      return new Response(
        JSON.stringify({ iceServers: STUN_ONLY, ttl: 0, relay: false, reason: 'usage-cap' }),
        { headers: json },
      );
    }

    const ttl = Math.max(60, Number(env.TTL_SECONDS) || 86400);
    const res = await fetch(`${UPSTREAM}/${env.TURN_KEY_ID}/credentials/generate-ice-servers`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ ttl }),
    });
    if (!res.ok) return new Response('upstream error', { status: 502, headers: cors });

    const data = await res.json();
    const list = Array.isArray(data.iceServers) ? data.iceServers : [data.iceServers];
    // Port 53 can stall ICE gathering without trickle ICE; drop it.
    const iceServers = list.filter(Boolean).map((s) => ({
      ...s,
      urls: [].concat(s.urls).filter((u) => !u.includes(':53?')),
    }));

    return new Response(JSON.stringify({ iceServers, ttl, relay: true }), { headers: json });
  },
};
