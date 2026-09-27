#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "${ROOT}"

status_json=$(curl -sS --max-time 15 -H 'Host: alpha-jira.sl-devops.com' http://127.0.0.1/status || true)
echo "Current status: ${status_json}"

if ! echo "${status_json}" | grep -q 'RUNNING'; then
  echo 'ERROR: Jira index is not healthy yet. Complete a full foreground reindex first.' >&2
  exit 1
fi

docker compose --env-file .env.versions \
  -f docker-compose.migration.yml \
  -f docker-compose.ghcr.yml \
  up -d --no-build --force-recreate jira

docker compose --env-file .env.versions \
  -f docker-compose.migration.yml \
  -f docker-compose.ghcr.yml \
  restart nginx

echo 'Recovery-mode JVM property removed. Recheck /status after Jira finishes restarting.'
