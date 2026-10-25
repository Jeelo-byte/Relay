#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
# This CLI writes credentials privately, matching the app's one-click host setup.
state="${RELAY_MESSAGE_HOST:-$root/infra/matrix/onboarding}"
umask 077
mkdir -p "$state"
if ! bash "$root/apple/RelayKit/Sources/RelayKit/Resources/MessageHost/setup.sh" "$state" "$@" > "$state/session.json"; then
  rm -f "$state/session.json"
  exit 1
fi
echo "Ready. Private session saved under the chosen host directory. Open Relay to link accounts."
