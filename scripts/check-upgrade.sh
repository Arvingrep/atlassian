#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSIONS_FILE=${VERSIONS_FILE:-${ROOT}/.env.versions}

if [[ ! -f "${VERSIONS_FILE}" ]]; then
  echo "missing versions file: ${VERSIONS_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${VERSIONS_FILE}"
set +a

: "${JIRA_VERSION:?JIRA_VERSION is required}"
: "${CONFLUENCE_VERSION:?CONFLUENCE_VERSION is required}"
: "${ATLASSIAN_JAVA_TAG:?ATLASSIAN_JAVA_TAG is required}"

jira_image="atlassian/jira-software:${JIRA_VERSION}-${ATLASSIAN_JAVA_TAG}"
confluence_image="atlassian/confluence-server:${CONFLUENCE_VERSION}-${ATLASSIAN_JAVA_TAG}"

printf 'Checking %s\n' "${jira_image}"
docker manifest inspect "${jira_image}" >/dev/null
printf 'Checking %s\n' "${confluence_image}"
docker manifest inspect "${confluence_image}" >/dev/null
printf 'Checking postgres:9.2\n'
docker manifest inspect postgres:9.2 >/dev/null

rendered=$(mktemp)
trap 'rm -f "${rendered}"' EXIT

docker compose \
  --env-file "${VERSIONS_FILE}" \
  -f "${ROOT}/docker-compose.migration.yml" \
  config >"${rendered}"

grep -Fq "image: ${jira_image}" "${rendered}"
grep -Fq "image: ${confluence_image}" "${rendered}"
grep -Fq 'image: postgres:9.2' "${rendered}"

echo "Upgrade configuration checks passed."
