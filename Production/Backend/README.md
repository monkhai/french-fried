# Backend foundation

The iOS app uses Supabase for native Apple ID-token sign-in, account profiles, private run storage, and invite-only group summaries. The existing French Fried project hosts the shared service; each runner signs in with their own Apple Account. Source builds use the project configured in the ignored `Production/App/Local.xcconfig`.

The Neon spike is historical research and is not used by the production app. A public client receives only the project URL and publishable key. Service-role keys and database credentials stay server-side. RLS and checked RPCs enforce access; hiding the client key is not an access-control boundary.

- [Supabase native Apple sign-in](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple)
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)

## Data contract

- `profiles`: the signed-in person's display name.
- `runs`: one saved run, including its time, distance, session reference, and whether the prescribed session was completed. Pace and elapsed time can be calculated from the recorded values.
- `run_routes`: route points in a separate owner-only table. Its composite foreign key prevents attaching a route to another user's run. Group-facing reads must never include this table or route coordinates.
- `save_run(...)`: an authenticated, invoker-scoped Postgres function that creates a run and its route together in one transaction, returning the run ID. Its parameters mirror the run columns (excluding IDs and creation time), followed by a JSON array of route points. Pass an empty array when no points were captured. A route insertion error rolls back the run.
- `save_run_idempotent(p_run_id, ...)`: the preferred save RPC. Generate one UUID per finished run and retain that UUID and the exact payload through retries. Identical retries return the same ID; a changed payload or another user's ID yields a conflict. Run and route are inserted atomically.
- All access policies require `auth.uid()` to equal the row owner. Client code uses a publishable/anon key and an authenticated user session; never a service-role key.

## Group contract

The second migration adds `running_groups`, one `group_members` row per user, private invite tokens, and personal `milestones`. Membership and invite mutation go through transactional functions:

- `create_group(p_name)` → group UUID; creates the group, first membership, and random invite together.
- `get_group_invite(p_group_id)` → invite UUID; only a current member can obtain it. The app constructs and shares the URL; URL hosting and app-link setup remain open.
- `preview_group_invite(p_token)` → group ID and name for a signed-in invitee; an invalid token returns no rows.
- `join_group(p_token)` → group UUID; a current member joining their own group is idempotent; another membership raises `already_in_group`.
- `leave_group(p_group_id)` removes membership and deletes the group and invite when the final member leaves. The cleanup trigger also handles final membership removal when an account is deleted. Runs, routes, and milestones stay with the person.
- `list_group_progress(p_group_id)` → one row per current member with name, current week, character stage, cosmetic IDs, and this week's saved-run count capped at three. The caller computes the total and goal as the sum and three times the member count. The current implementation resets on Monday at 00:00 UTC; the product has not specified a timezone, so this is an implementation assumption to revisit.
- `list_group_activity(p_group_id)` → current members' historical saved-run summaries and milestones, newest first. It exposes distance, active time, completion status, and program/session references, but never coordinates. The app can use session references to identify completed sessions; average pace can be derived from time and distance. Former members' activity disappears because the query uses current membership.

Group reads check the caller's membership inside narrowly scoped security-definer functions. Direct `runs`, `run_routes`, and `milestones` reads remain owner-only. Invite tokens are private bearer capabilities: anyone holding one and signed in can join, so the app must avoid logging them. Invite rotation/expiry is not implemented.

## Authoritative program progression

`program_sessions` freezes the 27 canonical `couch-to-5k` version 1 sessions and their complete warm-up/run/walk/cool-down durations. The Swift source and timing attribution are in `Production/ProgramCore`. `list_my_program_progress()` is an authenticated, invoker-scoped RPC returning `session_id`, `week`, `run_number`, and `completed` for all 27 sessions; private run RLS remains enforced.

A session counts only when its saved completion flag is true, its active duration reaches the prescribed duration, and its wall-clock duration is consistent (one second of tolerance for rounded seconds). Repeats count once. Each program week requires all three distinct prescribed sessions; only contiguous completed weeks advance the profile. Completing a later week early records its sessions but does not skip an unfinished week. The next suggested run is the first incomplete prescribed session. There is no enforced calendar schedule or restart reset; users can repeat any session and should take rest days.

Private triggers serialize writes per owner, then update `current_week` (1–9), `character_stage` (completed weeks, 0–9), and unique weekly/graduation milestones in the same transaction as run/route saves. A failed route save rolls everything back. Updating or deleting the qualifying runs recomputes progress and removes unsupported milestones. Clients can edit their name and cosmetic choices, but cannot write earned profile fields or milestones. The database validates timing consistency, not that a person actually exercised; device recordings remain the source of the submitted data.

Group calendar-week contributions intentionally continue to count all saved runs, including early finishes, capped at three. This is separate from prescribed-session completion. Group progress and feeds now use automatically earned profile state and milestones.

## Verify before using

On an isolated Supabase development database, apply all migrations in order and run `tests/ownership.sql` and `tests/group_security.sql` as an administrative database role using `psql -v ON_ERROR_STOP=1 -f <test-file>` with the test database connection in the environment. Each script simulates multiple users and rolls back. They check owner access, cross-user denial, forged-owner inserts, atomic run-save rollback, membership restrictions, shared historical activity, private routes, the weekly cap, last-member deletion, and account-deletion cleanup. Also verify the real Swift Apple sign-in, session restoration, run saves, concurrent group joins/leaves, and a second authenticated user against the chosen project before calling the integration complete.

On 2026-11-01, all four migrations were applied to the dedicated development project and the owner, group and idempotent-save rollback SQL suites passed through the Supabase connector. These simulated authenticated database roles; they do not prove real Apple authentication, client session handling, concurrent operations, or physical-device behavior. A repeated group suite with account deletion required connector confirmation and expired; a separate read-only check confirmed anonymous group creation, join, invite lookup and direct invite reads are denied. Do not apply to production without completing the remaining checks.

The security advisor reports the seven public security-definer group RPCs because signed-in users can invoke them. That access is intentional: each checks identity or membership, and the group suite covers cross-user denial. They remain privileged code requiring continued review. The `group_invites` RLS-without-policy notice is intentional: direct access is denied, with token access through the member-checked RPC. The performance advisor flags the composite route foreign key, but `run_id` is already the primary key, limiting the lookup to one row. Unused-index notices on an empty development database do not establish that indexes should be removed.

On 2026-11-01, the fifth migration (`authoritative_program_progress`) was applied to the dedicated development project. `tests/program_progress.sql` passed through the connector with rolled-back fixtures: early runs, repeated sessions, out-of-order weeks, contiguous progress, graduation, idempotent retry, protected fields, failed-route atomicity, deletion recomputation, and cross-user isolation. Simultaneous independent transactions have not been stress-tested. Security advisor reported no new progression findings; existing group RPC and intentionally denied invite notices remain. The Apple-only project also reports disabled leaked-password protection, which is unrelated to Apple ID-token authentication.

## Account deletion

The `delete-account` Edge Function is deployed to the shared project. It accepts only `POST` with a user's bearer session and `{"confirmation":"DELETE"}`. It validates the caller through `/auth/v1/user`, revokes all refresh sessions, and deletes that exact Auth user through the server-only admin API. It rejects client-supplied IDs. Foreign keys remove the profile, runs, routes, milestones, and memberships; the cleanup trigger removes groups with no members. A failure is returned without exposing upstream credentials or error bodies.

Set `verify_jwt = false` for this function because the handler performs its own server-verified Auth check, compatible with current Supabase signing keys. The Supabase-provided `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` remain in the function environment, never in the iOS app. The function uses platform `fetch` and has no third-party runtime dependencies.

The native Apple integration exchanges an ID token and nonce with Supabase and does not obtain/store Apple's refresh or access tokens. Following [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple), deletion removes account data immediately, clears the device's saved session and unfinished run, and directs the user to manually revoke Apple access. The app also signs out when Apple delivers a credential-revoked notification.

On 2026-11-09, six handler tests passed (`bun test Production/Backend/tests/delete-account.test.ts`), the deployed endpoint rejected an unauthenticated request with HTTP 401, and `tests/account_deletion.sql` passed using rolled-back disposable fixtures against the shared project. It checks deletion cascades, empty-group cleanup, and denial of profile/group recreation with a deleted user's claims. These checks do not replace real-device authentication and deletion testing.
