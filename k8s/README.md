# K8s 测试部署（官方 Atlassian Data Center Helm charts）

目标集群：MacBook 本地 OrbStack Kubernetes（`kubectl --context orbstack`），仅用于验证 chart 可行性。

## 集群事实

```text
节点     orbstack  18 CPU / 15.7 GiB RAM / 703 GiB ephemeral
存储     local-path（唯一 StorageClass，RWO）
入口     无 Ingress Controller（测试阶段用 port-forward）
Helm     v4.2.4
```

官方 chart 默认要求 shared-home 为 RWX，但 chart 文档明确说明单节点场景可用 `ReadWriteOnce`，因此本测试把 `sharedHome.accessModes` 设为 `ReadWriteOnce`。

## 与现有 compose 环境的差异

| 项目 | compose 环境 | K8s 测试 |
|---|---|---|
| 部署方式 | docker compose | 官方 DC chart 2.0.15 |
| 数据库 | PostgreSQL 9.2 | PostgreSQL 14（chart 要求 12+） |
| 应用版本 | Jira 9.6.0 / Confluence 7.19.7 | 通过 `image.tag` 固定到同版本 |
| 许可证 | 数据库内 | Confluence 走 Secret / Jira 走安装向导 |
| Home 目录 | Docker volume | localHome / sharedHome PVC |
| 入口 | nginx + 通配证书 | port-forward（后续可加 Ingress） |

## 目录

```text
k8s/
  manifests/postgres.yaml        集群内 PostgreSQL 14 + jira/confluence 库
  values-jira-dc.yaml           Jira DC chart values（官方镜像）
  values-jira-ghcr.yaml         overrides：改用 GHCR 镜像（CI 构建产物）
  values-confluence-dc.yaml     Confluence DC chart values（官方镜像）
  values-confluence-ghcr.yaml   overrides：改用 GHCR 镜像
  argocd/                       ArgoCD Application（GitOps 方式部署）
```

GitOps 部署见 `k8s/argocd/README.md`。

## 部署顺序

```bash
# 1. 数据库
kubectl --context orbstack apply -f k8s/manifests/postgres.yaml
kubectl --context orbstack -n atlassian rollout status statefulset/postgres

# 2. 数据库账号 Secret（不入库）
PW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
for a in jira confluence; do
  kubectl --context orbstack -n atlassian create secret generic "${a}-db-credentials" \
    --from-literal=username="$a" --from-literal=password="$PW" \
    --dry-run=client -o yaml | kubectl --context orbstack apply -f -
done

# 3. Jira
helm --kube-context orbstack upgrade --install jira atlassian-data-center/jira \
  --namespace atlassian --version 2.0.15 -f k8s/values-jira-dc.yaml --wait --timeout 10m

# 4. Confluence
helm --kube-context orbstack upgrade --install confluence atlassian-data-center/confluence \
  --namespace atlassian --version 2.0.15 -f k8s/values-confluence-dc.yaml --wait --timeout 15m
```

## 许可证

```bash
# Confluence：放进 Secret，值文件里取消 license 段注释
kubectl --context orbstack -n atlassian create secret generic confluence-license \
  --from-literal=license-key="$(cat /path/to/confluence.license)"

# Jira chart 2.0.15 不支持 license Secret，首次启动在浏览器安装向导里粘贴 DC 许可证
```

## 访问（测试）

```bash
kubectl --context orbstack -n atlassian port-forward svc/jira 18080:80
kubectl --context orbstack -n atlassian port-forward svc/confluence 18090:80
```

## 已知注意点

- chart 的 JVM / 容器资源必须写在 `jira.resources` / `confluence.resources` 下，**顶层 `resources:` 会被静默忽略**（Pod 会用 chart 默认值 768m heap、2 CPU / 2G）。
- 单节点、单副本，Data Center chart 同样只跑 1 个 Pod；不要设置多副本，本地盘不支持跨节点共享。
- Jira 启动约 1–2 分钟；Confluence 首次启动 5–15 分钟，务必依赖 `startupProbe` 而不是 `livenessProbe`。
- 迁移真实数据前，需要把 PG 9.2 的 dump 恢复到 PG 14，并把 29 GiB / 32 GiB 的 Home 目录灌进 PVC。
- 用完清理：

```bash
helm --kube-context orbstack -n atlassian uninstall jira confluence
kubectl --context orbstack delete -f k8s/manifests/postgres.yaml
kubectl --context orbstack -n atlassian delete pvc --all   # 会删数据
```

## GitOps（ArgoCD）

`k8s/argocd/` 下有三个 Application，用 sync-wave 控制顺序，用法见 `k8s/argocd/README.md`。

## 踩坑记录

- **chart 的 `resources` 必须嵌套**：`jira.resources` / `confluence.resources`。写在顶层会被静默忽略，Pod 会用 chart 默认值（768m/1g heap、2 CPU / 2G）。
- **不要用 `additionalEnvironmentVariables` 覆盖 `JVM_SUPPORT_RECOMMENDED_ARGS`**：chart 自己占用该键，重复会直接 apply 失败（`duplicate entries for key`）。也正因为 chart 会覆盖镜像 ENV，用自带 `-javaagent` 的镜像时该参数不会进入 JVM 命令行。
- **PostgreSQL 的 Service 不要用 headless（`clusterIP: None`）**：Pod 重建后 IP 变化，应用的 JDBC 连接池仍指着旧 IP，Jira 会直接报 `failed to establish a connection to your database` 并锁定自己（Startup check failed. Jira will be locked.），表现为 readiness 一直 500、StatefulSet 滚动更新卡住（旧 Pod 不 Ready，新 Pod 不会被创建）。用带 ClusterIP 的普通 Service 由 kube-proxy 转发即可。
- **单副本 + 未就绪会卡住 helm/StatefulSet 更新**：Jira 先进入锁定状态时，`helm upgrade` 会等到 `context deadline exceeded`，需要先把旧 Pod 的 readiness 修好或直接删 Pod。
