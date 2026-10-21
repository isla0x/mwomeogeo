import test from 'node:test';
import assert from 'node:assert/strict';
import worker, {NudgeRegistry} from './worker.mjs';

class Storage {
  data = new Map(); alarm = null; tail = Promise.resolve();
  async get(key) { return structuredClone(this.data.get(key)); }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { this.data.delete(key); }
  async getAlarm() { return this.alarm; }
  async setAlarm(time) { this.alarm = time; }
  async list({prefix, limit, startAfter}) {
    return new Map([...this.data].filter(([key]) => key.startsWith(prefix) && (!startAfter || key > startAfter))
      .sort(([a], [b]) => a.localeCompare(b)).slice(0, limit));
  }
  transaction(fn) { const next = this.tail.then(() => fn(this)); this.tail = next.catch(() => {}); return next; }
}
const makeToken = uid => `header.${Buffer.from(JSON.stringify({sub: uid, aud: 'mwomeogeo',
  iss: 'https://securetoken.google.com/mwomeogeo', exp: Math.floor(Date.now() / 1000) + 3600})).toString('base64url')}.signature`;
const request = (path, body, uid = 'sender') => new Request(`https://nudges.test${path}`, {
  method: 'POST', headers: uid ? {authorization: `Bearer ${makeToken(uid)}`} : {}, body: JSON.stringify(body)});
const id = n => `${String(n).padStart(8, '0')}-0000-4000-8000-000000000000`;
let env, storage, pushes, members, firestoreStatus;
async function setup() {
  storage = new Storage(); pushes = []; members = ['sender', 'receiver']; firestoreStatus = 200;
  const signing = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const der = await crypto.subtle.exportKey('pkcs8', signing.privateKey);
  env = {APNS_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${Buffer.from(der).toString('base64')}\n-----END PRIVATE KEY-----`,
    APNS_KEY_ID: 'TESTKEY', APNS_TEAM_ID: 'TESTTEAM'};
  const registry = new NudgeRegistry({storage, waitUntil() {}}, env);
  env.NUDGES = {idFromName: value => value, get: () => ({fetch: request => registry.fetch(request)})};
  globalThis.fetch = async (url, options) => {
    if (url.startsWith('https://firestore.googleapis.com/')) return Response.json({
      fields: {memberIds: {arrayValue: {values: members.map(uid => ({stringValue: uid}))}}}}, {status: firestoreStatus});
    assert.match(url, /^https:\/\/api(\.sandbox)?\.push\.apple\.com\/3\/device\/[a-f0-9]+$/);
    pushes.push({url, ...options, payload: JSON.parse(options.body)});
    return new Response(null, {status: 200});
  };
  return registry;
}
const device = (token = 'a'.repeat(64), environment = 'production') => ({tableId: 'table', token, environment});
const send = (n = 1, meal = 1) => worker.fetch(request('/nudge', {tableId: 'table', meal, requestId: id(n)}), env);

test('auth, membership, input and payload boundaries fail closed', async () => {
  await setup();
  assert.equal((await worker.fetch(request('/devices', device(), null), env)).status, 401);
  assert.equal((await worker.fetch(request('/devices', device(), 'outsider'), env)).status, 403);
  firestoreStatus = 403;
  assert.equal((await worker.fetch(request('/devices', device()), env)).status, 403);
  firestoreStatus = 200;
  assert.equal((await worker.fetch(request('/devices', {...device(), tableId: '../elsewhere'}), env)).status, 400);
  assert.equal((await worker.fetch(request('/devices', {...device(), token: 'invalid'}), env)).status, 400);
  assert.equal((await send(1, 3)).status, 400);
  assert.equal((await worker.fetch(request('/nudge', {tableId: 'table', text: 'x'.repeat(3000)}), env)).status, 400);
  assert.equal(pushes.length, 0);
});
test('sends exact meal title to the other opted-in member; retries are idempotent', async () => {
  await setup();
  await worker.fetch(request('/devices', device('b'.repeat(64))), env);
  await worker.fetch(request('/devices', device(), 'receiver'), env);
  // Client-supplied recipients, user identity and arbitrary text are ignored.
  const response = await worker.fetch(request('/nudge', {tableId: 'table', meal: 1, requestId: id(1),
    uid: 'receiver', members: ['outsider'], title: 'forged'}), env);
  assert.deepEqual(await response.json(), {accepted: 1});
  assert.equal(pushes.length, 1);
  assert.ok(pushes[0].url.endsWith('a'.repeat(64)));
  assert.equal(pushes[0].payload.aps.alert.title, '점심 뭐 먹어!?');
  assert.equal(pushes[0].payload.tableId, 'table');
  assert.equal(pushes[0].headers['apns-topic'], 'com.chaen.mwomeogeo');
  assert.equal(pushes[0].headers['apns-push-type'], 'alert');
  assert.match(pushes[0].headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.deepEqual(await (await send()).json(), {accepted: 1});
  assert.equal(pushes.length, 1);
  assert.equal((await send(2)).status, 429);
});
test('concurrent sends share cooldown and different meals have separate text', async () => {
  await setup();
  await worker.fetch(request('/devices', device(), 'receiver'), env);
  const responses = await Promise.all([send(1), send(2)]);
  assert.deepEqual(responses.map(x => x.status).sort(), [200, 429]);
  assert.equal(pushes.length, 1);
  await send(3, 0); await send(4, 2);
  assert.deepEqual(pushes.map(x => x.payload.aps.alert.title), ['점심 뭐 먹어!?', '아침 뭐 먹어!?', '저녁 뭐 먹어!?']);
});
test('disable, token rotation and device ownership prevent stale/own pushes', async () => {
  await setup();
  await worker.fetch(request('/devices', device(), 'receiver'), env);
  await worker.fetch(request('/devices', device('c'.repeat(64)), 'receiver'), env);
  await send();
  assert.ok(pushes[0].url.endsWith('c'.repeat(64)));
  await worker.fetch(request('/disable', {tableId: 'table'}, 'receiver'), env);
  assert.equal((await send(2, 0)).status, 404);
  await worker.fetch(request('/devices', device(), 'receiver'), env);
  await worker.fetch(request('/devices', device(), 'sender'), env); // Reinstalled same APNs token has a new owner.
  assert.equal((await send(3, 2)).status, 404);
  members = ['sender'];
  assert.equal((await send(4, 2)).status, 404);
});
test('APNs rejection is not reported as success and bad tokens are removed', async () => {
  await setup();
  await worker.fetch(request('/devices', device(), 'receiver'), env);
  const normal = globalThis.fetch;
  globalThis.fetch = (url, options) => url.includes('push.apple.com')
    ? Promise.resolve(Response.json({reason: 'Unregistered'}, {status: 410})) : normal(url, options);
  assert.equal((await send()).status, 502);
  assert.equal((await send(2)).status, 404);
  assert.equal(await storage.get('user:receiver'), undefined);
});
