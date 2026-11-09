import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeHandler } from './handler.mjs';

const rows = new Map();
const handler = makeHandler({
  verify: async token => { if (!['alice', 'bob'].includes(token)) throw new Error('bad token'); return { sub: token }; },
  getNote: async user => rows.get(user) ?? null,
  putNote: async (user, note) => rows.set(user, note)
});
const req = (token, method = 'GET', body) => new Request('https://example.test/', {
  method, headers: token ? { Authorization: `Bearer ${token}` } : {},
  ...(body === undefined ? {} : { body: JSON.stringify(body) })
});

test('rejects missing and invalid tokens', async () => {
  assert.equal((await handler.fetch(req())).status, 401);
  assert.equal((await handler.fetch(req('invalid'))).status, 401);
});

test('scopes writes and reads to the verified subject', async () => {
  assert.equal((await handler.fetch(req('alice', 'PUT', { note: 'hello', user_id: 'bob' }))).status, 200);
  assert.equal((await (await handler.fetch(req('alice'))).json()).note, 'hello');
  assert.equal((await (await handler.fetch(req('bob'))).json()).note, null);
});

test('rejects an invalid note', async () => {
  assert.equal((await handler.fetch(req('alice', 'PUT', { note: 'x'.repeat(201) }))).status, 400);
});
