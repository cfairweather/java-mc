#!/usr/bin/env bash
# Restore a restic snapshot into the LOCAL mc-data volume.
#   scripts/restore.sh latest
#   scripts/restore.sh 3f2a1b4c
# Stops the server, wipes /data, restores, and starts again. The current /data
# is snapshotted first so this is reversible.
set -euo pipefail
cd "$(dirname "$0")/.."
snapshot="${1:-latest}"

echo ">> Taking a safety snapshot of the current data"
docker compose exec backup backup now

echo ">> Stopping the server"
docker compose stop mc

echo ">> Restoring snapshot ${snapshot}"
docker compose run --rm --no-deps -v java-mc_mc-data:/data backup \
  sh -c 'find /data -mindepth 1 -delete && restic restore "$0" --target / --path /data' "$snapshot"

echo ">> Starting the server"
docker compose start mc
echo "Restored ${snapshot}. Watch it come up with: make logs"
