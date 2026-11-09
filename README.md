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
- Follow the [backend notes](Production/Backend/README.md) for authentication, access controls, and known limitations.

### 3. Turn up the heat

```sh
cd Production/App
xcodegen generate
open FrenchFried.xcodeproj
```

Select your signing team and a device or simulator in Xcode, then build and run.

**A note on voice:** the [cue scripts](Production/Voice/zoe-cues.json) are included; generated recordings are kept out of this repository pending confirmation of redistribution rights. Without those files, voice cues are silent. The rest of the app remains available.

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
