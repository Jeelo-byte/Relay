#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# launchd has a minimal PATH; support standard Node installations.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
[[ -f apps/web/.next/BUILD_ID ]] || { echo 'Build the website first: npm ci && npm run build' >&2; exit 1; }
[[ -f .env.local ]] || { echo 'Configure .env.local before starting the host.' >&2; exit 1; }
node --env-file=.env.local node_modules/next/dist/bin/next start apps/web --hostname 127.0.0.1 --port 3100 &
web_pid=$!
node scripts/host-gateway.mjs &
gateway_pid=$!
cleanup() { kill "$web_pid" "$gateway_pid" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
while kill -0 "$web_pid" 2>/dev/null && kill -0 "$gateway_pid" 2>/dev/null; do sleep 2; done
exit 1
