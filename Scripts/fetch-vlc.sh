#!/bin/bash
# Fetches the VLC frameworks Kanal plays MKV with.
#
# AVFoundation cannot open Matroska, and a real provider's catalogue is almost
# entirely MKV — 31,027 of 31,176 films on the one measured. VLC decodes it.
#
# The stable 3.7.x releases are CocoaPods-only, so rather than adding that
# toolchain the XCFrameworks are fetched straight from VideoLAN and dropped in
# Vendor/. They are far too large to commit, so Vendor/ is gitignored and this
# script is what a fresh clone runs once.
#
#   ./Scripts/fetch-vlc.sh
#
# VLCKit is LGPL v2.1. See Settings → Licences in the app.
set -euo pipefail

VERSION="3.7.3-319ed2c0-79128878"
BASE="https://download.videolan.org/cocoapods/prod"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$VENDOR"

fetch() {
  local product="$1" framework="$2"
  if [ -d "$VENDOR/$framework.xcframework" ]; then
    echo "$framework: already present"
    return
  fi

  echo "$framework: downloading…"
  curl -fL --progress-bar -o "$WORK/$product.tar.xz" "$BASE/$product-$VERSION.tar.xz"

  echo "$framework: extracting…"
  mkdir -p "$WORK/$product"
  tar -xJf "$WORK/$product.tar.xz" -C "$WORK/$product"

  local found
  found="$(find "$WORK/$product" -maxdepth 3 -name "$framework.xcframework" -print -quit)"
  [ -n "$found" ] || { echo "$framework: not found in archive" >&2; exit 1; }

  # VideoLAN ships these with full debug symbols — around 1 GB for iOS alone.
  # Stripping is local housekeeping and changes nothing that gets shipped:
  # App Store thinning removes the unused slices at delivery either way.
  echo "$framework: stripping debug symbols…"
  while IFS= read -r binary; do
    strip -S -x "$binary" 2>/dev/null || true
  done < <(find "$found" -type f -name "$framework" -perm -u+x)

  # The dSYM bundles are most of the weight and are of no use to us — but the
  # XCFramework's Info.plist names them, and Xcode fails the build over a
  # DebugSymbolsPath that points at nothing. Drop both together.
  find "$found" -type d -name dSYMs -exec rm -rf {} + 2>/dev/null || true
  python3 - "$found" <<'PLIST'
import plistlib, sys, pathlib
path = pathlib.Path(sys.argv[1]) / "Info.plist"
data = plistlib.loads(path.read_bytes())
for library in data.get("AvailableLibraries", []):
    library.pop("DebugSymbolsPath", None)
path.write_bytes(plistlib.dumps(data))
PLIST

  mv "$found" "$VENDOR/"

  # VideoLAN still ships armv7 and armv7s. No device that can run Kanal can
  # run those, and Apple would strip them at delivery anyway — dropping them
  # here just spares the repository and every local build the weight.
  python3 "$ROOT/Scripts/thin-vlc.py" "$framework"
}

cd "$ROOT"
fetch MobileVLCKit MobileVLCKit   # iOS and iPadOS
fetch TVVLCKit TVVLCKit           # tvOS

echo
echo "Done. Vendor/ is gitignored; rerun this after a fresh clone."
