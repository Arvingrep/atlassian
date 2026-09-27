#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

: "${POSTGRES_CONTAINER:?POSTGRES_CONTAINER is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${JIRA_DB:?JIRA_DB is required}"
: "${JIRA_CONTAINER:?JIRA_CONTAINER is required}"
: "${JIRA_DOMAIN:?JIRA_DOMAIN is required}"
: "${JIRA_PORT:?JIRA_PORT is required}"
: "${HTTP_PORT:?HTTP_PORT is required}"

ARCHIVE=${1:-/tmp/jira-migration-package.tar.gz}
CONFIRM=${2:-}
JIRA_HOME_VOLUME=${JIRA_HOME_VOLUME:-${COMPOSE_PROJECT_NAME:-atlassian}_jira_home}
BASE=(-f "${ROOT}/docker-compose.jira.yml" -f "${ROOT}/docker-compose.confluence.yml" -f "${ROOT}/images.ghcr.yml")
RECOVERY=(-f "${ROOT}/docker-compose.jira-index-recovery.yml")

usage() {
  cat <<'EOF'
Usage:
  scripts/import-jira-migration-package.sh ARCHIVE --yes

Destructively replaces the current Jira database and Jira Home. It intentionally
creates no backup. Confluence is not modified.
EOF
}

if [[ "${ARCHIVE}" == "--help" || "${ARCHIVE}" == "-h" ]]; then
  usage
  exit 0
fi
if [[ "${CONFIRM}" != "--yes" ]]; then
  usage >&2
  echo "ERROR: pass --yes to confirm destructive replacement" >&2
  exit 2
fi
if [[ ! -f "${ARCHIVE}" ]]; then
  echo "ERROR: archive not found: ${ARCHIVE}" >&2
  exit 2
fi

cd "${ROOT}"
export COMPOSE_PROJECT_NAME

psql_exec() {
  docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "$1" "${@:2}"
}

printf 'Archive: %s\n' "${ARCHIVE}"
gzip -t "${ARCHIVE}"
tar -tzf "${ARCHIVE}" | grep -qx 'jira_invd_db.dump'
tar -tzf "${ARCHIVE}" | grep -q '^\./data/attachments/'

echo "Stopping ${JIRA_CONTAINER}..."
docker compose --env-file .env "${BASE[@]}" stop jira

echo 'Replacing Jira Home...'
cat "${ARCHIVE}" | docker run --rm -i --platform "${ATLASSIAN_PLATFORM:-linux/amd64}" \
  -v "${JIRA_HOME_VOLUME}:/target" "${POSTGRES_IMAGE}" sh -ec '
    find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    tar -xzf - -C /target \
      --exclude="./caches" \
      --exclude="./caches/*" \
      --exclude="./plugins/.osgi-plugins" \
      --exclude="./plugins/.osgi-plugins/*" \
      --exclude="./plugins/.bundled-plugins" \
      --exclude="./plugins/.bundled-plugins/*" \
      --exclude="./plugins/install-app-info" \
      --exclude="./plugins/install-app-info/*"
    chown -R 2001:2001 /target
    test -f /target/jira_invd_db.dump
  '

echo "Replacing database ${JIRA_DB}..."
psql_exec postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${JIRA_DB}' AND pid <> pg_backend_pid();"
psql_exec postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${JIRA_DB};"
psql_exec postgres -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE ${JIRA_DB} OWNER ${POSTGRES_USER} ENCODING 'UTF8' TEMPLATE template0;"

docker run --rm --platform "${ATLASSIAN_PLATFORM:-linux/amd64}" -v "${JIRA_HOME_VOLUME}:/source" "${POSTGRES_IMAGE}" \
  cat /source/jira_invd_db.dump \
  | docker exec -i "${POSTGRES_CONTAINER}" pg_restore -U "${POSTGRES_USER}" -d "${JIRA_DB}" \
      --no-owner --no-acl --exit-on-error

echo 'Removing dump and old database reference config...'
docker run --rm --platform "${ATLASSIAN_PLATFORM:-linux/amd64}" -v "${JIRA_HOME_VOLUME}:/target" "${POSTGRES_IMAGE}" sh -ec '
  rm -f /target/jira_invd_db.dump /target/dbconfig.xml.raw /target/dbconfig.xml
  chown -R 2001:2001 /target
'

echo 'Starting Jira in index-recovery access mode...'
docker compose --env-file .env "${BASE[@]}" "${RECOVERY[@]}" up -d --no-build jira
docker compose --env-file .env "${BASE[@]}" restart nginx

printf 'tables='; psql_exec "${JIRA_DB}" -Atc \
  "select count(*) from information_schema.tables where table_schema='public';"
printf 'issues='; psql_exec "${JIRA_DB}" -Atc 'select count(*) from jiraissue;'
printf 'projects='; psql_exec "${JIRA_DB}" -Atc 'select count(*) from project;'
printf 'users='; psql_exec "${JIRA_DB}" -Atc 'select count(*) from app_user;'

cat <<EOF
Import completed. Jira starts with the index consistency gate temporarily
disabled because Lucene indexes are deliberately not migrated.

Next:
1. Open http://${JIRA_DOMAIN}
2. Run a full foreground reindex.
3. Run scripts/finalize-jira-migration.sh to remove recovery mode.
EOF
