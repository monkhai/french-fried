import { describe, expect, test } from 'bun:test';
import { deletionHandler } from '../supabase/functions/delete-account/handler';

const id = '00000000-0000-4000-8000-000000000123';
const config = { url: 'https://example.supabase.co', serviceKey: 'server-only-test-key' };
const makeRequest = (body: object = { confirmation: 'DELETE' }, token = 'user-session') => new Request('https://example.test/delete-account', {
  method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {}, body: JSON.stringify(body),
});
function mocked(statuses = [200, 204, 200]) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const request = async (input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    const status = statuses[calls.length - 1];
    return new Response(status === 204 ? null : JSON.stringify(calls.length === 1 ? { id } : {}), { status });
  };
  return { calls, handler: deletionHandler(config, request as typeof fetch) };
}
describe('account deletion boundary', () => {
  test('rejects missing auth before making administrative requests', async () => {
    const { calls, handler } = mocked();
    expect((await handler(makeRequest({}, ''))).status).toBe(401);
    expect(calls).toHaveLength(0);
  });
  test('rejects a client-selected account and missing confirmation', async () => {
    for (const body of [{ confirmation: 'DELETE', user_id: id }, {}]) {
      const { calls, handler } = mocked();
      expect((await handler(makeRequest(body))).status).toBe(400);
      expect(calls).toHaveLength(0);
    }
  });
  test('never deletes after failed authentication', async () => {
    const { calls, handler } = mocked([401]);
    expect((await handler(makeRequest())).status).toBe(401);
    expect(calls).toHaveLength(1);
  });
  test('does not delete when session revocation fails', async () => {
    const { calls, handler } = mocked([200, 500]);
    expect((await handler(makeRequest())).status).toBe(503);
    expect(calls).toHaveLength(2);
  });
  test('deletes only the verified caller after global sign-out', async () => {
    const { calls, handler } = mocked();
    const response = await handler(makeRequest());
    expect(await response.json()).toEqual({ deleted: true });
    expect(calls.map(c => c.url)).toEqual([
      `${config.url}/auth/v1/user`, `${config.url}/auth/v1/logout?scope=global`,
      `${config.url}/auth/v1/admin/users/${id}`,
    ]);
    expect(calls[0].init?.headers).toEqual({ apikey: config.serviceKey, Authorization: 'Bearer user-session' });
    expect(calls[2].init?.method).toBe('DELETE');
    expect(JSON.parse(calls[2].init?.body as string)).toEqual({ should_soft_delete: false });
  });
  test('does not report success on deletion failure or reveal server details', async () => {
    const { handler } = mocked([200, 204, 500]);
    const response = await handler(makeRequest());
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: 'deletion_failed' });
  });
});
