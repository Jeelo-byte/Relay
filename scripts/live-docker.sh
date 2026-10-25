#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/relay/docker.sock}"
if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
else
  compose=(docker-compose)
fi
exec "${compose[@]}" --env-file "$project_dir/infra/matrix/private/runtime.env" -f "$project_dir/infra/matrix/compose.live.yml" "$@"
