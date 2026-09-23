#!/usr/bin/env bash
# Add or remove a player on the running LOCAL server and keep server/server.env
# in sync so the change survives a redeploy.
#   scripts/whitelist.sh add Steve
#   scripts/whitelist.sh remove Steve
set -euo pipefail
cd "$(dirname "$0")/.."

action="${1:-}"; name="${2:-}"
if [[ -z "$action" || -z "$name" ]]; then
  echo "usage: $0 add|remove <username>" >&2; exit 2
fi

env_file=server/server.env
current=$(grep -E '^WHITELIST=' "$env_file" | cut -d= -f2-)
IFS=',' read -r -a names <<<"$current"

case "$action" in
  add)
    docker compose exec mc rcon-cli whitelist add "$name"
    if ! printf '%s\n' "${names[@]}" | grep -qix "$name"; then
      names+=("$name")
    fi
    ;;
  remove)
    docker compose exec mc rcon-cli whitelist remove "$name"
    docker compose exec mc rcon-cli kick "$name" "Removed from whitelist" || true
    mapfile -t names < <(printf '%s\n' "${names[@]}" | grep -vix "$name" || true)
    ;;
  *) echo "unknown action: $action" >&2; exit 2 ;;
esac

joined=$(IFS=','; echo "${names[*]}")
sed -i.bak -E "s|^WHITELIST=.*|WHITELIST=${joined}|" "$env_file" && rm -f "$env_file.bak"
echo "WHITELIST=${joined}"
echo "Commit server/server.env so the AWS deployment picks it up (make deploy)."
