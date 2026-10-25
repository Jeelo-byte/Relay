#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
# Backups include decrypted bridge data and credentials. Encrypt before writing the final archive.
[[ $# == 1 && "$1" == /* ]] || { echo 'Usage: bash scripts/backup-message-plane.sh /absolute/path/relay-backup.tar.gz.enc' >&2; exit 1; }
[[ ! -e "$1" ]] || { echo 'Backup destination already exists.' >&2; exit 1; }
backup_work=$(mktemp -d "${TMPDIR:-/tmp}/relay-backup.XXXXXX")
trap 'rm -rf "$backup_work"' EXIT
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/relay/docker.sock}"
container=$(bash scripts/live-docker.sh ps -q postgres)
[[ -n "$container" ]] || { echo 'The message database is not running.' >&2; exit 1; }
# Logical dump is consistent while the stack is running; do not copy a live PG data directory.
docker exec "$container" pg_dumpall -U relay --clean --if-exists > "$backup_work/message-databases.sql"
# Copy configuration/media, excluding PostgreSQL physical files and transient login displays.
tar -czf "$backup_work/message-config.tar.gz" --exclude=postgres --exclude='*.sock' --exclude='*qr*' -C infra/matrix/private .
# OpenSSL prompts privately for the backup password; never put it in a command or environment file.
tar -czf - -C "$backup_work" . | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -out "$1"
[[ -s "$1" ]] || { echo 'Backup failed.' >&2; exit 1; }
echo 'Encrypted backup created. Test restoration on an isolated stack before relying on it.'
