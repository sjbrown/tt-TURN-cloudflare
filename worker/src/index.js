// Mints short-lived Cloudflare Realtime TURN credentials so the long-lived
// TURN key never reaches the browser. No state, no logging of requests.
//
//   GET /ice  ->  { "iceServers": [ { urls: [...], username, credential }, ... ] }
//
// Secrets: TURN_KEY_ID, TURN_KEY_API_TOKEN   Vars: ALLOWED_ORIGINS, TTL_SECONDS

const UPSTREAM = 'https://rtc.live.cloudflare.com/v1/turn/keys';

export default {
  async fetch(req, env) {
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

    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

    const { pathname } = new URL(req.url);
    if (req.method !== 'GET' || pathname !== '/ice') {
      return new Response('not found', { status: 404, headers: cors });
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

    return new Response(JSON.stringify({ iceServers, ttl }), {
      headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  },
};
