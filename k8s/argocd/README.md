# ArgoCD 部署（GitOps）

三个 Application，用 sync-wave 控制顺序：

| Application | 来源 | wave |
|---|---|---|
| `atlassian-postgres` | 本仓库 `k8s/manifests`（PostgreSQL 14 + 库表） | 0 |
| `atlassian-jira` | upstream chart `jira` 2.0.15 + 本仓库 values | 1 |
| `atlassian-confluence` | upstream chart `confluence` 2.0.15 + 本仓库 values | 1 |

Jira / Confluence 用 ArgoCD 的 **multi-source**：chart 来自 `https://atlassian.github.io/data-center-helm-charts`，values 来自本仓库（`ref: values`），因此 values 改动只需 push 到 Git。

## 前置

```bash
# 1) 集群里装 ArgoCD（测试集群尚未安装）
kubectl --context orbstack create namespace argocd
kubectl --context orbstack -n argocd apply -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2) 数据库账号 Secret（不入 Git）
PW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
for a in jira confluence; do
  kubectl --context orbstack -n atlassian create secret generic "${a}-db-credentials" \
    --from-literal=username="$a" --from-literal=password="$PW"
done

# 3) Confluence 许可证（可选，向导粘贴也可以）
kubectl --context orbstack -n atlassian create secret generic confluence-license \
  --from-literal=license-key="$(cat /path/to/confluence.license)"
```

ArgoCD 不会管理任何 Secret：数据库凭据和许可证都靠上面的命令或 SealedSecrets 提供。

## 提交 Application

```bash
kubectl --context orbstack apply -f k8s/argocd/application-postgres.yaml
kubectl --context orbstack apply -f k8s/argocd/application-jira.yaml
kubectl --context orbstack apply -f k8s/argocd/application-confluence.yaml
```

`atlassian-postgres` 先进入 Synced/Healthy，然后两个应用同步。

## 注意

- `destination.namespace: atlassian` 由 `k8s/manifests/postgres.yaml` 里的 Namespace 资源创建，所以 `CreateNamespace=false`。
- 用 `ServerSideApply=true`：StatefulSet 的探针、env 等字段较多，客户端 apply 容易因 `last-applied-configuration` 过大出问题。
- Jira / Confluence 的 `additionalEnvironmentVariables` **不能**重复定义 `JVM_SUPPORT_RECOMMENDED_ARGS`（chart 已占用该键，重复会直接报 duplicate env key）。
- 装完 ArgoCD 后如果想要「App of Apps」，再加一个 root Application 引用 `k8s/argocd/` 目录即可。
