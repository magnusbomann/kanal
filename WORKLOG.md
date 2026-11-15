# Worklog & handoff — Kanal

**Read this file first, before touching anything.** It is the running memory for
this project. Every agent that works here reads it to get oriented and appends
to it before finishing. If you read only this file and `README.md`, you should
know enough to start.

- **What the project *is*, and how it works** → `README.md` (architecture, the
  product bet, every subsystem). This file does **not** repeat that — it points
  to it. Deep "why" questions are answered there.
- **What has *happened*, what is *in flight*, and what to do *next*** → this
  file, in the log below.

---

## How to work here (the contract)

1. **Log every session.** Before you stop, add a dated entry at the top of the
   **Session log** (newest first) using the template at the bottom. State what
   you changed, why, what you verified, and what you left unfinished or unsure.
   A future agent — or Magnus — reads this instead of re-deriving your work.
2. **Mark unverified work honestly.** Separate "done and verified" from "written
   but not run on real hardware/data". The README already uses **Verified** vs
   **Not yet verified**; keep that discipline. Never claim something passes that
   you did not run.
3. **Small, single-purpose commits** with plain-language messages (look at
   `git log --oneline` — the house style is "Make the player's buttons actually
   tappable", not "fix bug"). Commit only when the work is coherent; don't
   commit broken state without saying so in the message and here.
4. **Tests are the gate.** `cd Packages/KanalKit && swift test` must stay green.
   The localization lint runs as part of it — a missed string is a build error,
   not a review comment. Add tests for new behaviour.
5. **Don't break the localization rules.** Every user-facing string is a
   `LocalizedStringResource` in `KanalUI/Strings.swift` or
   `KanalCore/Strings.swift` — never a literal in a view. See README →
   Localization for the four traps this codebase already closed.
6. **Ask before irreversible or outward-facing actions** — publishing, sending,
   spending, deleting, changing account/signing settings. Magnus works in long
   autonomous stretches and reviews later, so *do* keep moving on code; but
   flag anything that leaves the machine.
7. **Language of this file:** English, to match the codebase and README, so any
   agent reading the repo is on familiar ground. (Magnus converses in
   Norwegian — that's fine; the written record stays English.)

---

## Current state — snapshot

_Last updated: 2026-08-26. Update this block whenever the big picture moves;
keep the blow-by-blow in the Session log._

**Repo:** `Kanal/` is the git repo (branch `main`, tracks `origin/main`).
`Site/` is the static marketing/support site, a sibling folder, **not** in this
git repo — treat it as a separate deliverable (see `Site/README.md`).

**Build & run**
- `xcodegen generate && open Kanal.xcodeproj` — iOS + tvOS targets, mostly thin
  shells over `Packages/KanalKit`.
- `cd Packages/KanalKit && swift test` — offline test suite + localization lint.
- Live tests are opt-in: `KANAL_LIVE_TESTS=1 swift test --filter LiveIntegrationTests`,
  and EPG: `KANAL_TEST_EPG_URL="<url>" swift test --filter LiveEPGTests`.
- First checkout also needs `./Scripts/fetch-vlc.sh` (Vendor/ is gitignored,
  ~525 MB) and `Config/Secrets.xcconfig` (optional TMDB key; empty is fine).

**Done & verified** (per README, confirm before relying on it)
- One-field setup, auto-organisation, forgiving/translated search, offline title
  packs (en, nb), TV guide with malformed-XML repair, localization machinery
  (en + nb ship), dual playback engine (AVFoundation + bundled VLC) with one
  shared control chrome.
- Consumer setup now validates before saving, preserves a working library on a
  bad addition, persists pasted input outside the reclaimable cache, and treats
  a multi-source TV handoff atomically. Search presents one channel/film/show
  in type sections; category and favourite routes retain their context.
- Home now answers what to watch next: one focused search entry, Continue
  watching, the actual next episode, favourite channels with now/next guide
  data, recent channels and stable recently-added film/show batches. History,
  episode caches and update snapshots stay with the active TV service.
- Home now also keeps a balanced editorial layer with top films, top series and
  locally available Netflix, Max/HBO and Apple TV+ picks. Films and Series are
  lightweight landing pages with top, new, service and category shelves; the
  complete provider catalogue is only materialised behind See all.
- Original milestone 1 is built: setup has plain-language progress, a broken
  saved service can be repaired without changing identity, the support report
  is redacted by construction, and common provider-link shapes are covered.
- Original milestone 3 is built with no Kanal account: secrets migrate to
  synchronisable Keychain and an AES-GCM-sealed private-iCloud snapshot syncs
  URL services, profiles, favourites, settings and watch progress.
- Builds and runs on iOS + tvOS; screenshots taken; Norwegian verified end to end.

**Written but NOT verified** (the honest edges — good places to pick up)
- **Handoff (phone→TV pairing)** — built, never run on two real devices.
  Bonjour/QR need real hardware; simulators don't exercise it.
- **Xtream panels** — `XtreamClient` written to the documented API, unit-tested
  for shape, but no live panel has ever answered it.
- **Automatic decoder handoff** — AVFoundation→VLC fallback, candidate walking
  and remembered channel variants have unit/build coverage, but the new path
  has not yet been re-run against a failing real-provider stream on hardware.
- **Apple-device sync** — deterministic two-device tests, entitlement checks
  and simulator builds pass, but no physical iPhone↔Apple TV iCloud/Keychain
  round trip has been run yet.
- **Before shipping** (from README): Wikimedia user-agent needs a contact URL,
  and iCloud KVS must be enabled for the production App ID.

**Original milestones — completed in the requested order**
- **Original milestone 1 — Ready on the first try:** software work complete;
  the physical pairing/decoder/provider pass remains in the manual acceptance
  round documented in `README.md`.
- **Original milestone 3 — Set up once, use everywhere:** software work
  complete using synchronisable Keychain + an encrypted private-iCloud
  snapshot; the physical two-device round remains.

**Later backlog** (from README "Next", not yet scoped)
- Catch-up, fast previous-channel switching and better subtitle discovery.
- Recordings, multi-view, per-profile favourites.
- More languages (machinery done; adding one is 3 steps + lint).

---

## Session log

### 2026-11-15 — Mac search crash, and streams that never started

- **Who:** Claude (Fable 5.2), with Magnus.
- **Goal:** Magnus reported the Mac app closing when searching and when
  leaving a film, and "nothing streams" lately. Fix and ship to TestFlight.
- **Did:**
  - **Search crash (Mac).** Three crash reports from build 202610311528, one
    stack: `UISearchController` activating inside the tab bar →
    `-[UIScreen _preferredFocusedWindow]` → `_screenBasedFocusUnsupported`
    assertion. UIKit bug for the iPad app on a Mac. On a Mac
    (`isiOSAppOnMac`) `SearchView` now draws its own field
    (`SearchField` / `SearchFieldSupport`) and the search tab drops
    `role: .search`. iPhone, iPad and Apple TV keep `.searchable` unchanged.
  - **Live TV gave up on a clock.** `LiveChannelSession` handed Apple's
    player to VLC after 3 s, declared the feed dead at 6 s, and stopped after
    3 feeds / 20 s — each step a new connection on a one-connection account.
    It now waits on evidence: the system player's own byte-based verdict, a
    20 s allowance for VLC, an 8 s stall limit once a picture has moved, a
    0.7 s settle between feeds, and a 60 s search window
    (`LiveStreamRecovery.searchWindow`). A status pill shows "connecting" /
    "trying another source" instead of a black screen.
  - **The provider's offline clip counted as success.** Measured today: a dead
    channel or film is answered with HTTP 200 and a 10 s, video-only MPEG-TS
    clip ("This channel is currently offline") from `/auth/…`. 11 of 20
    sampled Norwegian feeds, 0 of 30 random films, but 3 of the first 4 in the
    4K category. A feed is now only remembered as working after 12 s of play;
    VLC reports a live stream that ends as a failure; a film that opens with
    no sound and no length ≥ 2 min is reported through the new
    `AlternativePlayerRequest.onPlaceholder`, and `PlayerView` skips to the
    film's next listing or says it could not be started. The system player
    retries the clip only when a stream was released in the last minute.
  - `SystemPlaybackController` shows buffering while opening and releases its
    item on terminal failure instead of holding the connection paused.
  - `ExternalDisplaySceneDelegate` ignores external-display scenes on a Mac.
- **Verified:** `swift test` — 447 tests in 86 suites passed. Unsigned generic
  iOS and tvOS Debug builds succeed. The real `SystemPlaybackController`, run
  natively on macOS against the provider: seven live channels moving in
  0.9–1.2 s, the offline channel reported as `.providerPlaceholder`.
- **NOT verified:** nothing was run as the iPad app on the Mac — the Mac is
  not in the development profile and Apple refused to add it (see below), and
  the simulators are disabled on this machine (CoreSimulator out of date). So
  the Mac search field, the rewritten live session's UI, and VLC's
  placeholder detection are compiled and reasoned, not seen running. The
  "closes when leaving a film" crash left no report of its own; all three
  reports are the search stack, which a film opened from search would also
  hit on the way back — likely the same bug, not proven. The provider was
  fast today, so the slow-evening failure was not reproduced live either.
- **TestFlight:** uploaded as build 202611152022, iOS and tvOS, once Magnus
  had accepted Apple's new agreement (four earlier attempts were refused with
  `403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`).
- **Left open / for next agent:** After the TestFlight build installs,
  check on the Mac: search, play a film from search and close it, a live
  channel, an offline channel ("Discovery+ Extra 8"), and "Mad Max 2 4K
  (1981)" (dead on the provider today).
- **Commits:** ee74a8c, which also carries the download and AirPlay work
  that was already uncommitted in the tree.

### 2026-10-30 — Pre-release walkthrough on iPhone and Apple TV simulators

- **Who:** Claude (Opus 5.5), with Magnus.
- **Goal:** Walk the app on both simulators against the real test panel and
  find bugs worth fixing before release.
- **Did:** Fixed two bugs. (1) iPhone detail page: the artwork used
  `.aspectRatio(.fill)` inside a ScrollView, so a portrait poster (no
  backdrop) grew past the screen and sat behind title/buttons/text. Now a
  fixed 16:9 box the artwork fills (`TitleDetailView.backdrop`). (2) Channel
  grouping folded Norway's and Denmark's "TV 2" (and SE/DK "TV3") — same
  exact name on the panel — into one channel, so the guide interleaved both
  schedules and failover could land on the Danish feed. `ChannelNaming.
  countryScopedKeys` now splits a name only when its listings sit under two
  different countries; countryless categories join the dominant country so
  sport keeps its feeds. Two tests added in `ChannelGroupTests`.
- **Verified:** `swift test` — 437 tests in 84 suites passed. iOS and tvOS
  simulator builds; detail page checked on Besettelse and The Dark Knight;
  iPhone guide now shows only the Norwegian TV 2 schedule.
- **Follow-up, same day (Magnus: "fiks alle"):** Fixed the rest. Intro copy
  ("gjør bare kanalene du har, hyggelige å se på"). `SourceDetector` now
  requires a plausible ASCII host (dotted name with letter TLD, IPv4,
  localhost, IPv6) so keyboard-mangled links are unrecognized. Service rows
  ("Populært på Netflix/HBO Max/Apple TV") merged round-robin into one
  brand-free row, "Det alle ser på" (`DiscoveryMerge`), on Home, Films and
  Series; `shelf.onService` key removed. Low-bandwidth names ("NRK1 Lav
  Internett hastighet") fold into their channel and rank last. New
  `PlaybackFailure.providerPlaceholder`: a live item whose AVPlayerItem turns
  ready with a finite length under 2 min is the panel's offline clip; it
  advances to the next feed (one patient connection retry first) and is not
  handed to VLC. `AppModel.withoutUnusedOwner` drops an untouched default
  owner before merging a remote household that already has an adult.
  Status-bar fade over the tab view on iOS. tvOS manual-setup heading now
  asks "Ingen iPhone for hånden?" instead of repeating the button.
- **Verified (follow-up):** `swift test` — 442 tests in 85 suites passed.
  iOS + tvOS simulator builds. On iPhone: NRK1 Lav gone from the list, "Det
  alle ser på" row shown, status bar clean when scrolled.
- **Left open / for next agent:** Placeholder detection covers AVFoundation
  only; a live stream that goes straight to VLC would still play the clip.
  The placeholder path was not seen end-to-end: the test account allows one
  connection and every probe returned the clip. Duplicate-owner fix is unit
  tested, not tested against real iCloud. tvOS guide keeps its reserved
  220pt detail panel by design. Not walked: Pluss paywall, parental code,
  VOD playback, search. The KanalUI.xcstrings file was re-serialised by
  Python (same JSON content, committed `": "` style, keys sorted).
- **Commits:** none — left for Magnus to review with the other uncommitted work.

### 2026-10-30 — AirPlay for MKV films, smoother child profiles, TV focus

- **Request:** Child profile switch stuttered on Apple TV; audio/subtitle button in
  the top-right of the TV player was unreachable with the remote; iPhone could not
  AirPlay. Magnus chose the on-phone repackaging route for AirPlay ("must not be
  fragile, must not break existing playback").
- **Profiles:** a restricted profile's library (filter + full re-sort of ~400k
  entries) is now cut off the main actor, in `activate` and in each rating batch
  (`AppModel+Profiles.swift`, `catalogueRevision` guards against a stale cut).
- **TV focus:** `PlayerChrome` top bar and its trailing cluster are focus sections.
- **AirPlay:** `Remux/kanal_remux.c` + minimal FFmpeg 7.1.1 (LGPL, 2.8 MB) built
  by `Scripts/build-ffmpeg.sh` into `Vendor/KanalFFmpeg.xcframework` (gitignored;
  run once after cloning, builds in ~/Library/Caches because configure breaks on
  the space in "IPTV "). Exports only `kanal_remux_run`, so no clash with VLCKit's
  FFmpeg. MKV → HLS fMP4: video copied (H.264/HEVC only, hvc1-tagged), AAC/AC-3/
  E-AC-3 copied, anything else (DTS…) → AAC. `App/iOS/AirPlayRelay.swift` serves it
  over LAN (token path, 404 elsewhere) to an AVPlayer. The VLC controller switches
  only on a route change to an AirPlay receiver, for non-live films; any failure,
  a dropped provider mid-film, or a receiver that takes no picture (HomePod)
  hands the film back to VLC at the same position. Screen mirroring path
  (`ExternalDisplay`) kept as well.
- **Verified:** remuxer against synthetic MKVs (H.264+AAC, HEVC+B-frames+AC-3 5.1,
  H.264+2×DTS with language pick), from file and over HTTP with Range seeks;
  AVFoundation plays all outputs; Swift server/session tested on macOS end to end.
  iOS + tvOS build; 435 package tests pass; localization check passes.
- **Not verified:** a real provider film (fomo.re returned the same 4.4 MB
  10-second MPEG-TS placeholder for every VOD URL to this Mac during the session),
  and nothing on a real iPhone/Apple TV/AirPlay receiver. Subtitles are not
  carried over AirPlay.

### 2026-09-06 — Downloads, and a library you can take things out of

- **Who:** Claude (Opus 5), with Magnus.
- **Goal:** Download films and episodes for offline viewing on iPhone and Apple
  TV, give them a library of their own, and make favourites, downloads and
  Continue watching removable — long press on iPhone, as when rearranging apps.
- **Did:** New `DownloadStore` in Core (background `URLSession`, one download at
  a time, held back entirely while something is playing — the account allows one
  connection, so a download underneath a film takes the slot rather than merely
  slowing it). Records keep a whole `MediaItem`, so a file survives the provider
  rewriting its catalogue; files are saved as `.mkv` when the url says nothing,
  which is both what the panel serves and what routes them to VLC. An HTTP error
  or a file under 64 KB is a failure, not a film. Playback of a downloaded title
  is wired once, in `RootView`'s `alternatives` closure, so every screen that can
  play something plays the local file without knowing it exists. New
  `MyLibraryView` (Downloads · Favourites · Continue watching) reachable from a
  Home header button and from Settings — Home itself gets no downloads shelf, at
  Magnus's call: it is a nice-to-have, and Home belongs to what people want most
  nights — with per-row delete (swipe on iPhone,
  long press everywhere) and a clear-all at the foot of each section. Context
  menus added on Home: remove from Continue watching, remove a recent channel,
  download. `WatchState.forget/clearHistory/clearFavorites` and the matching
  `AppModel` methods do the removing, resolving the source-scoped history key and
  its alias so a film cannot come back after a playlist refresh changed its id.
  Deleting a TV service now deletes its downloads. 35 new strings, all 14
  languages.
- **Verified:** `swift test` — 435 tests in 84 suites, including 10 new ones for
  download bookkeeping and forgetting; `Scripts/check-localization.py` passed
  (484 keys). Signed generic iOS Simulator and tvOS Simulator Debug builds
  succeeded. On an iPhone 17 simulator in Norwegian, against a local M3U served
  from `127.0.0.1`: downloaded a title from the detail screen, saw it appear in
  the "På denne enheten" shelf and in My library with its real poster and size,
  saw it survive a relaunch, and opened it — playback started from the local
  file. Home was re-checked after the downloads shelf was removed. NOT verified: a real provider download (no credentials in that session,
  so the "film" was 3 MB of random bytes — the machinery is real, the content was
  not); anything on tvOS beyond compiling, since the simulator cannot be driven
  with a remote from here; a download that spans app suspension.
- **Left open / for next agent:** Downloads are free rather than a Pluss feature,
  following the rule that only household features are gated — worth a second
  opinion from Magnus, since offline viewing is the kind of thing people pay for.
  A download of a title a child profile may not watch is still blocked at the
  player, but appears in the grown-up's library list; that is correct today
  because My library sits behind the same code as Settings, but it is worth a
  test. tvOS keeps downloads in Caches because there is nowhere durable — the
  screen says so, but nobody has watched the system reclaim one.
- **Shipped:** `./Scripts/upload-testflight.sh both` — build `202609060839`,
  version 1.0, iPhone/iPad and Apple TV. Both archives passed the iCloud
  entitlement check and uploaded successfully.
- **Commits:** none — left uncommitted for Magnus to review, alongside the
  pre-existing uncommitted paywall changes.

### 2026-09-05 — Repair Apple TV QR bootstrap and ship both TestFlight apps

- **Request:** Fix QR discovery, missing profiles and empty TV content; upload iOS and tvOS to TestFlight. Deployment explicitly authorized in the conversation.
- **Changed:** Encrypted pairing now carries the household profiles/watch state, selected service, and pasted playlist contents alongside credentials. TV imports preserve source/profile identities, survive restart and repeated pairing, and acknowledge only after validation and throwing credential/storage writes. Cloud descriptors without credentials return to QR setup while retaining existing profiles. Late profile arrival no longer leaves an empty policy; remote child removal still requires profile selection.
- **Transport:** Publish QR only when the TCP listener is ready; use private LAN IPv4 fallback when Bonjour discovery fails; bound discovery/connection and import receipt waits separately. Preserve accepted connection through setup-screen teardown. Added iOS `kanal://pair` URL handling for system Camera scans.
- **Platform:** tvOS stores received credentials locally. Apple documents that tvOS does not synchronize app Keychain items through iCloud; QR is the credential bootstrap, while encrypted household sync continues to carry profiles and descriptors.
- **Verified:** iOS and tvOS simulator builds passed. Full package suite: 425 Swift Testing tests plus 3 XCTest tests passed, including localization lint, QR backwards compatibility, profile/favorite transfer and restart, credential-write failure, missing-credential recovery, and remote child-profile removal. Opt-in real LAN transport test also passed (3.281s): Bonjour intentionally mismatched, direct TCP fallback delivered the household and encrypted receipt even when the host screen stopped during import.
- **Limits:** No physical iPhone/Apple TV pair or the user's provider account was available for end-to-end playback verification. Existing unrelated working-tree changes preserved; no git commit/push.
- **Release verified:** Both iOS and tvOS uploaded as `1.0 (202609050923)`. App Store Connect API confirms both `VALID` and `IN_BETA_TESTING` (internal TestFlight). Archive iCloud entitlement checks passed on both platforms. Upload log: `/tmp/kanal-pairing-testflight.log`; final API response: `/tmp/kanal-asc-current.json`.

### 2026-09-05 — Keep QR-imported credentials usable on Apple TV

- **Who:** Codex (sync_fix).
- **Goal:** Fix Apple TV setup appearing empty after QR or device sync.
- **Did:** Updated `KeychainSourceCredentialStore` so newly added tvOS
  credentials are stored as local Keychain items. Apple’s
  `kSecAttrSynchronizable` flag does not provide iCloud Keychain sync on tvOS;
  the prior unconditional `true` did not make credentials arrive from iPhone.
  This does not prove locally written synchronizable items were unreadable. iOS/macOS behavior remains synchronisable,
  and reads continue to use `kSecAttrSynchronizableAny` for compatibility.
- **Verified:** `swift test --filter SecureSourceStorageTests` passed (3 tests);
  `git diff --check` passed. No tvOS hardware or TestFlight round trip was run.
- **Follow-up completed:** QR household transfer, import persistence and recovery
  are covered by the subsequent session entry above.


### 2026-09-05 — Make player close controls fully tappable and deterministic

- Reproduced the reported live-channel failure panel with a local dead-stream fixture. The shared primary and secondary capsule styles now define their full visible capsule as the hit target, covering 33 existing uses across setup, profiles, playback, details, pairing and purchase screens.
- Live and recorded player close actions now stop their playback engines, cancel player tasks, clear `Navigator.playing`, and then dismiss. The live failure panel exposes stable accessibility identifiers for Retry, Choose stream and Close.
- Added a UI regression that taps near the edge of the Close capsule rather than its text and verifies both the panel and full-screen player disappear. It passed on the iOS 26.5 simulator. Final package suite passed: 416 tests in 80 suites. tvOS simulator build passed. `git diff --check` passed.
- Logs: `/tmp/kanal-close-ui.log`, `/tmp/kanal-close-tests.log`, `/tmp/kanal-close-tv.log`. No real provider, purchase or deployment was used.

### 2026-09-05 — Created every paid product in App Store Connect

- **Who:** Claude (Opus 5), with Magnus.
- **Goal:** Make paying actually work. The code was finished, but *no* products
  existed at Apple — `Product.products(for:)` came back empty, so the paywall
  rendered without prices and nobody could buy anything.
- **Did:** Everything through the App Store Connect API using the key already in
  `~/.appstoreconnect/`, not the web UI. Weighed RevenueCat and dropped it:
  Kanal has no server, no account and a single entitlement, so the StoreKit 2
  code in `PurchaseStore` is already correct, and another SDK would only put a
  third party between a customer and the thing they paid for.
  - Subscription group "Kanal Pluss" (`22360622`).
  - `…pro.monthly` (`6808904010`), `…pro.yearly` (`6808903782`),
    `…pro.lifetime` (`6808904056`) — all family-shareable, all 175 territories.
  - 14 languages × 4 objects = 56 localizations, matching the app's own set.
  - **Strategic pricing, not currency conversion.** Apple's own equalization
    from NOK/USD produced ₹499/month in India and ₺249.99 in Turkey — dearer
    than the US. Replaced with three purchasing-power tiers, each equalized from
    a different USD anchor: A (list, 4.99/29.99/69.99), B ≈ 70 % (27
    territories), C ≈ 45 % (95 territories). Norway, Sweden and Denmark are set
    by hand (39/249/599 NOK).
  - Seven-day free trial on yearly — the API demands one call per territory.
  - Review screenshot: the paywall run in the simulator with `-kanal-paywall`,
    uploaded against all three products.
- **Verified:** Read back from the API afterwards. All three products are
  `READY_TO_SUBMIT`, each with 175/175 prices and 14/14 languages, and the
  yearly free trial is live in 175/175 territories. **Not verified:**
  that a real purchase completes. That needs a TestFlight or sandbox build with
  a sandbox account, and cannot be exercised from the simulator.
- **Left open / for next agent:**
  - Confirm the Paid Applications agreement is active in App Store Connect. If
    it is not, products never load no matter what this entry says.
  - Run a sandbox purchase of each of the three, plus a Restore Purchases.
  - The products go to review alongside the next app version.
  - `Config/Kanal.storekit` still carries its own internal IDs; it only drives
    simulator runs and does not affect production.
- **Commits:** none — no code change was needed.

---

### 2026-09-05 — Complete Apple TV design fixes

- User authorized the full design-review list and economical models. Used three bounded GPT-5.6-Luna agents for setup, guide, and player; parent reviewed and corrected integration before building.
- Added TV typography minima, contrast fixes and focus outlines/sections; moved See all beside shelf headings, simplified home, and assigned detail Play focus. Added visible live-player favorites, single-screen QR/manual setup, guide focus information and now navigation, accelerated confirmable/cancellable seeking, and calmer TV purchase pacing.
- Parent corrected focus opening guide sheets, unsupported conditional argument syntax, missing play focus, player focus styles/initial auto-hide, optional closure syntax, repair-vs-pairing routing, layout widths, iOS MoveCommandDirection availability, and test macro mutation handling.
- Both current tvOS and iOS simulator builds passed. Package tests: 416 Swift Testing + 3 XCTest passed, including localization and new seek/pacing tests. Diff whitespace check passed.
- Visually verified TV setup (Audit/apple-tv-design/setup-after.png). Further end-to-end library/player inspection was limited by the ad-hoc simulator environment; explicit limitations are recorded in Audit/APPLE_TV_DESIGN_REVIEW.md. Temporary simulator entitlements were tried only on local build products, then removed. No project signing/account configuration changed.
- No source commits, deployment or publication. Preserved all existing unrelated dirty work. Physical TV/remote and two-device pairing remain manual acceptance work.

### 2026-09-05 — tvOS player focus and seeking

- **Who:** Codex (GPT-5), delegated player work.
- **Goal:** Make Apple TV player remote navigation focus-aware and seeking usable.
- **Did:** Removed the parent-level left/right skip handler. Added a focusable tvOS
  video surface, explicit control/timeline focus, pending timeline seeks with
  accelerating long-distance nudges, select-to-commit and Back-to-cancel. Back
  now hides controls before closing, and auto-hide defers while focus, a track
  sheet or a pending seek is active. Bound play focus, preserved button focus
  after activation, and extracted the bounded reversal/pause-aware seek policy
  into `TelevisionSeekState` with core regression tests. iOS scrub gestures and
  the shared playback protocol remain unchanged.
- **Verified:** Source inspection and `git diff --check` only. No builds or tests
  run because other agents are editing concurrently, per task contract.
- **Left open:** tvOS focus behavior and Siri Remote event delivery remain to be
  exercised by the parent build on simulator/hardware. No new localization keys.
- **Commits:** none — shared dirty worktree preserved.

### 2026-09-05 — Consolidate Apple TV setup into one screen

- **Who:** Codex (tv_setup).
- **Goal:** Make Apple TV setup spacious and phone-first while preserving manual setup, repair, validation, and pairing feedback.
- **Did:** Routed tvOS onboarding directly to `WelcomeView`, embedded the QR pairing surface above a secondary manual URL section, added a close action that stops the single pairing host when hidden, and kept import errors/progress visible through completion.
- **Verified:** `git diff --check` passed for the three owned views. No builds or tests run, per task instruction; physical pairing remains unverified.
- **Left open:** Parent should add localized keys `pairing.close`, `pairing.showQR`, `pairing.manual.title`, and `pairing.manual.body` to the catalog/resources.
- **Commits:** none.

### 2026-09-05 — Apple TV design audit

- Reviewed current UI implementation and inspected the home screen in the 1080p tvOS simulator. Wrote Audit/APPLE_TV_DESIGN_REVIEW.md with prioritized recommendations and explicit evidence limits; saved a home screenshot.
- Main findings: unscaled 10–16 pt supporting text, low contrast in white-on-coral actions, focus-navigation risks across short shelves, and TV seeking limited to ten-second command steps without an interactive timeline.
- Current tvOS Debug simulator build succeeded using build/design-review. Ad-hoc signed local build products after unsigned simulator launch failed code-signing validation. No signing settings changed.
- No application source changes. No core tests run for this documentation-only audit. Physical Siri Remote, full playback and pairing flows remain unverified; preserved existing dirty work.

### 2026-09-05 — Consolidated launch-fix verification

- User authorized tests/builds after implementation. Final Swift package suite: 415 tests in 80 suites passed; localization check passed for all 423 keys. Added regression coverage for original audit failures, child profile removal/expansion during sync, replica convergence and persisted tombstones, authenticated receipt tampering, and empty Xtream live stage.
- Fixed Swift 6 Sendable constraint on PairingHost.TimeoutGate and stopped request reads after import begins so EOF cannot cancel its receipt. iOS and tvOS simulator builds succeeded.
- ProNudge UI run failed before assertions with CODESIGNING Invalid Page in dyld. Both local Vendor simulator VLC frameworks failed codesign verification, while embedded copies could be signed correctly. Repaired ad-hoc simulator signatures; device slices unchanged. No real purchase or deployment. Final clean iOS UI retest passed: OnboardingAccessibilityUITests verifies launch, scroll reachability of Continue at accessibility XXXL, and navigation to the second page. Log /tmp/kanal-onboarding-final.log; result /tmp/kanal-followup-ui-clean2/Logs/Test/Test-Kanal-2026.09.05_08-11-52-+0200.xcresult. The initial test assertion incorrectly required the button visible before scrolling; corrected that assertion and retained the passing test. ProNudge playback/paywall flow still requires its local stream fixture.
- Logs: /tmp/kanal-followup-final-tests.log, /tmp/kanal-followup-regressions.log, /tmp/kanal-followup-ios.log, /tmp/kanal-followup-final-tv.log. Real multi-device iCloud/pairing, provider playback, and StoreKit end-to-end remain outside these automated results.


### 2026-09-05 — Implement launch-review fixes; validation deliberately deferred

- User authorized all ten launch-review fixes and explicitly requested economical subagents and implementation before further testing. Used three bounded GPT-5.6-Luna agents for pairing/import, playback/purchase/legal, and typography/guide; parent integrated sync, credentials and profile safety.
- Implemented persistent per-field replica versions/tombstones, cloud history redaction with local resolution, v3 snapshot migration, safe profile reselection, progress checkpoints, VOD-only first import fallback, acknowledged pairing with bounded import, semantic Dynamic Type, grouped guide playback, partial StoreKit offers/free-trial handling, bundled legal documents, and uptime privacy reasons.
- Reviewed integration statically, including credential-load failures, cancellation before import commit, pairing screen teardown before acknowledgment, and timeout-gate locking. No tests, builds, or hardware validation run for this follow-up, as requested. Earlier 403-test baseline does not validate these edits.
- Updated LAUNCH_REVIEW.md with implementation status and the consolidated test queue. Public policy domain/contact remains unresolved; native legal fallback and the local Site privacy copy were updated, but nothing was deployed. iCloud credentials use synchronizable Keychain, separate from redacted household metadata. Update all devices before v3 multi-device checks.
- Existing unrelated dirty work preserved. No commits or publishing.


_Newest first. Copy the template below for each new entry._

### 2026-09-05 — Launch audit and family trust fixes

- **Who:** Codex.
- **Goal:** Review launch readiness and define the product mission for ordinary
  viewers and families.
- **Did:** Added `LAUNCH_REVIEW.md` with the proposed mission, prioritized
  findings, evidence limits and release acceptance criteria. Gated adult
  profile selection through the existing parental challenge; filtered cached
  on-demand episodes at the current-profile read boundary; preserved legacy
  credential descriptors when Keychain migration/persistence fails; changed
  Keychain credential replacement to update-before-add instead of delete-first.
  Added three normal regression tests. Independently reproduced loss of local
  favourites during remote sync and credentials inside cloud history payloads;
  retained the two failing diagnostic probes under `Audit/SyncAuditProbes.swift`,
  outside the normal suite. These two bugs remain open.
- **Verified:** Final normal suite: 403 tests in 77 suites passed, including
  localization. Three new launch regressions passed. Both separate sync probes
  failed on the expected assertions. Final signed Debug iOS/tvOS Simulator
  builds passed; both simulator bundles passed deep strict signature checks.
  Launched Norwegian onboarding on a fresh iPhone 16e simulator and confirmed
  that maximum Dynamic Type did not enlarge its body text. `git diff --check`
  passed. Payment URLs failed DNS resolution from this environment.
- **Left open / for next agent:** Follow the prioritized launch review. No real
  devices, StoreKit sandbox, live provider, complete screen-by-screen UI round
  or physical iCloud sync were exercised. Playback files were being changed
  concurrently by other work; those edits were left alone. Their new
  `systemUptime` usage also needs a matching privacy-manifest declaration.
  Test counts include concurrent work; do not attribute the whole increase to
  this audit. Recommend TestFlight continuation, not broad launch yet.
- **Commits:** none — the existing shared dirty worktree was preserved.

### 2026-08-30 — Keep iCloud entitlement in TestFlight distributions

- **Who:** Codex (GPT-5).
- **Goal:** Diagnose why “Synchronise now” reported that iCloud was unavailable
  on a physical iPhone even though the project contained iCloud entitlements.
- **Did:** Traced the failure to the release pipeline rather than the sync
  store: TestFlight build `202608301309` had only the application/team/beta
  entitlements because the upload script archived wholly unsigned, so Xcode
  had no requested KVS entitlement to preserve when it distribution-signed the
  export. Changed the script to create a provisioned, signed iOS archive. tvOS
  still needs an unsigned archive because the team has no registered Apple TV,
  so that path now ad-hoc signs the archive with the concrete requested KVS
  entitlement before export. Added a hard pre-upload check that refuses any
  archive without `com.apple.developer.ubiquity-kvstore-identifier`.
- **Verified:** A signed generic iOS archive succeeded using the configured App
  Store Connect credentials. Its code signature contains
  `JWL8576LU4.com.bomann.kanal`, and its embedded provisioning profile permits
  the KVS entitlement. `bash -n Scripts/upload-testflight.sh` passed. Build
  `202608301323` and `202608301349` stopped safely before upload because the
  first guards parsed codesign's output incorrectly (stderr and dotted plist
  key-path handling). The final guard extracts the XML portion and escapes the
  entitlement key; it directly returned `JWL8576LU4.com.bomann.kanal` against
  the signed archive. iOS build `202608301402` was accepted by App Store
  Connect with “Upload succeeded”. The first tvOS export lost its network
  connection; the retry, tvOS build `202608301408`, was also accepted with
  “Upload succeeded”. Both archives passed the KVS entitlement guard first.
- **Left open / for next agent:** Install iOS build `202608301402` after App
  Store Connect finishes processing and press Synchronise now on physical iPhone.
  Then confirm propagation on a second Apple device. If upload fails, inspect
  the export log; do not revert to a wholly unsigned archive.
- **Commits:** none — retained in the existing uncommitted worktree.

### 2026-08-30 — Responsive settings, native TV details and reliable iCloud updates

- **Who:** Codex (GPT-5).
- **Goal:** Repair the cramped iOS/tvOS settings and title-detail UX shown in
  Magnus's photos, remove settings lag, make private Apple-device sync react
  reliably, and diagnose a repeatedly reported tvOS crash.
- **Did:** Replaced the one-size-fits-all audio selector with a narrow-width
  iOS menu and a focusable, horizontally scrolling tvOS control whose complete
  language names remain readable. Moved tvOS settings, profile/PIN flows and
  title details from narrow sheets to full-screen presentations. Rebuilt the
  tvOS title screen as a full-width cinematic hero with TV-sized metadata,
  play/favourite actions, overview, cast and episodes. Cached and moved the
  expensive profile category/withheld-title derivation off SwiftUI's render
  path, with debounced recomputation after policy changes. Changed household
  sync to a versioned non-secret iCloud KVS envelope while leaving provider
  URLs and credentials in synchronizable Keychain, migrates the legacy
  per-device-encrypted value, and listens for external KVS notifications while
  the app is active. The supplied crash report was dyld `CODESIGNING Code 2`
  from an intentionally unsigned simulator artifact, not an app-code crash;
  rebuilt and reinstalled a normally signed artifact.
- **Verified:** `swift test` — 391 tests in 75 suites passed, including private
  Apple-device sync and localization. Signed iOS Simulator and tvOS Simulator
  Debug builds passed, and both bundles passed
  `codesign --verify --deep --strict`. The signed tvOS app was installed and
  launched on Apple TV 4K at 1080p; settings and the new title detail were
  visually inspected. The final settings capture shows full-screen layout and
  complete labels such as “Originalspråk” and “Norsk Bokmål”. The app remained
  alive on repeat launch.
- **Left open / for next agent:** Exercise iCloud propagation on two physical
  Apple devices signed into the same account; Simulator cannot prove the
  production iCloud container/account path. Measure profile-editor frame time
  with a real provider-sized catalogue on physical iOS/tvOS hardware.
- **Commits:** none — kept uncommitted for Magnus to review alongside the
  existing dirty worktree.

### 2026-08-26 — Ready first, then private Apple-device sync

- **Who:** Codex (GPT-5).
- **Goal:** Complete original milestone 1 and then original milestone 3, leaving
  real provider, physical playback/pairing and real-iCloud flows for a separate
  manual pass.
- **Did:** Added a plain-language connection checklist to setup and loading.
  Failed saved services now offer Retry and Change details; replacement
  validates before commit and keeps the source id, history and favourites.
  Added a user-inspectable support report containing only app/system state,
  counts, provider host and diagnostics — never paths, queries, credentials,
  content or profile names — plus an offline acceptance matrix for nine link
  families and mixed live/film/series data. Then split service descriptors from
  secret Keychain payloads, including automatic plaintext-JSON migration.
  Added a synchronisable AES key, AES-GCM encrypted private-iCloud household
  snapshots, launch/foreground/coalesced/manual sync, Settings status,
  per-profile state transfer and iOS/tvOS KVS entitlements. The chosen model has
  no Kanal account or backend. Local imported files and the parental code stay
  device-local for explicit size/security reasons.
- **Verified:** `swift test` — 308 tests in 60 suites passed; localization lint
  passed with all 404 keys declared and translated; XcodeGen regenerated the
  project; signed generic iOS Simulator and tvOS Simulator Debug builds passed;
  app and embedded VLC frameworks passed strict code-signature verification.
  The simulator build carried the expected iCloud KVS entitlement, installed
  and stayed alive on iPhone 17 Pro. A seeded service reached Settings; the sync
  section was visually inspected in Norwegian. Its real `sources.json` was
  inspected and contained no playlist/guide URL, username or password.
  Relaunching without the debug seed restored that redacted service from
  Keychain and rebuilt the Home library successfully.
- **Left open / for next agent:** Run `README.md` → Manual acceptance round on
  physical iPhone/Apple TV and 5–10 real provider shapes. Enable iCloud KVS for
  the production App ID before the first device/archive build.
- **Commits:** none — the shared working tree already contains the preceding
  product tranches and remains uncommitted for Magnus to review together.

### 2026-08-26 — Finish and polish Kanal Pluss purchasing

- **Who:** Codex (GPT-5).
- **Goal:** Find the in-flight payment work and continue it into a clean,
  UHF-calibre purchase experience without disturbing the larger uncommitted
  consumer-experience tranche.
- **Did:** Kept the existing StoreKit 2, free-tier watermark and paced post-play
  offer architecture. Refined the Pluss screen with explicit billing periods,
  a real annual saving calculated from App Store prices, a visible loading and
  retry state, purchase progress, a direct close action, and required Terms and
  Privacy links. Purchase handling now rejects expired entitlements, reports a
  missing product, and surfaces restore failures instead of silently swallowing
  them. The screen stays compact on iPhone and gets a sofa-readable width on
  tvOS. English and Norwegian catalogs and generated resources were updated.
- **Verified:** `swift test --package-path Packages/KanalKit` — 303 tests in 58
  suites passed, including localization lint and all purchase-nudge tests.
  Signed iOS Simulator Debug build passed; the Norwegian paywall was installed,
  launched and visually inspected on iPhone 17 Pro. `git diff --check` passed.
  A full tvOS Simulator build reached the project but is currently blocked by
  the unrelated in-flight `HouseholdSnapshot` Equatable conformance in
  `HouseholdSync.swift`, not the purchase files.
- **Left open / for next agent:** Configure the same three product IDs, prices,
  trial and Family Sharing in App Store Connect; then test purchase, restore,
  renewal/lapse and family sharing with sandbox Apple IDs and on physical iOS
  and Apple TV hardware. Re-run the tvOS build after the household-sync type
  compiles there.
- **Commits:** none — left with the existing uncommitted tranche for Magnus to
  review.

### 2026-08-26 — Editorial Home and scalable Films/Series landings

- **Who:** Codex (GPT-5), with focused discovery, performance and UX review
  agents.
- **Goal:** Restore useful TMDB service rows, guarantee both films and series on
  Home, and replace the eager all-catalogue Film/Series tabs with clean,
  consumer-friendly landing pages.
- **Did:** Replaced Home's response-order `prefix(2)` with an explicit
  presentation model for top films, top series and mixed service spotlights.
  Netflix, Max/HBO and Apple TV+ are recognised deliberately, while rows only
  contain titles the active provider actually carries. Rebuilt Films and
  Series around continue/next, favourites, recently added, top, new, service
  and category shelves; full libraries and filters now live behind See all and
  mount incrementally. Discovery fetches run concurrently, preserve good cached
  rows through partial network failures and use flat-rate provider results.
  Ranking, filtering, search-index work and full-list sorting moved off the UI
  actor with cancellation and bounded top-K previews for very large libraries.
  Also separated navigation history per tab, fixed the Other category, cached
  favourites, and clear stale details/recommendations immediately when a
  profile or service changes.
- **Verified:** `swift test` — 299 tests in 56 suites passed; localization lint
  passed with all 370 keys declared and translated; `git diff --check` passed.
  Signed generic iOS Simulator and tvOS Simulator Debug builds passed, including
  strict deep verification of each app and strict verification of embedded
  MobileVLCKit/TVVLCKit. Home, Films and Series were visually inspected against
  a seeded local catalogue. The final iOS build was reinstalled and remained
  alive on an iPhone 17 Pro simulator, confirming the former pre-main VLC
  signature crash is absent.
- **Left open / for next agent:** Validate the editorial mix and Apple TV remote
  focus against a large real provider catalogue. Then start original milestone
  1; keep original milestone 3 queued behind it as requested.
- **Commits:** none — left uncommitted for Magnus to review with the preceding
  consumer-experience work.

### 2026-08-24 — Home 2.0: answer what to watch now

- **Who:** Codex (GPT-5), with a focused read-only review subagent.
- **Goal:** Build the requested Home 2.0 while preserving the original
  milestones 1 and 3 as the next work, in that order.
- **Did:** Rebuilt Home around one clear question and one entry into the real
  grouped search. Added source-scoped continue/history snapshots, one resume
  per show, real next-episode resolution (including mismatched Xtream names),
  favourite channels with now/next data from every fallback feed, recent
  channels recorded only after successful playback, and stable recently-added
  film/show batches that survive rotating stream tokens and expire after 14
  days. Continue-watching progress also follows a film when a signed M3U URL
  gives it a new technical id. Home resolution now uses a sparse library index
  instead of rescanning a
  400,000-item catalogue on every progress update. Episode caches are cleared
  on service changes. Home keeps at most two discovery rows; category browsing
  lives in Direct/Films/Series. The original milestones 1 and 3 are recorded
  above rather than being started out of order.
- **Verified:** Localization resources regenerated; `swift test` — 279 tests
  in 53 suites passed; signed generic iOS Simulator and tvOS Simulator Debug
  builds passed; both app bundles passed strict deep code-signature checks.
  The final iOS build was installed and launched in Norwegian on a fresh
  iPhone 17e simulator; the narrow Home header, search entry and five-tab shell
  were visually inspected. No launch crash occurred.
- **Left open / for next agent:** Exercise every populated Home shelf against a
  large real provider with real EPG data and verify focus/remote behaviour on a
  physical Apple TV. Then start original milestone 1; keep original milestone
  3 queued behind it.
- **Commits:** none — left uncommitted for Magnus to review with the preceding
  consumer-experience tranche.

### 2026-08-24 — First consumer-experience quality tranche

- **Who:** Codex (GPT-5), with focused playback, source and search subagents.
- **Goal:** Start building toward a Netflix-simple experience without exposing
  M3U/Xtream vocabulary, while first keeping the simulator launch stable.
- **Did:** Kept setup to one TV-service link and replaced protocol copy with
  plain-language guidance; added inline repairable errors, adaptive layout and
  a scroll-safe sign-in sheet. Source additions now validate before mutation,
  pasted text survives cache eviction, phone→TV batches are atomic, and load
  generations stop stale refresh/guide/episode results replacing a newer
  library. Playback now hands media failures from AVFoundation to VLC, walks
  every provider/fallback candidate, and remembers the channel variant that
  worked. Search indexes one representative per channel/film/show, groups the
  UI into Live/Films/Series, opens complete series, retains channel fallbacks,
  preserves category/favourite routes, and orders tabs Home · Live · Films ·
  Series · Search.
- **Verified:** `./Scripts/build-localizations.py`; `swift test` — 260 tests in
  49 suites passed (opt-in live/internet suites skipped); signed generic iOS
  Simulator and tvOS Simulator Debug builds passed; both app bundles passed
  `codesign --verify --deep --strict`; the final iOS build was installed and
  launched in Norwegian on a fresh iPhone 17 simulator and remained alive.
  Onboarding and Home were visually inspected in simulator screenshots.
- **Left open / for next agent:** Re-test automatic VLC handoff with a real
  failing provider stream and pairing on two physical devices. A startup
  failure from an already-saved source still offers Retry rather than a second
  “change TV service” recovery action.
- **Commits:** none — the coherent changes are intentionally left for Magnus to
  review alongside the pre-existing README/worklog additions.

### 2026-08-24 — Set up this worklog

- **Who:** Claude (Opus 4.8), with Magnus.
- **Goal:** Give a second AI a single entry point so it can get oriented and
  continue the work without re-deriving everything.
- **Did:** Surveyed the repo (no prior worklog existed — only the two READMEs).
  Created this file as the handoff + running log. Captured the current-state
  snapshot from `README.md`, `git log`, and a clean working tree at commit
  `acc925d` (2026-08-23).
- **Verified:** Facts in the snapshot are transcribed from the README and git
  state, not re-tested. The "Written but NOT verified" list is copied from the
  README's own "Not yet verified" / "Before shipping" sections — still true.
- **Left open / for next agent:** Nothing broken. Natural next pieces are the
  three unverified edges above (handoff on hardware, a live Xtream panel, the
  pre-ship attribution/user-agent items). Confirm the snapshot still matches
  `git log` before trusting it.

---

## Entry template (copy this)

```markdown
### YYYY-MM-DD — <one-line summary>

- **Who:** <model / person>
- **Goal:** <what you set out to do>
- **Did:** <what actually changed — files, behaviour, decisions and why>
- **Verified:** <what you actually ran: `swift test`, on-device, live test —
  and what you did NOT verify>
- **Left open / for next agent:** <unfinished work, known risks, open questions>
- **Commits:** <hashes or "none — left uncommitted because …">
```
