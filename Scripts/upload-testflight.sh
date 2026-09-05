#!/bin/bash
#
# Archives both apps and uploads them to TestFlight.
#
# Needs an App Store Connect API key, because Xcode's own signed-in session is
# not reachable from the command line — `xcodebuild` fails with "Failed to Use
# Accounts" whatever else is configured.
#
# Put the key and its two identifiers here, outside the repository:
#
#   ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
#   ~/.appstoreconnect/issuer.txt      one line, the Issuer ID
#   ~/.appstoreconnect/keyid.txt       one line, the Key ID
#
# Both identifiers are on App Store Connect under
# Users and Access -> Integrations -> App Store Connect API.
#
#   ./Scripts/upload-testflight.sh            both platforms
#   ./Scripts/upload-testflight.sh ios        just iPhone and iPad
#   ./Scripts/upload-testflight.sh tvos       just Apple TV
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$HOME/.appstoreconnect"
TEAM="JWL8576LU4"

fail() { printf '\n%s\n' "$1" >&2; exit 1; }

[ -f "$CONFIG/issuer.txt" ] || fail "Missing $CONFIG/issuer.txt — see the notes at the top of this script."
[ -f "$CONFIG/keyid.txt" ] || fail "Missing $CONFIG/keyid.txt — see the notes at the top of this script."

ISSUER="$(tr -d '[:space:]' < "$CONFIG/issuer.txt")"
KEY_ID="$(tr -d '[:space:]' < "$CONFIG/keyid.txt")"
KEY_PATH="$CONFIG/private_keys/AuthKey_${KEY_ID}.p8"
[ -f "$KEY_PATH" ] || fail "Missing $KEY_PATH"

WANTED="${1:-both}"

# Every upload needs a build number App Store Connect has not seen before.
BUILD="$(date +%Y%m%d%H%M)"
echo "Build number: $BUILD"

options="$(mktemp -t kanal-upload).plist"
trap 'rm -f "$options"' EXIT
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>destination</key><string>upload</string>
	<key>uploadSymbols</key><true/>
	<key>testFlightInternalTestingOnly</key><true/>
</dict>
</plist>
PLIST

ship() {
	local scheme="$1" platform="$2" archive="/tmp/Kanal-$2-$BUILD.xcarchive"

	echo
	echo "── $scheme ──────────────────────────────"

	local app="$archive/Products/Applications/Kanal.app"
	if [ "$platform" = "tvOS" ]; then
		# A development-signed generic tvOS archive requires a registered Apple
		# TV. Preserve the requested entitlement in an ad-hoc archive instead;
		# exportArchive then obtains the App Store profile and distribution-signs
		# it. A wholly unsigned archive loses the target entitlements at export.
		xcodebuild -project "$ROOT/Kanal.xcodeproj" -scheme "$scheme" \
			-destination "generic/platform=$platform" -configuration Release \
			-archivePath "$archive" CURRENT_PROJECT_VERSION="$BUILD" \
			CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
			archive | awk '/error:|ARCHIVE (SUCCEEDED|FAILED)/'

		local concrete_entitlements bundle_id
		concrete_entitlements="$(mktemp -t kanal-entitlements).plist"
		bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Info.plist")"
		cp "$ROOT/App/tvOS/Kanal.entitlements" "$concrete_entitlements"
		/usr/libexec/PlistBuddy -c \
			"Set :com.apple.developer.ubiquity-kvstore-identifier $TEAM.$bundle_id" \
			"$concrete_entitlements"
		/usr/bin/codesign --force --sign - --entitlements "$concrete_entitlements" "$app"
		rm -f "$concrete_entitlements"
	else
		# Archive with App Store Connect credentials. A wholly unsigned archive
		# loses the target's requested entitlements during export.
		xcodebuild -project "$ROOT/Kanal.xcodeproj" -scheme "$scheme" \
			-destination "generic/platform=$platform" -configuration Release \
			-archivePath "$archive" CURRENT_PROJECT_VERSION="$BUILD" \
			-allowProvisioningUpdates \
			-authenticationKeyPath "$KEY_PATH" \
			-authenticationKeyID "$KEY_ID" \
			-authenticationKeyIssuerID "$ISSUER" \
			archive | awk '/error:|ARCHIVE (SUCCEEDED|FAILED)/'
	fi

	if ! /usr/bin/codesign -d --entitlements :- "$app" 2>&1 \
		| sed -n '/<?xml/,$p' \
		| /usr/bin/plutil -extract 'com\.apple\.developer\.ubiquity-kvstore-identifier' \
			raw -o - - >/dev/null 2>&1; then
		fail "$scheme archive is missing its iCloud key-value-store entitlement; refusing to upload."
	fi
	echo "Verified iCloud entitlement in $scheme archive."

	xcodebuild -exportArchive -archivePath "$archive" \
		-exportOptionsPlist "$options" -allowProvisioningUpdates \
		-authenticationKeyPath "$KEY_PATH" \
		-authenticationKeyID "$KEY_ID" \
		-authenticationKeyIssuerID "$ISSUER" \
		| awk '/error:|EXPORT (SUCCEEDED|FAILED)|Upload/'
}

case "$WANTED" in
	ios)  ship Kanal iOS ;;
	tvos) ship KanalTV tvOS ;;
	both) ship Kanal iOS; ship KanalTV tvOS ;;
	*)    fail "Unknown target '$WANTED'. Use ios, tvos, or both." ;;
esac

echo
echo "Uploaded as build $BUILD. Processing on App Store Connect takes a few minutes."
