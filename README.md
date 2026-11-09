# French Fried

An iOS running app with a Couch to 5K program, run tracking, Apple sign-in, groups, and Live Activities.

## Build

Requires Xcode with the iOS 26 SDK and XcodeGen.

1. Copy `Production/App/Local.xcconfig.example` to `Production/App/Local.xcconfig` and supply your Supabase project URL, publishable client key, and Apple development team ID. The URL escape in the example is required by xcconfig syntax.
2. Set your own bundle identifiers in `Production/App/project.yml` and configure Sign in with Apple for them.
3. Apply the SQL migrations in `Production/Backend/supabase/migrations` in filename order to your own Supabase project; see the backend README for access controls and limitations.
4. Run `cd Production/App && xcodegen generate`, open the generated project, and build.

Local configuration, signing files, generated projects, build output, prototypes, and internal review captures are excluded from Git. Existing local files are preserved. Optional generated voice recordings are excluded pending confirmation of redistribution rights; missing recordings are handled by the cue player. The cue scripts remain available in `Production/Voice`.

## Tests

Run `swift test --package-path Production/ProgramCore` and `swift test --package-path Production/RunTracking`. Backend SQL security tests are in `Production/Backend/tests` and require a disposable configured database. The experimental Neon scaffold has `node --test Experiments/neon-auth-spike/handler.test.mjs` tests.

## Attribution and security

See `Production/ProgramCore/ATTRIBUTION.md` for the training-plan source and Open Government Licence attribution. No blanket open-source license is granted by this repository.

Only publishable client keys belong in the app; they are extractable from any distributed binary. Never use a service-role key, database password, or Apple private key. Database authorization must be enforced by RLS and authenticated RPC checks. Publishing this source is not a certification of the running backend's security.
