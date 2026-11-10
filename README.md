<div align="center">

<img src="Production/App/Sources/Assets.xcassets/WelcomePotato.imageset/stage-1.png" alt="French Fried potato mascot" width="240" />

# French Fried

### From couch potato to hot potato.

A running app for people whose natural habitat is the couch.<br />Nine weeks. One run at a time. A little attitude along the way.

**SwiftUI · iOS 26+ · Live Activities · Supabase**

[What's inside](#a-little-less-couch-a-little-more-cardio) · [Run it yourself](#serve-locally) · [Under the hood](#ingredients)

</div>

---

## A little less couch. A little more cardio.

Getting into running is hard enough. French Fried gives you a session to follow, a place to see your progress, and a potato to keep you company.

| | On the menu |
| :--- | :--- |
| 🥔 **Start where you are** | A nine-week, 27-session Couch to 5K program with warm-ups, run/walk intervals, and cool-downs. |
| 🏃 **Go off-menu** | Free runs when you want to head out without intervals. Track time, distance, and your route. |
| 🔒 **Keep your phone locked** | Follow your run with Live Activities on the Lock Screen and Dynamic Island. |
| 🗺️ **Look back at the miles** | Saved runs, route maps, and program progress. |
| 🍟 **Bring your people** | Create or join a running group with invite codes. |
| 🔊 **Add some seasoning** | Optional voice guidance and haptic cues. Both start off; you choose the noise level. |

> **“Done! You crispy legend.”**<br />
> — an actual line from the voice-cue script

The program builds toward **30 minutes of continuous running**, not a guaranteed five-kilometre distance. Take rest days. Repeat sessions when you need to. The potato isn't going anywhere.

## Serve locally

You'll need **Xcode with the iOS 26 SDK or newer**, **XcodeGen**, your own **Supabase project**, and an **Apple development team** for signing and Sign in with Apple.

### Just here to run with a friend?

Version 1.0 (build 5) was submitted to App Review on November 10, 2026. Once it is approved, install it on an **iPhone with iOS 26+**, sign in with your own **Apple Account**, and join your friend's crew with their invite code. The app connects to the hosted backend automatically. You need neither a developer account nor any secret keys.

[App website](https://frenchfried.monkhai.dev) · [Support](https://frenchfried.monkhai.dev/support) · [Privacy](https://frenchfried.monkhai.dev/privacy)

### 1. Set the table

```sh
git clone https://github.com/monkhai/french-fried.git
cd french-fried
cp Production/App/Local.xcconfig.example Production/App/Local.xcconfig
```

Fill in `Production/App/Local.xcconfig` with your project URL, **publishable** client key, and Apple team ID. Keep the `https:/$()/` URL syntax from the example: it prevents xcconfig from treating `//` as a comment. This file is ignored by Git.

### 2. Bring your own backend

- Set your own bundle identifiers in [`Production/App/project.yml`](Production/App/project.yml) and configure Sign in with Apple for them.
- Apply the [SQL migrations](Production/Backend/supabase/migrations) to your Supabase project in filename order.
- Deploy the `delete-account` Edge Function from that directory. It authenticates the caller through Supabase Auth before deleting only their account; keep its service-role key on the server. See the backend notes for configuration.
- Follow the [backend notes](Production/Backend/README.md) for authentication, access controls, and known limitations.

### 3. Turn up the heat

```sh
cd Production/App
xcodegen generate
open FrenchFried.xcodeproj
```

Select your signing team and a device or simulator in Xcode, then build and run.

**A note on voice:** the [cue scripts](Production/Voice/zoe-cues.json) and recordings are included with confirmed redistribution permission. Optional voice cues include strong language and start off by default.

## Ingredients

Small Swift packages handle the core behavior; the app brings them together.

| Location | Responsibility |
| :--- | :--- |
| [`Production/App`](Production/App) | SwiftUI screens, session state, run guidance, and Live Activities |
| [`Production/ProgramCore`](Production/ProgramCore) | Training plans, interval timing, and phase-cue policy |
| [`Production/RunTracking`](Production/RunTracking) | Location tracking and run recording |
| [`Production/AppleSignIn`](Production/AppleSignIn) | Native Apple sign-in and nonce handling |
| [`Production/Backend`](Production/Backend) | Supabase migrations, access policies, and SQL tests |
| [`Experiments/neon-auth-spike`](Experiments/neon-auth-spike) | An isolated auth experiment; not part of the production app |

## Check the crispiness

From the repository root:

```sh
swift test --package-path Production/ProgramCore
swift test --package-path Production/RunTracking
node --test Experiments/neon-auth-spike/handler.test.mjs
```

[Backend security tests](Production/Backend/tests) require a disposable configured database. The Neon tests use fake verification and storage; they don't validate a deployed authentication flow.

## The fine print, lightly salted

**Keep local things local.** Configuration, signing files, generated Xcode projects, build output, prototypes, and internal review captures are excluded from Git.

**Client keys aren't secrets.** Only Supabase publishable keys belong in the app. Service-role keys, database passwords, and Apple private keys do not. Database access must be enforced through RLS and authenticated RPC checks; public source is not a certification of a deployed backend's security.

**Give credit.** The training plan's provenance and Open Government Licence attribution are documented in [`ATTRIBUTION.md`](Production/ProgramCore/ATTRIBUTION.md). No blanket open-source license is granted by this repository.

---

<div align="center">

**Ready when you are, spud.** 🥔

</div>

## App Store release tooling

The release workflow uses [ASC](https://github.com/rorkai/App-Store-Connect-CLI) for App Store Connect and [Goldie](https://github.com/software-mansion-labs/goldie) for screenshots. Local setup currently uses ASC 6.6.0 and Goldie 0.5.0.

```sh
# Build a signed device archive using the ignored Local.xcconfig.
BUILD_NUMBER=5 scripts/archive-app.sh

# Export for the App Store. Supply your own team ID.
APPLE_TEAM_ID=YOURTEAMID scripts/export-app.sh 5

# Authenticate ASC locally first; never commit its API private key.
# Upload only after completing release readiness checks.
ASC_APP_ID=YOUR_APP_ID scripts/upload-app.sh release/output/app-store-5/FrenchFried.ipa
```

`upload-app.sh` expects ASC at `.tools/asc`, or an executable path in `ASC_BIN`. It uploads and waits for processing; it does not submit for review or release the app. Archives, IPAs, CLI authentication, and local release files are ignored by Git.

Store copy is drafted in [`release/store-metadata.json`](release/store-metadata.json). Its unresolved fields document remaining verification limitations. The live support/privacy pages, account deletion, reviewer contact, age rating, medical-device declaration, and listing metadata are configured. Build 5 has been submitted for App Review. Real Apple sign-in and on-device running still need release verification. The native ID-token flow does not retain Apple refresh/access tokens; after deleting account data, the app follows Apple TN3194 by showing manual Sign in with Apple revocation instructions.

Goldie's configuration is in [`goldie/goldie.config.ts`](goldie/goldie.config.ts). Build a Release simulator app into `release/output/simulator`, then run:

```sh
GOLDIE_CONFIG="$PWD/goldie/goldie.config.ts" npx -y goldie@0.5.0 doctor
GOLDIE_CONFIG="$PWD/goldie/goldie.config.ts" npx -y goldie@0.5.0 capture
GOLDIE_CONFIG="$PWD/goldie/goldie.config.ts" npx -y goldie@0.5.0 frame
GOLDIE_CONFIG="$PWD/goldie/goldie.config.ts" npx -y goldie@0.5.0 verify
```

The initial flow captures the production welcome screen. Authenticated screenshots must use a dedicated test account and avoid personal routes and invite codes. The welcome screenshot has completed App Store Connect processing. The app uses light appearance consistently, including when the device is in dark mode.
