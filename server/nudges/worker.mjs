// Firebase stays on Spark. Authenticate through Firestore's existing member-only
// rules; no Google administrator key or public device-token collection is used.
const project = 'mwomeogeo';
const topic = 'com.chaen.mwomeogeo';
const meals = ['아침', '점심', '저녁'];
const day = 86400000;
const reply = (status, body) => Response.json(body, {status,
  headers: {'cache-control': 'no-store'}});
const problem = (status, error) => reply(status, {error});
const validTable = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(value);
const validToken = value => typeof value === 'string' && /^[a-f0-9]{32,512}$/.test(value);
const b64 = data => btoa(String.fromCharCode(...new Uint8Array(data)))
  .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
const bytes = value => new TextEncoder().encode(value);
async function hash(value) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes(value)))]
    .map(x => x.toString(16).padStart(2, '0')).join('');
}
async function smallBody(request) {
  const reader = request.body?.getReader();
  if (!reader) throw Error('body');
  let size = 0; const chunks = [];
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 2048) throw Error('body');
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  const joined = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { joined.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder().decode(joined));
}

export default {
  async fetch(request, env) {
    const route = new URL(request.url).pathname;
    if (request.method !== 'POST' || !['/devices', '/disable', '/nudge'].includes(route)) {
      return problem(404, 'not_found');
    }
    let body;
    try { body = await smallBody(request); } catch { return problem(400, 'invalid_request'); }
    if (!body || !validTable(body.tableId)) return problem(400, 'invalid_request');
    if (route === '/devices' && (!validToken(body.token)
      || !['production', 'sandbox'].includes(body.environment))) return problem(400, 'invalid_request');
    if (route === '/nudge' && (!Number.isInteger(body.meal) || body.meal < 0 || body.meal > 2
      || typeof body.requestId !== 'string' || !/^[a-f0-9-]{36}$/.test(body.requestId))) {
      return problem(400, 'invalid_request');
    }
    const authorization = request.headers.get('authorization') || '';
    if (!authorization.startsWith('Bearer ') || authorization.length > 8192) return problem(401, 'unauthorized');
    let uid;
    try {
      const part = authorization.slice(7).split('.')[1];
      const claims = JSON.parse(atob(part.replaceAll('-', '+').replaceAll('_', '/')));
      uid = claims.sub;
      if (typeof uid !== 'string' || uid.length < 1 || uid.length > 128
        || claims.aud !== project || claims.iss !== `https://securetoken.google.com/${project}`
        || claims.exp <= Date.now() / 1000) return problem(401, 'unauthorized');
    } catch { return problem(401, 'unauthorized'); }
    try {
      // Decoding above is validation only. This request is the authentication
      // boundary: Google verifies the signature and the deployed rules verify membership.
      const url = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/tables/${body.tableId}?mask.fieldPaths=memberIds`;
      const verified = await fetch(url, {headers: {authorization}, redirect: 'error',
        signal: AbortSignal.timeout(10000)});
      if (verified.status === 401) return problem(401, 'unauthorized');
      if ([403, 404].includes(verified.status)) return problem(403, 'forbidden');
      if (!verified.ok) return problem(503, 'unavailable');
      const table = await verified.json();
      const members = table.fields?.memberIds?.arrayValue?.values?.map(x => x.stringValue);
      if (!Array.isArray(members) || members.length > 20 || !members.includes(uid)) return problem(403, 'forbidden');
      const id = env.NUDGES.idFromName('push-registry');
      return await env.NUDGES.get(id).fetch(new Request(`https://private${route}`, {
        method: 'POST', body: JSON.stringify({...body, uid, members})}));
    } catch { return problem(503, 'unavailable'); }
  },
};

// Fetch-only Durable Object API; no public RPC methods. One private registry
// allows a reinstalled device token to change owners without leaking old-table pushes.
// ponytail: one registry suits a small app; shard by token/user if throughput requires it.
export class NudgeRegistry {
  constructor(ctx, env) { this.ctx = ctx; this.storage = ctx.storage; this.env = env; }
  async fetch(request) {
    const data = await request.json();
    const route = new URL(request.url).pathname;
    const key = `user:${data.uid}`;
    if (route === '/devices') {
      const tokenKey = `token:${await hash(data.token)}`;
      await this.storage.transaction(async tx => {
        const previous = await tx.get(key);
        if (previous && previous.token !== data.token) await tx.delete(`token:${await hash(previous.token)}`);
        const oldOwner = await tx.get(tokenKey);
        if (oldOwner && oldOwner !== data.uid) await tx.delete(`user:${oldOwner}`);
        await tx.put(tokenKey, data.uid);
        await tx.put(key, {token: data.token, environment: data.environment, seen: Date.now()});
      });
      return reply(200, {enabled: true});
    }
    if (route === '/disable') {
      await this.storage.transaction(async tx => {
        const previous = await tx.get(key);
        if (previous) await tx.delete(`token:${await hash(previous.token)}`);
        await tx.delete(key);
      });
      return reply(200, {enabled: false});
    }
    if (route !== '/nudge') return problem(404, 'not_found');
    if (!this.env.APNS_PRIVATE_KEY || !this.env.APNS_KEY_ID || !this.env.APNS_TEAM_ID) {
      return problem(503, 'not_configured');
    }
    const now = Date.now();
    const recipients = [...new Set(data.members)].filter(uid => uid !== data.uid);
    const devices = [];
    for (const uid of recipients) {
      const device = await this.storage.get(`user:${uid}`);
      if (device && device.seen > now - 30 * day) devices.push({uid, ...device});
    }
    if (!devices.length) return problem(404, 'no_devices');
    const requestKey = `request:${data.uid}:${data.requestId}`;
    const cooldownKey = `cooldown:${data.tableId}:${data.meal}`;
    const reserved = await this.storage.transaction(async tx => {
      const previous = await tx.get(requestKey);
      if (previous && previous.expires > now) {
        if (previous.tableId !== data.tableId || previous.meal !== data.meal) return problem(400, 'invalid_request');
        return previous.result ? reply(previous.status, previous.result) : problem(409, 'pending');
      }
      const cooldown = await tx.get(cooldownKey);
      if (cooldown && cooldown.until > now) return problem(429, 'cooldown');
      await tx.put(requestKey, {tableId: data.tableId, meal: data.meal, expires: now + day});
      await tx.put(cooldownKey, {requestKey, until: now + 1800000});
      return null;
    });
    if (reserved) return reserved;
    // Persist completion even when the client disconnects. Uncertain results
    // remain pending instead of being retried as a second push.
    const sending = this.deliver(data, devices, requestKey, cooldownKey, now);
    if (await this.storage.getAlarm() === null) await this.storage.setAlarm(now + day);
    this.ctx.waitUntil(sending);
    return await sending;
  }
  async deliver(data, devices, requestKey, cooldownKey, now) {
    let accepted = 0;
    try {
      const jwt = await providerToken(this.env);
      const date = new Date(now + 9 * 3600000).toISOString().slice(0, 10);
      const collapse = await hash(`${data.tableId}:${date}:${data.meal}`);
      const results = await Promise.all(devices.map(async device => {
        try {
          const host = device.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
          const response = await fetch(`https://${host}/3/device/${device.token}`, {
            method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
            headers: {authorization: `bearer ${jwt}`, 'apns-topic': topic,
              'apns-push-type': 'alert', 'apns-priority': '10', 'content-type': 'application/json',
              'apns-expiration': String(Math.floor(now / 1000) + 3600), 'apns-collapse-id': collapse},
            body: JSON.stringify({aps: {alert: {title: `${meals[data.meal]} 뭐 먹어!?`,
              body: '한 끼 사진으로 안부를 전해줘.'}, sound: 'default', 'thread-id': data.tableId},
              tableId: data.tableId, meal: data.meal}),
          });
          if (response.status === 200) return 1;
          const error = await response.json().catch(() => ({}));
          if (response.status === 410 || error.reason === 'BadDeviceToken' || error.reason === 'DeviceTokenNotForTopic') {
            await this.storage.transaction(async tx => {
              const current = await tx.get(`user:${device.uid}`);
              if (current?.token === device.token) {
                await tx.delete(`user:${device.uid}`);
                await tx.delete(`token:${await hash(device.token)}`);
              }
            });
          }
          return 0;
        } catch {
          // Network timeout can mean APNs accepted the request. Keep the reservation
          // and do not automatically retry (duplicate alerts are worse than a miss).
          return -1;
        }
      }));
      accepted = results.filter(value => value === 1).length;
      const uncertain = results.includes(-1);
      const status = accepted ? 200 : 502;
      const result = accepted ? {accepted} : {error: 'delivery_failed'};
      await this.storage.transaction(async tx => {
        await tx.put(requestKey, {tableId: data.tableId, meal: data.meal, expires: now + day, status, result});
        if (!accepted && !uncertain) {
          const cooldown = await tx.get(cooldownKey);
          if (cooldown?.requestKey === requestKey) await tx.delete(cooldownKey);
        }
      });
      return reply(status, result);
    } catch { return problem(503, 'unavailable'); }
  }
  async alarm() {
    for (const prefix of ['request:', 'cooldown:']) {
      let cursor;
      while (true) {
        const entries = await this.storage.list({prefix, limit: 128, ...(cursor ? {startAfter: cursor} : {})});
        for (const [key, value] of entries) {
          if ((value.expires ?? value.until) < Date.now()) await this.storage.delete(key);
          cursor = key;
        }
        if (entries.size < 128) break;
      }
    }
  }
}

let cachedProvider;
async function providerToken(env) {
  if (cachedProvider && cachedProvider.key === env.APNS_KEY_ID && cachedProvider.until > Date.now()) return cachedProvider.token;
  const header = b64(bytes(JSON.stringify({alg: 'ES256', kid: env.APNS_KEY_ID})));
  const claims = b64(bytes(JSON.stringify({iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000)})));
  const unsigned = `${header}.${claims}`;
  const pem = env.APNS_PRIVATE_KEY.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
    {name: 'ECDSA', namedCurve: 'P-256'}, false, ['sign']);
  const signature = await crypto.subtle.sign({name: 'ECDSA', hash: 'SHA-256'}, key, bytes(unsigned));
  const token = `${unsigned}.${b64(signature)}`;
  cachedProvider = {key: env.APNS_KEY_ID, until: Date.now() + 50 * 60000, token};
  return token;
}
