#!/bin/bash
#
# Captures App Store screenshots from a booted simulator, seeded with the
# demo playlist (public test streams and Creative Commons films only — never a
# real provider, whose posters App Review would read as pirated content).
#
#   python3 -m http.server 8740 --bind 127.0.0.1   # in ../Site
#   ./AppStore/capture-screenshots.sh <udid> <iphone|ipad|tv> <en|nb>
#
# Needs a Debug build installed (the -kanal-* launch arguments are compiled out
# of Release). Status bar: `xcrun simctl status_bar <udid> override --time 9:41`.
set -euo pipefail
UDID="$1"; KIND="$2"; LANG_CODE="${3:-en}"
OUT="$(cd "$(dirname "$0")" && pwd)/screenshots/$KIND-$LANG_CODE"
mkdir -p "$OUT"
LOCALE=$([ "$LANG_CODE" = nb ] && echo nb_NO || echo en_US)
SOURCE="${KANAL_DEMO:-http://127.0.0.1:8740/demo.m3u}"

shot() {
	local name="$1" wait="$2"; shift 2
	# Terminate and pause first: tvOS drops a launch that arrives while the
	# previous instance is still going down, and lands on the Home screen.
	xcrun simctl terminate "$UDID" com.bomann.kanal >/dev/null 2>&1 || true
	sleep 3
	xcrun simctl launch "$UDID" com.bomann.kanal \
		-AppleLanguages "($LANG_CODE)" -AppleLocale "$LOCALE" "$@" >/dev/null
	sleep "$wait"
	xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
	echo "  $name"
}

# First launch loads the playlist and lets artwork arrive.
shot 00-warmup 40 -kanal-source "$SOURCE"
rm -f "$OUT/00-warmup.png"
shot 01-home     15
shot 02-films    15 -kanal-tab films
shot 03-details  15 -kanal-details 2
# The demo playlist has no programme guide, so Live TV shows its channel list.
shot 04-live     15 -kanal-tab live
shot 05-series   15 -kanal-open-series 0
shot 06-player   30 -kanal-play-movie 2
# Not for the store listing: the paywall is the review screenshot each
# in-app purchase needs. Its sample prices are Norwegian kroner.
shot 99-paywall-iap-review 10 -kanal-paywall
echo "Saved to $OUT"
