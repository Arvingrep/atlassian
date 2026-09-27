#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSIONS_FILE=${VERSIONS_FILE:-${ROOT}/.env.versions}

set -a
# shellcheck disable=SC1090
source "${VERSIONS_FILE}"
set +a

: "${JIRA_VERSION:?JIRA_VERSION is required}"
: "${CONFLUENCE_VERSION:?CONFLUENCE_VERSION is required}"
: "${ATLASSIAN_JAVA_TAG:?ATLASSIAN_JAVA_TAG is required}"

jira_base="atlassian/jira-software:${JIRA_VERSION}-${ATLASSIAN_JAVA_TAG}"
confluence_base="atlassian/confluence-server:${CONFLUENCE_VERSION}-${ATLASSIAN_JAVA_TAG}"
jira_ghcr="ghcr.io/arvingrep/atlassian-jira:${JIRA_VERSION}-example-agent"
confluence_ghcr="ghcr.io/arvingrep/atlassian-confluence:${CONFLUENCE_VERSION}-example-agent"

for image in "${jira_base}" "${confluence_base}" postgres:9.2 "${jira_ghcr}" "${confluence_ghcr}"; do
  echo "Checking ${image}"
  docker manifest inspect "${image}" >/dev/null
done

echo 'Validating GHCR Compose configuration'
docker compose --env-file "${VERSIONS_FILE}" \
  -f "${ROOT}/docker-compose.jira.yml" \
  -f "${ROOT}/docker-compose.confluence.yml" \
  -f "${ROOT}/images.ghcr.yml" \
  config >/dev/null

bash -n \
  "${ROOT}/scripts/check-upgrade.sh" \
  "${ROOT}/scripts/check-java-agent.sh" \
  "${ROOT}/scripts/import-jira-migration-package.sh" \
  "${ROOT}/scripts/finalize-jira-migration.sh"

echo 'Atlassian configuration checks passed.'
