#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
# Honor Docker's selected context and an explicit DOCKER_HOST. Docker Desktop and
# Colima have different sockets; do not silently override the user's runtime.
if ! command -v docker >/dev/null 2>&1; then
  echo "Install and start Docker Desktop (or Docker Engine) before running Relay's message services." >&2
  exit 1
fi
if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
else
  compose=(docker-compose)
fi
stack="${RELAY_MATRIX_STACK:-local}"
case "$stack" in
  local) args=(-f "$project_dir/infra/matrix/compose.yml") ;;
  live)
    runtime_env="$project_dir/infra/matrix/private/runtime.env"
    if [[ ! -f "$runtime_env" ]]; then
      echo "The optional PostgreSQL stack needs infra/matrix/private/runtime.env and initialized PostgreSQL data. See docs/WEB-SETUP.md. The existing Mac stack uses RELAY_MATRIX_STACK=local (the default)." >&2
      exit 1
    fi
    args=(--env-file "$runtime_env" -f "$project_dir/infra/matrix/compose.live.yml") ;;
  *) echo "RELAY_MATRIX_STACK must be local or live." >&2; exit 1 ;;
esac
if [[ "${1:-}" != "config" ]] && ! docker info >/dev/null 2>&1; then
  echo "Docker is not reachable. Start Docker Desktop or choose your running Docker context." >&2
  exit 1
fi
exec "${compose[@]}" "${args[@]}" "$@"
