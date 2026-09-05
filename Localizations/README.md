# Localization contract

`languages.json` is the authoritative list of interface languages shipped by
Kanal. English is the source language and the safe fallback. iOS and tvOS pick
the best supported language from the viewer's system or per-app language
setting.

## Adding or changing interface text

1. Declare the key in the module's `Strings.swift`.
2. Add the English source and every translation to the matching `.xcstrings`
   catalog.
3. Run `python3 Scripts/build-localizations.py` to regenerate every `.lproj`.
4. Run `swift test`. `LocalizationTests` invokes
   `Scripts/check-localization.py` and fails if a declared key, a supported
   language, a compiled resource, a format placeholder, or an Info.plist
   localization is missing.

Never add user-facing string literals directly to SwiftUI views. Never edit
generated `.strings` or `.stringsdict` files by hand.

Machine translation is acceptable as a first pass, but onboarding, purchases,
privacy, parental controls, playback and error recovery require human review
before an App Store release. Arabic also requires an explicit right-to-left UI
pass. Product and protocol names such as Kanal, M3U, Xtream, EPG, TMDB and VLC
stay unchanged.

## Metadata language

TMDB discovery, titles, plots and details use the viewer's locale. Their caches
are scoped by language and region, so changing the app language cannot leave
old metadata on screen. TMDB falls back to English when a localized plot is
empty. Provider-supplied channel and category names remain provider content;
Kanal localizes known genres and country names locally.
