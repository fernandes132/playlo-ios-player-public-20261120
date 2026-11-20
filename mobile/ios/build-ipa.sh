#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 ../prepare_shared.py
command -v xcodebuild >/dev/null || { echo "Build requires macOS and Xcode." >&2; exit 1; }
xcodebuild -project Playlo.xcodeproj -scheme Playlo -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
APP="DerivedData/Build/Products/Release-iphoneos/Playlo.app"
[[ -f "$APP/Playlo" ]] || { echo "No built app executable; refusing to create IPA." >&2; exit 1; }
file "$APP/Playlo" | grep -q 'Mach-O' || { echo "App executable is not Mach-O." >&2; exit 1; }
mkdir -p .build
STAGE=$(mktemp -d "$PWD/.build/package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/Playlo.app"
(cd "$STAGE" && /usr/bin/zip -qry "$OLDPWD/.build/Playlo-unsigned.ipa" Payload)
python3 validate-ipa.py .build/Playlo-unsigned.ipa
python3 ../verify_bundle.py .build/Playlo-unsigned.ipa > .build/Playlo-embedded-bundle.json
echo "Built .build/Playlo-unsigned.ipa. Import this IPA in iLoader for signing and installation."
