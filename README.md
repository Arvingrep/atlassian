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
| nginx | `NGINX_CONTAINER`、`HTTP_PORT`、`HTTPS_PORT`、`NGINX_TLS_CERT`、`NGINX_TLS_KEY` |
| 对外协议 | `ATL_PROXY_PORT`、`ATL_TOMCAT_SCHEME` |

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

- Jira：`https://alpha-jira.sl-devops.com`
- Confluence：`https://confsys.sl-devops.com`

`HTTP_PORT` 只做 301 跳转到 HTTPS。

## TLS

nginx 监听 `443`，使用通配符证书：

```text
CN=*.sl-devops.com
SAN: *.sl-devops.com, sl-devops.com
签发：Certum DV TLS G2 R39 CA
有效期至：2026-12-11
```


Compose 以只读方式挂载到容器：

```text
/etc/nginx/certs/tls.crt
/etc/nginx/certs/tls.key
```

路径通过 `.env` 的 `NGINX_TLS_CERT`、`NGINX_TLS_KEY` 指定。证书文件不进入 Git 仓库；路径变化时直接改 `.env`。


## Jira 备份导入

该脚本会直接覆盖当前 Jira 数据库和 Jira Home，不创建测试环境备份：

```bash
scripts/import-jira-migration-package.sh /tmp/jira-migration-package.tar.gz --yes
```

导入完成后执行：

```text
Administration → System → Indexing → Full foreground re-index
```

也可以用管理员账号通过 REST 触发（无需打开 UI）：

```bash
curl -k --resolve alpha-jira.sl-devops.com:443:127.0.0.1 \
  -c /tmp/jc.txt -b /tmp/jc.txt \
  -d 'os_username=ADMIN&os_password=PASSWORD&login=Log+in' \
  https://alpha-jira.sl-devops.com/login.jsp

curl -k --resolve alpha-jira.sl-devops.com:443:127.0.0.1 \
  -b /tmp/jc.txt -H 'Content-Type: application/json' \
  -H 'X-Atlassian-Token: no-check' \
  -X POST -d '{"type":"foreground"}' \
  https://alpha-jira.sl-devops.com/rest/api/2/reindex
```

返回的 `progressUrl` 可轮询进度；完成后 `/status` 变为 `RUNNING`。

索引完成后退出恢复模式：

```bash
scripts/finalize-jira-migration.sh
```

## Confluence 备份导入

```bash
scripts/import-confluence-migration-package.sh \
  /tmp/confluence-migration-package.tar.gz --yes
```

脚本会：

1. 停止 Confluence；
2. 恢复 Home，保留 `attachments/` 与 `shared-home/`，排除 `index/`、`journal/`、`analytics-logs/`、`restore/`、`database/`；
3. 由 `confluence.cfg.xml.raw` 生成新配置，改写连接串并删除 `jdbc.password.decrypter.classname`；
4. 重建数据库并恢复 `conf70db.dump`；
5. 属主改为 `2002:2002`；
6. 启动并输出表、空间、内容、页面、用户和附件数量。

导入后需在 `General Configuration → General` 核对 Base URL 为：

```text
https://confsys.sl-devops.com
```

数据库中的旧域名引用可用 SQL 批量替换，`bandana` 表涉及：

```text
atlassian.confluence.settings             baseUrl
synchrony_collaborative_editor_app_base_url
com.atlassian.plugins.custom_apps.customAppsAsJSON
com.atlassian.oauth.consumer.ConsumerService:host.__HOST_SERVICE__
applinks.admin.<id>.display.url / .rpc.url
```


## 用户目录与登录

源环境的 Confluence 用户由 **Jira 内嵌 Crowd** 提供（目录 `Jira Server`，`crowd.server.url` 原为 `http://10.146.40.69:8667`）。迁移后该地址不可达，因此 Crowd 目录里的账号（426 个，含 `corwin`）无法认证，登录会被拒。

两种处理方式：

1. 长期方案：把该目录的 `crowd.server.url` 指向迁移后的 Jira，并确认应用 `Conf70UserGroup` 的远程地址白名单包含 Confluence 容器网段，再验证 Crowd REST。
2. 临时方案：在 Confluence 内部目录建立同名本地账号（复用同一 PKCS5S2 凭据哈希），使该用户可以登录；Crowd 恢复后删除本地账号。

临时账号的清理 SQL：

```sql
DELETE FROM cwd_membership m USING cwd_user u
  WHERE m.child_user_id = u.id AND u.directory_id = 360449 AND u.lower_user_name = 'corwin';
DELETE FROM cwd_user WHERE directory_id = 360449 AND lower_user_name = 'corwin';
```

## 验收

```bash
docker compose \
  -f docker-compose.jira.yml \
  -f docker-compose.confluence.yml \
  -f images.ghcr.yml ps

curl -k --resolve alpha-jira.sl-devops.com:443:127.0.0.1 https://alpha-jira.sl-devops.com/status
curl -Ik --resolve confsys.sl-devops.com:443:127.0.0.1 https://confsys.sl-devops.com/

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
