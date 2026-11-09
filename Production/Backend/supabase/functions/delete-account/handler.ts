// No client-supplied user ID is accepted. Identity always comes from Auth.
export type Configuration = { url: string; serviceKey: string };
export function deletionHandler(config: Configuration, request: typeof fetch = fetch) {
  const reply = (status: number, body: object) => new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
    const authorization = req.headers.get('Authorization') ?? '';
    if (!/^Bearer [^\s]+$/.test(authorization)) return reply(401, { error: 'unauthorized' });
    let body;
    try { body = await req.json(); } catch { return reply(400, { error: 'invalid_request' }); }
    if (!body || body.confirmation !== 'DELETE' || Object.keys(body).length !== 1) {
      return reply(400, { error: 'confirmation_required' });
    }
    if (!config.url || !config.serviceKey) return reply(503, { error: 'not_configured' });
    const base = `${config.url.replace(/\/$/, '')}/auth/v1`;
    const headers = { apikey: config.serviceKey, Authorization: authorization };
    try {
      // Auth checks the token AND current user existence; decoded JWT claims alone aren't sufficient.
      const identity = await request(`${base}/user`, { headers });
      if (identity.status === 401 || identity.status === 403) return reply(401, { error: 'unauthorized' });
      if (!identity.ok) return reply(503, { error: 'auth_unavailable' });
      const user = await identity.json();
      if (typeof user.id !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(user.id)) {
        return reply(401, { error: 'unauthorized' });
      }
      // Revoke all refresh sessions before removing account data. Existing JWTs
      // cannot access deleted rows or create owned rows because of the auth.users FKs.
      const logout = await request(`${base}/logout?scope=global`, { method: 'POST', headers });
      if (!logout.ok) return reply(503, { error: 'session_revocation_failed' });
      const deletion = await request(`${base}/admin/users/${user.id}`, {
        method: 'DELETE',
        headers: { apikey: config.serviceKey, Authorization: `Bearer ${config.serviceKey}`,
          'Content-Type': 'application/json' },
        body: JSON.stringify({ should_soft_delete: false }),
      });
      if (!deletion.ok) return reply(503, { error: 'deletion_failed' });
      return reply(200, { deleted: true });
    } catch {
      // Never log credentials, tokens, request bodies, or account information.
      return reply(503, { error: 'temporarily_unavailable' });
    }
  };
}
