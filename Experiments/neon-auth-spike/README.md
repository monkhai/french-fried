# Neon Apple sign-in spike

This is an isolated proof-of-concept scaffold, not production code or a verified full auth flow.

## What exists

- A Neon Function-style `fetch` handler verifies a Managed Better Auth JWT against Neon JWKS/issuer and scopes reads and writes to the verified subject.
- `schema.sql` creates a tiny per-user note table for a disposable development branch.
- `node --test handler.test.mjs` checks missing/invalid token handling, identity scoping, and input validation using fake verification/storage. It does not test cryptography or Postgres.

## Unknown: native Apple sign-in

Neon's [current OAuth guide](https://neon.com/docs/auth/guides/setup-oauth) supports Apple and documents a browser redirect flow with a Services ID and Apple credentials. It does not document a Swift SDK or native Apple ID-token exchange. [Upstream Better Auth](https://better-auth.com/docs/authentication/apple) describes `signIn.social` with an Apple ID token and native bundle-ID audience configuration, but that does not establish that Neon's managed service exposes the required configuration or native session handling. Do not assume that flow works until tested or Neon confirms it.

## To complete the spike

1. Confirm an authorized Neon development project/branch and Functions-supported region. Enable managed auth and provide an Apple developer App ID, Services ID, team/key IDs and a Sign in with Apple key through appropriate protected configuration. Apple OAuth credentials are not shared by Neon.
2. Confirm the actual supported native Apple token exchange, audience and nonce handling with Neon; implement the native sign-in and session restoration only against that verified contract.
3. On the isolated branch, apply `schema.sql`, install packages from `package.json`, and deploy `index.mjs` using Neon tooling. `DATABASE_URL`, `NEON_AUTH_JWKS_URL` and `NEON_AUTH_BASE_URL` must be injected by the branch runtime.
4. Obtain a real managed-auth JWT for a signed-in user; call GET and PUT with a bearer token. Test a second user, no token, and invalid/expired tokens. Verify real database isolation and record results.

Never put an Apple key, database URL, token, or service credential in this directory. The scaffold has not been deployed or run with Neon, Apple, `jose`, or Postgres. Live project setup was outside this subtask's authorization.

Sources: [Neon OAuth](https://neon.com/docs/auth/guides/setup-oauth), [Neon Functions authentication](https://neon.com/docs/compute/functions/authentication), [Better Auth Apple](https://better-auth.com/docs/authentication/apple).
