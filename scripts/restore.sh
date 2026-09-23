#!/usr/bin/env bash
# Restore a restic snapshot into the LOCAL mc-data volume.
#   scripts/restore.sh latest
#   scripts/restore.sh 3f2a1b4c
# Takes a safety snapshot, stops the server, wipes /data, restores, starts
# again. Mods and libraries are excluded from backups and re-downloaded on the
# next start, so the first boot after a restore takes a few minutes.
set -euo pipefail
cd "$(dirname "$0")/.."
snapshot="${1:-latest}"

set -a
# shellcheck disable=SC1091
source .env
set +a
: "${RESTIC_PASSWORD:?set RESTIC_PASSWORD in .env}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/restic}"
BACKUP_IMAGE="${BACKUP_IMAGE:-itzg/mc-backup:2026.9.2}"
volume="$(docker compose config --format json | python3 -c 'import json,sys; c=json.load(sys.stdin); print(c["volumes"]["mc-data"]["name"])')"

echo ">> Taking a safety snapshot of the current data"
docker compose exec -T backup backup now

echo ">> Stopping the server"
docker compose stop mc

echo ">> Restoring snapshot ${snapshot} into volume ${volume}"
docker run --rm \
  -v "${volume}:/data" -v "$PWD/backups:/backups" \
  -e RESTIC_REPOSITORY="$RESTIC_REPOSITORY" -e RESTIC_PASSWORD="$RESTIC_PASSWORD" \
  --entrypoint sh "$BACKUP_IMAGE" -c \
  'export PATH=/opt:$PATH; restic cat snapshot "$1" >/dev/null && find /data -mindepth 1 -delete && restic restore "$1" --target / --path /data && chown -R 1000:1000 /data' \
  _ "$snapshot"

echo ">> Starting the server"
docker compose start mc
echo "Restored ${snapshot}. Watch it come up with: make logs"
