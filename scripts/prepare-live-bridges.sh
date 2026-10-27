#!/bin/bash
# Add selected bridges to an existing PostgreSQL message host; preserve WhatsApp.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
host="${RELAY_EXISTING_MATRIX_DIR:-$root/infra/matrix}"
assets="$root/apple/RelayKit/Sources/RelayKit/Resources/MessageHost"
[[ -f "$host/private/runtime.env" && -f "$host/private/synapse/homeserver.yaml" ]] || {
  echo 'Choose an initialized PostgreSQL host with RELAY_EXISTING_MATRIX_DIR.' >&2; exit 1;
}
[[ $# -gt 0 ]] || { echo 'Choose instagram, gmessages, or discord.' >&2; exit 1; }
for service in "$@"; do
  case "$service" in instagram|gmessages|discord) ;; *) echo 'Unsupported additional bridge.' >&2; exit 1;; esac
done
compose=(docker compose --project-directory "$host" --env-file "$host/private/runtime.env" -f "$root/infra/matrix/compose.live.yml")
image="ghcr.io/element-hq/synapse@sha256:390f5e67227378eb87c84627b57f0582cdb235fcc8159d89f371f37bf7cccfd7"
configure() {
  docker run --rm -i -v "$host/private:/private" --entrypoint python "$image" - "$@" < "$assets/configure.py"
}
umask 077
mkdir "$host/private/.bridge-setup-lock" 2>/dev/null || { echo 'Another bridge setup is running.' >&2; exit 1; }
trap 'rmdir "$host/private/.bridge-setup-lock"' EXIT
for service in "$@"; do
  echo "Preparing ${service}..."
  mkdir -p "$host/private/$service"
  if [[ ! -f "$host/private/$service/config.yaml" ]]; then
    "${compose[@]}" run --rm --no-deps "$service" >/dev/null 2>&1 || true
  fi
  configure bridge "$service"
  if [[ ! -f "$host/private/$service/registration.yaml" ]]; then
    "${compose[@]}" run --rm --no-deps "$service" >/dev/null 2>&1 || true
  fi
  configure registration "$service"
done
"${compose[@]}" up -d --no-deps "$@"
# Synapse must reload registrations; do not recreate Postgres or WhatsApp.
"${compose[@]}" restart synapse
"${compose[@]}" restart "$@"
echo 'Selected bridges are started. Link their accounts in Relay.'
