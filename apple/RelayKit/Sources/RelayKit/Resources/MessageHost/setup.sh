#!/bin/bash
# stdout is a private Matrix session for the native caller. Never echo credentials.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
assets="$(cd "$(dirname "$0")" && pwd)"
state="${1:?Choose a private host directory}"; shift
[[ $# -gt 0 ]] || { echo 'Choose at least one Docker connection.' >&2; exit 1; }
for service in "$@"; do
  case "$service" in whatsapp|instagram|gmessages|discord) ;; *) echo 'Unsupported connection.' >&2; exit 1;; esac
done
command -v docker >/dev/null || { echo 'Install Docker Desktop, then retry setup.' >&2; exit 1; }
if ! docker info >/dev/null 2>&1; then
  if [[ "$(uname)" == Darwin ]]; then open -a Docker || true; fi
  for attempt in {1..60}; do docker info >/dev/null 2>&1 && break; sleep 2; done
fi
docker info >/dev/null 2>&1 || { echo 'Docker is not ready. Open Docker Desktop and retry.' >&2; exit 1; }
umask 077
mkdir -p "$state/private/synapse" "$state/private/element"
# Serialize setup across windows/processes; never rewrite live configuration concurrently.
mkdir "$state/.setup-lock" 2>/dev/null || { echo 'Another setup is running. Retry when it finishes.' >&2; exit 1; }
trap 'rmdir "$state/.setup-lock"' EXIT
cp "$assets/compose.yml" "$state/compose.yml"
compose=(docker compose --project-name relay-messages -f "$state/compose.yml" --profile bridges)
synapse_image="ghcr.io/element-hq/synapse@sha256:390f5e67227378eb87c84627b57f0582cdb235fcc8159d89f371f37bf7cccfd7"
configure() {
  docker run --rm -v "$state/private:/private" -v "$assets:/setup:ro" -e RELAY_MATRIX_PORT="${RELAY_MATRIX_PORT:-8008}" --entrypoint python "$synapse_image" /setup/configure.py "$@"
}
if [[ ! -f "$state/private/synapse/homeserver.yaml" ]]; then
  echo 'Preparing your private message server…' >&2
  "${compose[@]}" run --rm --no-deps -e SYNAPSE_SERVER_NAME=relay.local -e SYNAPSE_REPORT_STATS=no synapse generate >&2
fi
configure homeserver >&2
for service in "$@"; do
  echo "Preparing ${service}..." >&2
  mkdir -p "$state/private/$service"
  if [[ ! -f "$state/private/$service/config.yaml" ]]; then
    "${compose[@]}" run --rm --no-deps "$service" >/dev/null 2>&1 || true
  fi
  configure bridge "$service" >&2
  if [[ ! -f "$state/private/$service/registration.yaml" ]]; then
    "${compose[@]}" run --rm --no-deps "$service" >/dev/null 2>&1 || true
  fi
  configure registration "$service" >&2
done
"${compose[@]}" up -d synapse element "$@" >&2
# Restart to load newly added registrations while retaining accounts and databases.
"${compose[@]}" restart synapse >&2
# Use Synapse's own Python runtime; no host Python, pip, or Node installation needed.
"${compose[@]}" exec -T -u root -e RELAY_MATRIX_PORT="${RELAY_MATRIX_PORT:-8008}" synapse python - < "$assets/account.py"
echo 'Message server ready. Link each selected account in Relay.' >&2
