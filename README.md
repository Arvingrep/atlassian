# Atlassian 迁移环境

用于恢复和验证旧 Atlassian 数据。

| 组件 | 版本 |
|---|---|
| Jira Software | 9.6.0 / JDK 11 |
| Confluence | 7.19.7 / JDK 11 |
| PostgreSQL | 9.2 |

> PostgreSQL 9.2 已停止维护。本环境仅用于迁移验证，后续应升级到受支持版本。

## 配置

所有变量集中在 `.env`，Compose 默认读取该文件。

| 分组 | 变量 |
|---|---|
| 项目 | `COMPOSE_PROJECT_NAME`、`TZ`、`ATLASSIAN_PLATFORM`、`ATLASSIAN_JAVA_TAG` |
| 镜像 | `NGINX_IMAGE`、`POSTGRES_IMAGE`、`JIRA_BASE_IMAGE`、`CONFLUENCE_BASE_IMAGE`、`JIRA_GHCR_IMAGE`、`CONFLUENCE_GHCR_IMAGE`、`JIRA_LOCAL_IMAGE`、`CONFLUENCE_LOCAL_IMAGE` |
| 数据库 | `POSTGRES_USER`、`POSTGRES_PASSWORD`、`POSTGRES_CONTAINER`、`POSTGRES_VOLUME`、`POSTGRES_PORT`、`POSTGRES_MAX_CONNECTIONS`、`JIRA_DB`、`CONFLUENCE_DB` |
| Jira | `JIRA_CONTAINER`、`JIRA_DOMAIN`、`JIRA_PORT`、`JIRA_HOME_VOLUME`、`JIRA_XMS`、`JIRA_XMX` |
| Confluence | `CONFLUENCE_CONTAINER`、`CONFLUENCE_DOMAIN`、`CONFLUENCE_PORT`、`CONFLUENCE_SYNCHRONY_PORT`、`CONFLUENCE_HOME_VOLUME`、`CONFLUENCE_XMS`、`CONFLUENCE_XMX` |
| nginx | `NGINX_CONTAINER`、`HTTP_PORT` |

## 文件

| 文件 | 用途 |
|---|---|
| `docker-compose.jira.yml` | PostgreSQL、Jira、nginx 和数据卷 |
| `docker-compose.confluence.yml` | PostgreSQL、Confluence 和数据卷 |
| `images.ghcr.yml` | 使用 GitHub Container Registry 镜像 |
| `images.local.yml` | 使用本地 Dockerfile 构建镜像 |
| `docker-compose.jira-index-recovery.yml` | Jira 无索引时临时开放 UI |

## 启动

```bash
# GHCR 镜像
docker compose \
  -f docker-compose.jira.yml \
  -f docker-compose.confluence.yml \
  -f images.ghcr.yml \
  up -d --pull always --no-build
```

首次使用空 PostgreSQL 数据卷时，`JIRA_DB` 会自动创建；启动 Confluence 前创建一次它的数据库：

```bash
docker exec atlassian-pg92 createdb -U atlassian -O atlassian confluence
```

数据库名、用户名和容器名均可在 `.env` 中调整。

本地构建：

```bash
# Jira
docker compose -f docker-compose.jira.yml -f images.local.yml up -d --build

# Confluence
docker compose -f docker-compose.confluence.yml -f images.local.yml up -d --build
```

访问：

- Jira：`http://alpha-jira.sl-devops.com`
- Confluence：`http://confsys.sl-devops.com`

本机 `/etc/hosts`：

```text
192.168.254.101 alpha-jira.sl-devops.com
192.168.254.101 confsys.sl-devops.com
```

## Jira 备份导入

该脚本会直接覆盖当前 Jira 数据库和 Jira Home，不创建测试环境备份：

```bash
scripts/import-jira-migration-package.sh /tmp/jira-migration-package.tar.gz --yes
```

导入完成后执行：

```text
Administration → System → Indexing → Full foreground re-index
```

索引完成后退出恢复模式：

```bash
scripts/finalize-jira-migration.sh
```

## 验收

```bash
docker compose \
  -f docker-compose.jira.yml \
  -f docker-compose.confluence.yml \
  -f images.ghcr.yml ps

curl -H 'Host: alpha-jira.sl-devops.com' http://127.0.0.1/status
curl -I -H 'Host: confsys.sl-devops.com' http://127.0.0.1/

docker logs -f --tail=200 jira-9.6.0
docker logs -f --tail=200 confluence-7.19.7
```

验收内容：

- Jira `/status` 返回 `RUNNING`；
- Issue、项目、用户、空间和页面数量与源环境一致；
- 抽查附件；
- 检查插件版本与授权；
- 检查 Base URL 和 Application Links；
- 完成 Jira 与 Confluence 索引重建。

## 停止

```bash
docker compose \
  -f docker-compose.jira.yml \
  -f docker-compose.confluence.yml \
  -f images.ghcr.yml down
```

不要使用 `down -v`，除非明确要删除全部迁移数据。

## CI

修改 `.env`、Compose、Dockerfile 或镜像配置后，GitHub Actions 会检查：

- Jira、Confluence、PostgreSQL 镜像标签；
- GHCR 镜像是否存在；
- GHCR 与本地构建两套 Compose 配置；
- Shell 脚本语法。

手动触发时可临时指定 Jira、Confluence 和 Java 版本，工作流会生成 `.env.ci` 覆盖版本变量。
