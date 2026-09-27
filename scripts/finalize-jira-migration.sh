#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

: "${JIRA_DOMAIN:?JIRA_DOMAIN is required}"
: "${HTTP_PORT:?HTTP_PORT is required}"

cd "${ROOT}"
export COMPOSE_PROJECT_NAME

status_json=$(curl -sS --max-time 15 -H "Host: ${JIRA_DOMAIN}" "http://127.0.0.1:${HTTP_PORT}/status" || true)
echo "Current status: ${status_json}"

if ! echo "${status_json}" | grep -q 'RUNNING'; then
  echo 'ERROR: Jira index is not healthy yet. Complete a full foreground reindex first.' >&2
  exit 1
fi

docker compose --env-file .env \
  -f docker-compose.jira.yml \
  -f docker-compose.confluence.yml \
  -f images.ghcr.yml \
  up -d --no-build --force-recreate jira

docker compose --env-file .env \
  -f docker-compose.jira.yml \
  -f docker-compose.confluence.yml \
  -f images.ghcr.yml \
  restart nginx

echo 'Recovery-mode JVM property removed. Recheck /status after Jira finishes restarting.'
