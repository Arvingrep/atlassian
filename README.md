# Atlassian 本地迁移环境

用于恢复和验证旧 Atlassian 环境：

| 组件 | 版本 |
|---|---|
| Jira Software | 9.6.0 / JDK 11 |
| Confluence | 7.19.7 / JDK 11 |
| PostgreSQL | 9.2 |
| 入口域名 | `alpha-jira.sl-devops.com` / `confsys.sl-devops.com` |

> PostgreSQL 9.2 已停止维护。本环境仅用于迁移和验证，不应作为最终生产环境。

## 快速启动

```bash
export POSTGRES_PASSWORD='本地数据库密码'

docker compose --env-file .env.versions \
  -f docker-compose.migration.yml \
  -f docker-compose.ghcr.yml \
  up -d --pull always --no-build
```

访问：

- Jira：`http://alpha-jira.sl-devops.com`
- Confluence：`http://confsys.sl-devops.com`

本机 DNS：

```text
192.168.254.101 alpha-jira.sl-devops.com
192.168.254.101 confsys.sl-devops.com
```

## Jira 数据导入

导入脚本会覆盖当前 Jira 数据库和 Jira Home，不创建测试数据备份：

```bash
scripts/import-jira-migration-package.sh \
  /Users/arvin/Downloads/jira-migration-package.tar.gz \
  --yes
```

脚本会：

1. 校验备份包；
2. 停止 Jira；
3. 恢复 Jira Home，排除索引和插件缓存；
4. 重建并恢复 PostgreSQL 数据库；
5. 删除旧数据库配置和 dump；
6. 修正目录权限；
7. 以索引恢复模式启动 Jira。

恢复后必须登录 Jira 执行：

```text
Administration → System → Indexing → Full foreground re-index
```

索引完成后退出恢复模式：

```bash
scripts/finalize-jira-migration.sh
```

## 常用命令

```bash
# 状态
docker compose --env-file .env.versions \
  -f docker-compose.migration.yml \
  -f docker-compose.ghcr.yml ps

# 日志
docker logs -f --tail=200 jira-9.6.0
docker logs -f --tail=200 confluence-7.19.7

# 停止并保留数据
docker compose --env-file .env.versions \
  -f docker-compose.migration.yml \
  -f docker-compose.ghcr.yml down
```

## 镜像

```text
ghcr.io/arvingrep/atlassian-jira:9.6.0-example-agent
ghcr.io/arvingrep/atlassian-confluence:7.19.7-example-agent
ghcr.io/arvingrep/atlassian-example-agent:latest
```

Jira 和 Confluence 旧版基础镜像仅支持 `linux/amd64`。Apple Silicon 使用 amd64 模拟运行。

## Java Agent 示例

镜像包含无类转换、无授权修改功能的教学 Agent：

```text
/var/agent/example-agent.jar
```

检查 JVM 参数：

```bash
scripts/check-java-agent.sh jira-9.6.0
scripts/check-java-agent.sh confluence-7.19.7
```

详细说明见 `example-agent/README.md`。

## CI

GitHub Actions 会：

- 校验版本和 Compose；
- 测试 `premain()`；
- 构建并发布 GHCR 镜像；
- 验证 PostgreSQL 初始化。

修改版本：编辑 `.env.versions` 后提交分支。
