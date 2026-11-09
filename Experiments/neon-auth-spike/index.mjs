import { neon } from '@neondatabase/serverless';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { makeHandler } from './handler.mjs';

// Neon injects these when Postgres and managed auth are enabled on the branch.
const sql = neon(process.env.DATABASE_URL);
const jwks = createRemoteJWKSet(new URL(process.env.NEON_AUTH_JWKS_URL));
const issuer = new URL(process.env.NEON_AUTH_BASE_URL).origin;

export default makeHandler({
  verify: async token => (await jwtVerify(token, jwks, { issuer, algorithms: ['EdDSA'] })).payload,
  getNote: async userId => {
    const rows = await sql`SELECT note FROM spike_notes WHERE user_id = ${userId}`;
    return rows[0]?.note ?? null;
  },
  putNote: async (userId, note) => {
    await sql`INSERT INTO spike_notes (user_id, note) VALUES (${userId}, ${note})
      ON CONFLICT (user_id) DO UPDATE SET note = EXCLUDED.note`;
  }
});
