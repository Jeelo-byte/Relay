#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="${1:-../Relay.app}"
# SwiftPM keeps resource bundles beside the executable; preserve its expected
# bundle-root layout inside the app as well as standard macOS metadata.
swift build
build_path="$(swift build --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$build_path/Relay" "$app_path/Contents/MacOS/Relay"
cp docs/brand/Relay.icns "$app_path/Contents/Resources/Relay.icns"
for bundle_path in "$build_path"/*.bundle; do
  [ -d "$bundle_path" ] && cp -R "$bundle_path" "$app_path/Contents/Resources/"
done
/usr/bin/python3 - "$app_path/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'CFBundleExecutable':'Relay', 'CFBundleIdentifier':'app.relay.agreements',
      'CFBundleName':'Relay', 'CFBundleIconFile':'Relay', 'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'0.4.0',
      'CFBundleVersion':'7', 'LSMinimumSystemVersion':'14.0',
      'NSHighResolutionCapable':True, 'NSFaceIDUsageDescription':'Unlock your private Relay agreements.',
      'NSContactsUsageDescription':'Relay imports contact names, phone numbers, and email addresses to link profiles across your messaging apps on this device.',
      'NSAppleEventsUsageDescription':'Relay sends the replies you review through Messages on this Mac.'}, f)
PY
chmod -R u+w "$app_path"
xattr -cr "$app_path"
codesign --force --deep --options runtime --entitlements apple/RelayMac.entitlements --sign - "$app_path"
printf 'Built %s\n' "$app_path"
