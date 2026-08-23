# Kanal

A native IPTV player for iPhone, iPad and Apple TV. App Store name:
**Kanal: IPTV Player**.

Kanal is a *player*. It ships no channels and hosts nothing — you bring the
subscription you already pay for.

## The product bet

UHF proved the category can be beautiful. The gap it leaves is setup: it still
asks a normal person to know what an M3U is, where their EPG lives, and which
of their forty provider folders hold films. Kanal's thesis is that none of that
should ever reach the user.

The test everything is measured against: **Kari, 63, types "Løvenes konge" and
finds the film for her grandchildren** — even though her provider listed it as
"The Lion King".

| Pillar | Where it lives | State |
| --- | --- | --- |
| One-field setup | `SourceDetector` | Done |
| Auto-organisation | `TitleCleaner`, `MediaClassifier`, `CategoryNormalizer`, `Library` | Done |
| No settings | `SettingsView` manages playlists and nothing else | Done |
| Search that forgives | `SearchNormalizer`, `SearchIndex`, `MetadataService` | Done |
| Speaks your language | `UIStrings`, `CoreStrings`, `PreferredLanguages`, `Scripts/check-localization.py` | Done (en, nb) |
| TV guide | `GuideView`, `XMLTVParser` | Done |
| Phone → TV handoff | `Pairing`, `PairingHost`, `PairingGuest`, `PairingView`, `HandoffView` | Built, not yet tested on real hardware |

## How search finds a film nobody listed under that name

Two stages, and the second is the whole point.

1. **Local.** `SearchIndex` is a sorted postings list built once per library
   load. It folds `ø æ å ß` — which Foundation's diacritic folding leaves
   alone — matches word prefixes in any order, and ranks exact titles above
   longer ones containing them. Instant, offline, and it never touches the
   network. Measured on 50,000 entries: **0.49 s to build, 12 ms per query.**

2. **Translated.** Only when the local pass comes up short, Kanal asks what the
   words *mean* and searches again under every other name the title has.

The direction matters. Pre-translating a 50,000-entry library would be a
hundred thousand requests at first launch — slow, and expensive on any paid
API. Translating the *query* is one request and covers the whole catalogue
immediately.

### Three tiers, cheapest first

`MetadataProvider` is a two-method protocol. Providers are tried in order and
the first confident answer wins, so cost and latency rise only when they have
to:

1. **Bundled title packs** — a static file shipped with the app. No network, no
   key, no rate limit, works on a plane. Answers the common case instantly.
2. **Wikidata, live** — free and key-less, for the long tail the pack misses.
3. **TMDB** — optional, only if built with a key, and only ever for artwork.

The tiers feed each other. Artwork databases search *their own* titles, not the
viewer's: TMDB will not find "Biler" however hard it looks, but it knows
"Cars". So tier 1 canonicalises the name before tier 3 is asked, which is what
gets a poster onto a Norwegian film's card at all.

#### Why the packs are small enough to ship

Only titles that **differ** from English are worth storing. "Ratatouille" and
"Django Unchained" are spelled the same everywhere and the local index already
finds them; the only pairs that need shipping are ones like "Løvenes konge" →
"The Lion King".

That turns an unbounded problem into a small static file. Norwegian is **6,764
pairs in 290 KB** — and of 22 test titles, 16 resolve entirely offline, with
the two "misses" being exactly the identical-in-both-languages case the design
deliberately omits.

`Scripts/build-title-packs.py` builds them from Wikidata at build time, one
entity type per query, unsorted, with backoff — `ORDER BY` with LIMIT/OFFSET
makes the query service sort the whole result set per page and reliably earns a
504.

A pack ships for every language the interface speaks, and only those. German
alone is 3.2 MB, so bundling everything we have built would cost every user
megabytes for languages whose interface is not even translated. Packs for `de`,
`sv`, `da`, `fr` and others are built and sitting in `Localizations/titles/`,
ready for when those interface languages ship. Anyone on a language without a
pack still gets translated search — it just comes from tier 2.

If the packs ever outgrow the app bundle, the next step is hosting them as a
GitHub release and fetching one on first run. Still free, still no server.

### Supplying a TMDB credential

TMDB issues two kinds and they authenticate differently: a **v3 API key** (32
hex characters, passed as a query parameter) and a **v4 read access token** (a
JWT, passed as `Authorization: Bearer`). Both work against the same `/3/`
endpoints. `TMDBClient` detects the shape rather than asking, because guessing
wrong fails with a 401 that reads like a bad key instead of a bad scheme.
Whitespace is stripped, since tokens are long enough that people paste them
wrapped across lines.

Put it in `Config/Secrets.xcconfig` (gitignored):

```
TMDB_API_KEY = <your key or token>
```

An empty value is fine — Kanal simply stays on the free tiers.

TMDB answers with an empty plot when it has none in the requested language, so
`TMDBClient` falls back to the English one. A blank space tells you nothing
about a film; an English sentence tells you what it is.

### Metadata providers, and why Wikidata is the default

`MetadataProvider` is a two-method protocol; providers are tried in order and
the first confident answer wins.

- **Wikidata** — always on. No API key, no signup, no registered application
  URL, and CC0 data, so Kanal works out of the box for everyone at no cost,
  commercial or not. Every entity carries a label in every language, which is
  exactly the question Kanal asks. It cannot supply posters: film artwork is
  copyrighted and largely absent from Commons.
- **TMDB** — optional, added only if the app is built with a key. Its API is
  free for personal use; a commercial licence costs money. It earns that cost
  only for artwork, never for search.

Kanal refuses a loose match rather than guessing. A wrong translation sends
someone to the wrong film with no clue why, which is worse than no translation.

### Measured coverage

Against 22 real Norwegian titles plus two nonsense controls:

- **16 resolved** — including "Gudfaren" → The Godfather, "Askepott" →
  Cinderella, "Gjøkeredet" → One Flew Over the Cuckoo's Nest, "Oppdrag Nemo" →
  Finding Nemo, and Norwegian-only films that correctly resolve to themselves.
- **3 genuine misses** — obscure titles, or ones whose Norwegian name differs
  from the Wikidata label ("Snøhvit" vs "Snehvit og de syv dvergene").
- **Both controls correctly rejected.** No false positives, which matters more
  than raw coverage.
- **3 network errors** — Wikimedia rate-limiting, see below.

So roughly five in six for mainstream titles, and never a wrong answer.

### A rate limit is not an answer

The measurement exposed a real bug worth recording. Wikimedia returns HTTP 429
under load, and the first version treated any failed lookup as "no such title"
and cached it. One slow moment would have made a film permanently invisible.

Now `WikidataProvider` distinguishes temporary failures from permanent ones,
retries with backoff, and searches languages sequentially rather than in
parallel — parallel requests were what earned the 429. `MetadataService` only
records a negative result when a provider actually answered "nothing".

## Playback, and why VLC is bundled

`AVPlayer` cannot open Matroska. Measured against a real provider's catalogue,
**31,027 of 31,176 films were `.mkv`**, and every series episode too — which is
why live TV worked and nothing else did. No amount of retrying alternative
extensions helps: panels do not offer one.

So Kanal ships two engines and picks per stream:

- **AVFoundation** for live TV and MP4. It brings picture-in-picture, AirPlay,
  the tvOS transport bar and the system's own subtitle and audio menus, none of
  which a bundled decoder gets for free.
- **VLC** for everything else. If AVFoundation reports a container it cannot
  open, playback moves across without the viewer seeing an error.

The engines are chosen by `PlaybackEngine.preferred(for:)`. `KanalUI` asks for
the second engine through an environment builder, so the package — and its
tests — stay free of a very large binary.

### One set of controls, two engines

`AVPlayerViewController` gave pause, scrubbing, track selection and a way out
for free. Swapping it for VLC on the Matroska path took all of that with it —
a film opened and the only way to stop watching was to force-quit the app.

Apple's player chrome is private and cannot be restyled, so imitating it would
have left the two paths *nearly* alike, which is the version that reads as
broken. Instead both engines expose `PlaybackControlling` and wear the same
`PlayerChrome`: they match because they are the same view.

The engines hand back only a video surface; `PlayerView` draws the controls.
An earlier attempt let each engine draw its own, and the VLC one inherited the
video's safe-area insets and clipped the title behind the Dynamic Island.

What the system path still has that VLC cannot: picture-in-picture and AirPlay.
Those are attached to the `AVPlayerLayer` and appear in the same chrome.

### Which VLC, and why

**MobileVLCKit and TVVLCKit 3.7.3**, the stable releases. VLCKit 4.0 has Swift
Package Manager support, which is tempting, but it is an alpha; the decoder is
not the place to run one.

3.7.x is distributed through CocoaPods only, so rather than adding that
toolchain the XCFrameworks are fetched straight from VideoLAN:

```bash
./Scripts/fetch-vlc.sh
```

`Vendor/` is gitignored — the frameworks are far too large to commit — so a
fresh clone runs that once. The script drops `armv7` and `armv7s`, which no device capable of running
Kanal can execute, and removes simulator debug symbols. Device symbols are
kept: without them every App Store upload warns "Upload Symbols Failed", and a
warning that appears every single time is one nobody reads.

### Size, measured

| | |
| --- | --- |
| VideoLAN's download, both platforms | 366 MB |
| `Vendor/` after trimming | 525 MB |
| **Release app for an iPhone** | **36 MB**, of which 33 MB is VLC |

### Licence

VLCKit is **LGPL v2.1 or later**. That permits it inside a proprietary app —
VLC relicensed specifically so it could ship on the App Store — on three
conditions, all met:

1. Publish any changes made to VLC. Kanal makes none.
2. Make the viewer aware VLC is embedded. Settings → Licences.
3. Make the viewer aware of their rights and where the source lives. Same
   screen, with a link and the relinking notice.

Kanal's own code stays closed; that is the difference between LGPL and GPL.
Before a commercial launch, have a lawyer read it.

## The TV guide

`GuideView` draws channels down and time across. Both axes scroll, but the
channel column and hour header must stay put — a guide where you lose track of
which row you are on is useless. Rather than synchronising several scroll
views, it reads the single scroll's offset and pushes the two headers back by
the same amount, so they read as pinned while everything stays in one lazily
drawn grid.

It lives inside the Live TV tab as a view toggle rather than a sixth tab, which
would have pushed search under "More".

### Provider guides are malformed in more ways than one

`XMLParser` is strict and provider guides are not. Measured against the
malformations panels actually emit, **seven of eight killed the parser
outright**:

| Input | Strict parser |
| --- | --- |
| Bare `&` in a title | fails |
| `&nbsp;`, `&eacute;` and other HTML entities | fails |
| Control characters below 0x20 | fails |
| Latin-1 content declaring `encoding="UTF-8"` | fails |
| A stray `<` in text | fails |
| A download that stopped mid-element | fails |
| A byte-order mark before the declaration | survives |

The cost is total rather than partial: every `<programme>` element comes after
every `<channel>`, so one bad byte a third of the way in takes the whole
schedule. On a real 225 KB test guide carrying four of these faults at once, a
strict parser delivered **81 elements — all 42 channels — and zero
programmes.** `XMLRepair` recovered **918 programmes across all 42 channels**
from the same bytes.

The ladder is in `XMLRepair`: strip leading junk, transcode mislabelled
encodings, remove illegal control characters, resolve or escape undeclared
entities, escape stray angle brackets, and close a truncated root so everything
before the cut survives. Nothing alters meaning — it fixes encoding and
escaping, never content. A well-formed guide is parsed strictly and never pays
for any of it.

### Repairing silently is its own kind of lie

A guide covering a third of your channels looks identical to one covering all
of them, right up until you go looking for a programme that isn't there. So
`SourceDiagnostics` records what was wrong — entries that could not be read,
repairs that were needed, a file that stopped short, and how much of your
channel list the guide actually covers — and Settings shows it, but only when
there is something to say. A clean load says nothing, because a permanent
"everything is fine" row is just noise.

To see what Kanal makes of your own provider's guide:

```bash
cd Packages/KanalKit && KANAL_TEST_EPG_URL="<your epg url>" swift test --filter LiveEPGTests
```

## Localization

Every user-facing string is declared in exactly two files — `KanalUI/Strings.swift`
and `KanalCore/Strings.swift` — as `LocalizedStringResource` constants with the
bundle baked in. Views never hold a literal. That makes "did we miss one?" a
question you answer by reading a list, and a typo in a key a compile error.

`Scripts/check-localization.py` enforces it, and runs as part of `swift test`:

1. Every key declared in Swift exists in its catalog.
2. Every catalog key is declared — no orphans sent to translators.
3. Every entry is translated into every language the catalog carries.
4. No literal survives in a view (`Text("…")`, `Button("…")`, and friends).
5. The app's `CFBundleLocalizations` lists every language the packages carry.

### Four traps this codebase hit, all now closed

- **SwiftUI in a package resolves against `Bundle.main`**, which is the app, so
  every string silently falls back to its key. Looks perfect in English, fails
  everywhere else. Closed by baking `Bundle.module` into every declaration.
- **SwiftPM does not compile `.xcstrings`** — only Xcode's build system does.
  Strings would have worked in the shipping app and not under `swift test`.
  Closed by keeping the catalogs in `Localizations/` as the editable source and
  compiling them to `.lproj` with `Scripts/build-localizations.py`.
- **Runtime-built strings are never extracted.** Counts, error messages and
  kind names are invisible to any extractor. Closed by declaring them as
  functions over catalog keys, which also gets real plural rules — "1 channels"
  is wrong in English and much worse elsewhere.
- **iOS picks the app's language from the app bundle**, not from its packages.
  Perfect translations in a package are simply never consulted. Closed by
  `CFBundleLocalizations`, and checked by the lint.

### Category names are translated too

Provider categories look like untouchable data, but they are not arbitrary
text — across real playlists they are drawn from a small, repeating vocabulary.
`CategoryLocalizer` covers it two ways, both free and offline:

- **Genres** — about fifty recurring words ("Entertainment", "Documentaries",
  "Kids", "Sci-Fi"), each a real catalog entry, so they are translated and
  linted like everything else.
- **Countries** — resolved through Foundation's own region data, which means
  every country name Apple ships is covered in the viewer's language with no
  list to maintain. "Norway", "Norge" and a bare "NO" all land on the same
  localized name.

Two rules keep it honest. Translation is **display-only** — grouping, filtering
and favourites all key off the raw name, so changing your phone's language
never breaks your filters. And it **never guesses**: anything unrecognised is
passed through exactly as the provider wrote it, because a mistranslated
"Viaplay Sport 1" is worse than leaving it alone.

### Still not translated, on purpose

Channel names, film titles and episode titles. Those are content, not labels.

### Language is not only interface text

`PreferredLanguages` feeds the *metadata* layer from the device too. Hardcoding
Norwegian there was a real bug: it made the whole translated-search feature
useless to anyone else. A German typing "Der König der Löwen" and a Swede
typing "Lejonkungen" now both find a provider entry called "The Lion King" —
covered by live tests that pass their languages explicitly, so they prove the
feature rather than the machine they run on.

### Adding a language

1. Add the translations to `Localizations/*.xcstrings` (Xcode opens these).
2. `python3 Scripts/build-localizations.py`
3. Add the code to `CFBundleLocalizations` in both `Info.plist` files.
4. `swift test` — the lint fails on anything missed.

## Layout

```
Kanal/
  project.yml                  XcodeGen spec — regenerate with `xcodegen generate`
  Config/Secrets.xcconfig      TMDB key, gitignored (an empty key is fine)
  Localizations/*.xcstrings    Translation source of truth
  Localizations/titles/        Offline title packs, per language
  Vendor/                      VLC frameworks, gitignored (Scripts/fetch-vlc.sh)
  Scripts/                     Localization and title-pack build, plus the lint
  App/Shared/KanalApp.swift    @main, shared by both app targets
  App/iOS, App/tvOS            Info.plist and platform assets only
  Packages/KanalKit/
    Sources/KanalCore          Models, parsing, organisation, metadata, pairing, storage
    Sources/KanalUI            Design system and every screen
    Tests/KanalCoreTests       122 tests
```

Almost all code lives in the package; the app targets are shells. That is why
one SwiftUI tree serves phone, tablet and TV.

## Design system

- **Palette** (`KanalColor`) — neutral surfaces, one saturated coral gradient
  reserved for the single most important action on a screen.
- **Type** (`KanalFont`) — heavy condensed display face for headlines, plain
  system text below that so it reads across a room.
- **Metrics** (`KanalMetrics`) — every spacing step scales 1.6× on tvOS.
- **Liquid Glass** (`KanalGlass`) — `kanalGlassPanel`, `kanalGlassPill` and
  `kanalGlassOverVideo` wrap the iOS 26 glass APIs so no call site repeats a
  shape/tint/interactivity combination.
- **Focus** — `KanalCardButtonStyle` and `KanalChipButtonStyle` lift, brighten
  and cast a shadow when focused, because on a TV the focused element is the
  entire interface.

## Handoff, and why there is no server

Typing a provider URL with a remote is the worst minute in any TV app. The
Apple TV shows a QR code; the phone reads it and sends the playlist directly
over the local network using Bonjour and `Network`, sealed with a ChaChaPoly
key that exists only while the pairing screen is open.

No account, no backend, **no running cost** — and provider credentials never
leave the house.

## Running it

```bash
xcodegen generate
open Kanal.xcodeproj
```

Tests run without Xcode:

```bash
cd Packages/KanalKit && swift test
```

Tests that hit the real internet are off by default:

```bash
cd Packages/KanalKit && KANAL_LIVE_TESTS=1 swift test --filter LiveIntegrationTests
```

## Verified

- iOS and tvOS both build and run; screenshots taken on iPhone 17 Pro, iPad
  Pro 13" and Apple TV 4K, in light and dark.
- 122 offline tests, plus live ones against Wikidata, TMDB and a real EPG file, including Kari's exact scenario.
- Both apps run in Norwegian end to end, verified by screenshot with
  `-AppleLanguages '(nb)'`.

## Not yet verified

- Handoff has never run on two real devices. Simulators do not share a local
  network in a way that exercises Bonjour properly.
- The QR scanner needs a real camera; the simulator has none.
- No Xtream panel has been tested. `XtreamClient` is written against the
  documented API and its shape is covered by unit tests, but no live panel has
  answered it.

## Before shipping

- **Wikimedia user agent.** `WikidataProvider` sends
  `Kanal/1.0 (IPTV player for Apple platforms)`. Wikimedia's policy wants a
  contact URL in there — add one once the site exists.
- **Attribution.** Wikidata is CC0 and needs none, but crediting it is polite.
  TMDB is enabled and *requires* attribution — its wording must appear in the
  app before release. Not yet added.
- `DEVELOPMENT_TEAM` in `project.yml` is empty.

## Next

- Recordings, multi-view, per-profile favourites.
- More languages. The machinery is done and English and Norwegian ship; adding
  a language is now three steps and a lint run.
