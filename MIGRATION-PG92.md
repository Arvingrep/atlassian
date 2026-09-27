# Jira 9.6.0 / Confluence 7.19.7 migration lab

This branch adds an isolated migration stack in `docker-compose.migration.yml`:

- Jira Software 9.6.0 (Java 11)
- Confluence 7.19.7 (Java 11)
- PostgreSQL 9.2
- Separate `jira` and `confluence` databases
- Persistent Docker volumes for both application homes and PostgreSQL

> PostgreSQL 9.2 is end-of-life and is outside the supported database matrix for
> these Atlassian releases. This stack is only for reproducing and extracting a
> legacy installation. Do not expose it to the Internet or use it as the final
> production target. After validating the restored data, upgrade PostgreSQL to a
> supported version before cutover.

## Capacity planning from the source inventory

The supplied inventory shows roughly 51 GB Jira home, 140 GB Confluence home,
1.2 GB Jira DB and 4.5 GB Confluence DB. Keep at least 250 GB free for the lab;
350 GB is safer while dumps, attachment copies and temporary indexes coexist.
The Confluence `backups` directory (about 107 GB) should not be copied into the
new application home unless a specific historical ZIP is required.

## Start the empty lab

```bash
export POSTGRES_PASSWORD='replace-with-a-local-only-password'
docker compose -f docker-compose.migration.yml config
docker compose -f docker-compose.migration.yml up -d postgres
docker compose -f docker-compose.migration.yml ps
```

On Apple Silicon, the compose file deliberately uses `linux/amd64` because the
legacy PostgreSQL 9.2 image has no native ARM64 build.

## Restore database dumps

Put custom-format or plain SQL dumps in `migration/import/`. Examples:

```bash
# Custom pg_dump format
docker compose -f docker-compose.migration.yml exec -T postgres \
  pg_restore -U atlassian -d jira --clean --if-exists --no-owner \
  < migration/import/jira.dump

docker compose -f docker-compose.migration.yml exec -T postgres \
  pg_restore -U atlassian -d confluence --clean --if-exists --no-owner \
  < migration/import/confluence.dump

# Plain SQL alternative
# docker compose -f docker-compose.migration.yml exec -T postgres \
#   psql -U atlassian -d jira < migration/import/jira.sql
```

If the dump was made by a newer `pg_dump`, restore it with a matching client
rather than PostgreSQL 9.2's bundled `pg_restore`.

## Restore application homes

Stop the application containers before copying files. Restore the active Jira
home and Confluence home, especially attachments and configuration. Exclude
rebuildable or disposable content such as caches, logs, temporary files,
Confluence thumbnails/indexes, Jira indexes, and old local backup ZIPs.

The named-volume locations can be inspected with:

```bash
docker volume inspect atlassian_jira_home
docker volume inspect atlassian_confluence_home
```

After copying, ensure the container user owns the files. Then start and inspect:

```bash
docker compose -f docker-compose.migration.yml up -d jira confluence
docker compose -f docker-compose.migration.yml logs -f --tail=200 jira confluence
```

Endpoints:

- Jira: `http://localhost:8080`
- Confluence: `http://localhost:8090`
- PostgreSQL (host access): `localhost:15432`

## Validation checklist

- Jira and Confluence versions match the source exactly.
- Database restore completes without missing roles/extensions.
- Application startup has no schema-upgrade or unsupported-database blocker.
- User/project/space counts match the source.
- Recent Jira attachments and Confluence page attachments open correctly.
- Installed apps are checked for version compatibility; do not blindly copy
  plugin caches.
- Rebuild Jira indexes and Confluence search indexes after the content check.
- Take a fresh database dump and application-home snapshot before the next
  PostgreSQL/application upgrade step.

## Tear down

```bash
docker compose -f docker-compose.migration.yml down
```

Add `-v` only when you intentionally want to delete all restored test data.
