#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ARCHIVE=${1:-/Users/arvin/Downloads/jira-migration-package.tar.gz}
CONFIRM=${2:-}
BASE=(-f "${ROOT}/docker-compose.migration.yml" -f "${ROOT}/docker-compose.ghcr.yml")
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
export COMPOSE_PROJECT_NAME=atlassian

printf 'Archive: %s\n' "${ARCHIVE}"
gzip -t "${ARCHIVE}"
tar -tzf "${ARCHIVE}" | grep -qx 'jira_invd_db.dump'
tar -tzf "${ARCHIVE}" | grep -q '^\./data/attachments/'

echo 'Stopping Jira...'
docker compose --env-file .env.versions "${BASE[@]}" stop jira

echo 'Replacing Jira Home...'
cat "${ARCHIVE}" | docker run --rm -i --platform linux/amd64 \
  -v atlassian_jira_home:/target postgres:9.2 sh -ec '
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

echo 'Replacing Jira database...'
docker exec atlassian-pg92 psql -U atlassian -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='jira' AND pid <> pg_backend_pid();"
docker exec atlassian-pg92 psql -U atlassian -d postgres -v ON_ERROR_STOP=1 \
  -c 'DROP DATABASE IF EXISTS jira;'
docker exec atlassian-pg92 psql -U atlassian -d postgres -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE jira OWNER atlassian ENCODING 'UTF8' TEMPLATE template0;"

docker run --rm --platform linux/amd64 -v atlassian_jira_home:/source postgres:9.2 \
  cat /source/jira_invd_db.dump \
  | docker exec -i atlassian-pg92 pg_restore -U atlassian -d jira \
      --no-owner --no-acl --exit-on-error

echo 'Removing dump and old database reference config...'
docker run --rm --platform linux/amd64 -v atlassian_jira_home:/target postgres:9.2 sh -ec '
  rm -f /target/jira_invd_db.dump /target/dbconfig.xml.raw /target/dbconfig.xml
  chown -R 2001:2001 /target
'

echo 'Starting Jira in index-recovery access mode...'
docker compose --env-file .env.versions "${BASE[@]}" "${RECOVERY[@]}" up -d --no-build jira
docker compose --env-file .env.versions "${BASE[@]}" restart nginx

printf 'tables='; docker exec atlassian-pg92 psql -U atlassian -d jira -Atc \
  "select count(*) from information_schema.tables where table_schema='public';"
printf 'issues='; docker exec atlassian-pg92 psql -U atlassian -d jira -Atc 'select count(*) from jiraissue;'
printf 'projects='; docker exec atlassian-pg92 psql -U atlassian -d jira -Atc 'select count(*) from project;'
printf 'users='; docker exec atlassian-pg92 psql -U atlassian -d jira -Atc 'select count(*) from app_user;'

cat <<'EOF'
Import completed. Jira starts with the index consistency gate temporarily
disabled because Lucene indexes are deliberately not migrated.

Next:
1. Log in to Jira.
2. Run a full foreground reindex.
3. Run scripts/finalize-jira-migration.sh to remove recovery mode.
EOF
