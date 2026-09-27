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
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${CONFLUENCE_DB:?CONFLUENCE_DB is required}"
: "${CONFLUENCE_CONTAINER:?CONFLUENCE_CONTAINER is required}"
: "${CONFLUENCE_HOME_VOLUME:?CONFLUENCE_HOME_VOLUME is required}"

ARCHIVE=${1:-/tmp/confluence-migration-package.tar.gz}
CONFIRM=${2:-}
BASE=(-f "${ROOT}/docker-compose.jira.yml" -f "${ROOT}/docker-compose.confluence.yml" -f "${ROOT}/images.ghcr.yml")
PLATFORM=${ATLASSIAN_PLATFORM:-linux/amd64}

usage() {
  cat <<'EOF'
Usage:
  scripts/import-confluence-migration-package.sh ARCHIVE --yes

Destructively replaces the current Confluence database and Confluence Home.
It intentionally creates no backup. Jira is not modified.
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

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

psql_exec() {
  docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "$1" "${@:2}"
}

printf 'Archive: %s\n' "${ARCHIVE}"
gzip -t "${ARCHIVE}"
tar -tzf "${ARCHIVE}" | grep -qx 'conf70db.dump'
tar -tzf "${ARCHIVE}" | grep -qx 'confluence.cfg.xml.raw'
tar -tzf "${ARCHIVE}" | grep -q '^\./attachments/'

echo "Stopping ${CONFLUENCE_CONTAINER}..."
docker compose --env-file .env "${BASE[@]}" stop confluence

echo 'Replacing Confluence Home...'
cat "${ARCHIVE}" | docker run --rm -i --platform "${PLATFORM}" \
  -v "${CONFLUENCE_HOME_VOLUME}:/target" "${POSTGRES_IMAGE}" sh -ec '
    find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    tar -xzf - -C /target \
      --exclude="./index" \
      --exclude="./index/*" \
      --exclude="./journal" \
      --exclude="./journal/*" \
      --exclude="./analytics-logs" \
      --exclude="./analytics-logs/*" \
      --exclude="./restore" \
      --exclude="./restore/*" \
      --exclude="./database" \
      --exclude="./database/*" \
      --exclude="./.java" \
      --exclude="./.java/*" \
      --exclude="./*.cfg.xmlbackup*"
    rm -f /target/confluence.cfg.xml /target/conf70db.dump /target/confluence.cfg.xml.raw
    chown -R 2002:2002 /target
    test -d /target/attachments
  '

echo 'Rewriting Confluence database configuration...'
tar -xOzf "${ARCHIVE}" confluence.cfg.xml.raw > "${TMP_DIR}/confluence.cfg.xml"
# Portable in-place edit: BSD sed needs an argument for -i, so use a temp file.
sed \
  -e "s#<property name=\"hibernate.connection.url\">.*</property>#<property name=\"hibernate.connection.url\">jdbc:postgresql://postgres:5432/${CONFLUENCE_DB}</property>#" \
  -e "s#<property name=\"hibernate.connection.username\">.*</property>#<property name=\"hibernate.connection.username\">${POSTGRES_USER}</property>#" \
  -e "s#<property name=\"hibernate.connection.password\">.*</property>#<property name=\"hibernate.connection.password\">${POSTGRES_PASSWORD}</property>#" \
  -e "/jdbc.password.decrypter.classname/d" \
  "${TMP_DIR}/confluence.cfg.xml" > "${TMP_DIR}/confluence.cfg.xml.new"
mv "${TMP_DIR}/confluence.cfg.xml.new" "${TMP_DIR}/confluence.cfg.xml"

grep -q "postgres:5432/${CONFLUENCE_DB}" "${TMP_DIR}/confluence.cfg.xml"
if grep -q 'jdbc.password.decrypter.classname' "${TMP_DIR}/confluence.cfg.xml"; then
  echo 'ERROR: password decrypter property still present' >&2
  exit 1
fi

docker run --rm -i --platform "${PLATFORM}" \
  -v "${CONFLUENCE_HOME_VOLUME}:/target" "${POSTGRES_IMAGE}" sh -ec '
    cat > /target/confluence.cfg.xml
    chown 2002:2002 /target/confluence.cfg.xml
    chmod 640 /target/confluence.cfg.xml
  ' < "${TMP_DIR}/confluence.cfg.xml"

echo "Replacing database ${CONFLUENCE_DB}..."
psql_exec postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${CONFLUENCE_DB}' AND pid <> pg_backend_pid();"
psql_exec postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${CONFLUENCE_DB};"
psql_exec postgres -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE ${CONFLUENCE_DB} OWNER ${POSTGRES_USER} ENCODING 'UTF8' TEMPLATE template0;"

tar -xOzf "${ARCHIVE}" conf70db.dump \
  | docker exec -i "${POSTGRES_CONTAINER}" pg_restore -U "${POSTGRES_USER}" -d "${CONFLUENCE_DB}" \
      --no-owner --no-acl --exit-on-error

echo 'Starting Confluence...'
docker compose --env-file .env "${BASE[@]}" up -d --no-build confluence
docker compose --env-file .env "${BASE[@]}" restart nginx

printf 'tables='; psql_exec "${CONFLUENCE_DB}" -Atc \
  "select count(*) from information_schema.tables where table_schema='public';"
printf 'spaces='; psql_exec "${CONFLUENCE_DB}" -Atc 'select count(*) from spaces;' 2>/dev/null || true
printf 'content='; psql_exec "${CONFLUENCE_DB}" -Atc 'select count(*) from content;' 2>/dev/null || true
printf 'users='; psql_exec "${CONFLUENCE_DB}" -Atc 'select count(*) from cwd_user;' 2>/dev/null || true
printf 'attachment_files='; ls -1 "$(docker volume inspect "${CONFLUENCE_HOME_VOLUME}" --format '{{.Mountpoint}}')/attachments" 2>/dev/null | wc -l

cat <<EOF
Confluence import completed.
Check https://${CONFLUENCE_DOMAIN} after startup finishes.
EOF
