#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENV_FILE=${ENV_FILE:-${ROOT}/.env}

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${JIRA_BASE_IMAGE:?JIRA_BASE_IMAGE is required}"
: "${CONFLUENCE_BASE_IMAGE:?CONFLUENCE_BASE_IMAGE is required}"
: "${POSTGRES_IMAGE:?POSTGRES_IMAGE is required}"
: "${JIRA_GHCR_IMAGE:?JIRA_GHCR_IMAGE is required}"
: "${CONFLUENCE_GHCR_IMAGE:?CONFLUENCE_GHCR_IMAGE is required}"

for image in \
  "${JIRA_BASE_IMAGE}" \
  "${CONFLUENCE_BASE_IMAGE}" \
  "${POSTGRES_IMAGE}" \
  "${JIRA_GHCR_IMAGE}" \
  "${CONFLUENCE_GHCR_IMAGE}"; do
  echo "Checking ${image}"
  docker manifest inspect "${image}" >/dev/null
done

echo 'Validating GHCR Compose configuration'
docker compose --env-file "${ENV_FILE}" \
  -f "${ROOT}/docker-compose.jira.yml" \
  -f "${ROOT}/docker-compose.confluence.yml" \
  -f "${ROOT}/images.ghcr.yml" \
  config >/dev/null

echo 'Validating local-build Compose configuration'
docker compose --env-file "${ENV_FILE}" \
  -f "${ROOT}/docker-compose.jira.yml" \
  -f "${ROOT}/docker-compose.confluence.yml" \
  -f "${ROOT}/images.local.yml" \
  config >/dev/null

bash -n "${ROOT}"/scripts/*.sh

echo 'Atlassian configuration checks passed.'
