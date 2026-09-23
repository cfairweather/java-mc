#!/usr/bin/env bash
# Run a command inside a container of the running ECS task via ECS Exec.
#   scripts/aws-exec.sh mc rcon-cli list
#   scripts/aws-exec.sh backup backup now
set -euo pipefail
cd "$(dirname "$0")/.."
container="${1:?container name (mc|backup)}"; shift
tf="terraform -chdir=infra/terraform"
region=$($tf output -raw region)
cluster=$($tf output -raw ecs_cluster)
service=$($tf output -raw ecs_service)
task=$(aws ecs list-tasks --region "$region" --cluster "$cluster" --service-name "$service" \
  --query 'taskArns[0]' --output text)
if [[ -z "$task" || "$task" == "None" ]]; then
  echo "No running task for service $service" >&2; exit 1
fi
if [[ $# -eq 0 ]]; then
  cmd="/bin/bash"
else
  cmd=$(printf '%q ' "$@")
fi
exec aws ecs execute-command --region "$region" --cluster "$cluster" --task "$task" \
  --container "$container" --interactive --command "$cmd"
