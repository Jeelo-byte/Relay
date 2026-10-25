#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -ne 2 ]; then
  printf 'Usage: bash scripts/run-iphone.sh DEVICE_UDID APPLE_TEAM_ID\n' >&2
  exit 2
fi
device_udid="$1"
apple_team_id="$2"
mkdir -p artifacts
# Build the application target. The root Swift package produces a bare
# executable, which cannot be installed on an iPhone.
xcodebuild -project Relay.xcodeproj -scheme Relay \
  -destination "id=$device_udid" -derivedDataPath DerivedData \
  CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$apple_team_id" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build \
  > artifacts/iphone-device-build.log 2>&1
app_path="DerivedData/Build/Products/Debug-iphoneos/Relay.app"
codesign --verify --deep --strict "$app_path"
xcrun devicectl device install app --device "$device_udid" "$app_path"
if ! xcrun devicectl device process launch --device "$device_udid" \
  --terminate-existing app.relay.agreements; then
  printf 'If iOS reports developer trust, trust your developer account in Settings > General > VPN & Device Management on the phone, then rerun.\n' >&2
  exit 1
fi
