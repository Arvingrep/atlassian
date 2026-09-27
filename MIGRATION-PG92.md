# 迁移说明

## 环境

```text
Jira 9.6.0
Confluence 7.19.7
PostgreSQL 9.2
```

PostgreSQL 9.2 仅用于兼容旧数据。完成迁移验证后，应升级到 Atlassian 支持的数据库版本。

## Compose 文件

| 文件 | 用途 |
|---|---|
| `docker-compose.migration.yml` | 基础服务、数据卷和 nginx |
| `docker-compose.ghcr.yml` | 使用 GitHub 发布镜像 |
| `docker-compose.agent-demo.yml` | 本地构建镜像 |
| `docker-compose.jira-index-recovery.yml` | Jira 无索引时临时开放 UI |

## Jira 恢复

```bash
scripts/import-jira-migration-package.sh BACKUP.tar.gz --yes
```

导入完成后核对：

```bash
docker exec atlassian-pg92 psql -U atlassian -d jira -Atc \
  'select count(*) from jiraissue;'

docker exec atlassian-pg92 psql -U atlassian -d jira -Atc \
  'select count(*) from project;'
```

然后执行完整前台索引，最后运行：

```bash
scripts/finalize-jira-migration.sh
```

## Confluence 恢复

1. 停止 Confluence；
2. 恢复 PostgreSQL dump；
3. 恢复 Home、附件和插件数据；
4. 排除旧索引、缓存、日志和临时文件；
5. 修正文件属主；
6. 启动并重建搜索索引。

## 验收

- `/status` 返回 `RUNNING`；
- Jira Issue、项目、用户数量与源环境一致；
- Confluence 空间、页面、附件数量一致；
- 抽查近期附件；
- 检查商业插件授权和版本兼容性；
- 检查 Base URL 与 Application Links；
- PostgreSQL、Jira Home、Confluence Home 均使用持久卷。

## 注意

- 不要导入旧 `dbconfig.xml` 或 `confluence.cfg.xml` 中的生产凭据；
- 不要迁移 Lucene/OSGi 缓存；
- 不要公开包含许可证、Token 或数据库密码的日志；
- `down -v` 会删除恢复数据，除非明确重置环境，否则不要使用。
