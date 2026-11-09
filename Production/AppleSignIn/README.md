# Native Apple sign-in

`AppleSignInFlow` provides native request setup and one-time nonce pairing. It does not create a backend session or store tokens. The host creates and retains one flow, calls `configure(_:)` from `SignInWithAppleButton`'s request callback, then calls `complete(_:)` on its result. Exchange the resulting identity token and **raw** nonce with the selected backend; regard the user as signed in only after the backend returns an authenticated session. Handle `.cancelled` quietly and show a recoverable error for other failures. Never log the token or nonce.

If request configuration fails, surface the error and do not exchange the authorization callback. Each callback consumes the pending nonce, including cancellation and malformed credentials. Do not initiate overlapping requests on one flow.

For Supabase, see [native ID-token sign-in](https://supabase.com/docs/reference/swift/auth-signinwithidtoken): pass the Apple identity token and raw nonce to `signInWithIdToken` with provider `.apple`; Apple receives the SHA-256 hex digest of that raw nonce. Other providers must explicitly support and verify the nonce flow.

The host app requires a correctly configured Apple Developer App ID and Sign in with Apple capability, and the selected backend must accept that app's audience. Apple's name and email may be provided only once, so handle missing values and persist the name through onboarding if needed. No developer credentials, backend, session persistence or app UI are configured in this package. End-to-end sign-in must be tested on a signed app with a configured provider.
