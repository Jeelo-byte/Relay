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
      'CFBundleName':'Relay', 'CFBundleIconFile':'Relay', 'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'0.2.0',
      'CFBundleVersion':'2', 'LSMinimumSystemVersion':'14.0',
      'NSHighResolutionCapable':True, 'NSAppleEventsUsageDescription':'Send only the iMessage drafts you review and confirm through Messages on this Mac.', 'NSFaceIDUsageDescription':'Unlock your private Relay agreements.'}, f)
PY
chmod -R u+w "$app_path"
xattr -cr "$app_path"
codesign --force --deep --entitlements apple/RelayApp/Relay.macOS.entitlements --sign - "$app_path"
printf 'Built %s\n' "$app_path"
