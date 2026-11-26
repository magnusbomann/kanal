#!/bin/bash
#
# Moves Kanal to a different public domain in one step.
#
# Everything that leaves the device or reaches App Review names the domain:
# the in-app privacy and terms texts, the Wikimedia user agent, the App Store
# metadata and review notes in AppStore/, and every page of Site/. They all say kanalplayer.com today.
#
#   ./Scripts/set-domain.sh kanal.example
#
# Logs (WORKLOG, LAUNCH_REVIEW, README) are history and are left alone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$ROOT/Site"
OLD="${OLD_DOMAIN:-kanalplayer.com}"
NEW="${1:?Usage: $0 <new-domain>}"

case "$NEW" in
	*/*|*@*|http*) echo "Give the bare domain, e.g. kanal.example" >&2; exit 1 ;;
esac

old_pattern="${OLD//./\\.}"
files=()
while IFS= read -r file; do files+=("$file"); done < <(
	grep -rlF "$OLD" \
		"$ROOT/Packages/KanalKit/Sources" \
		"$ROOT/AppStore" \
		"$SITE" 2>/dev/null || true
)

[ "${#files[@]}" -gt 0 ] || { echo "Nothing names $OLD." ; exit 0; }

for file in "${files[@]}"; do
	sed -i '' "s/$old_pattern/$NEW/g" "$file"
	echo "  ${file#"$ROOT/"}"
done
echo "Moved ${#files[@]} files from $OLD to $NEW."
echo "Then: ./Scripts/build-localizations.py is not needed (legal texts are plain"
echo "resources), but run swift test, and update the URLs in App Store Connect."
