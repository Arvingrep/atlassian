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

## 接到 mac-mini 的 ArgoCD

MacBook 的 k8s（context `orbstack`）由 **mac-mini 上跑的 ArgoCD** 管理。因为 OrbStack 的 API server 只监听 `127.0.0.1:26443`，mini 侧无法直连，需要两步：

### 1. Tailscale 转发 API 端口（MacBook 上执行）

```bash
tailscale serve --bg --tcp 26443 tcp://127.0.0.1:26443
tailscale serve status          # 确认 100.x.y.z:26443 -> 127.0.0.1:26443
```

mini 的 pod/host 都能访问 `https://<macbook-tailnet-ip>:26443`（实测返回 401 = 可达）。

### 2. 在 mini 的 ArgoCD 注册集群

```bash
kubectl --context mac-mini-orbstack -n argocd apply -f cluster-macbook-orbstack.yaml   # 本地生成，不入 Git
```

集群 Secret 的要点（`argocd.argoproj.io/secret-type: cluster`）：

```yaml
stringData:
  name: macbook-orbstack
  server: https://<macbook-tailnet-ip>:26443
  config: |
    {"tlsClientConfig":{"insecure":true,"certData":"<kubeconfig client-cert>","keyData":"<kubeconfig client-key>"}}
```

- **坑**：`caData` 与 `insecure: true` 不能同时给，否则 ArgoCD 报
  `specifying a root certificates file with the insecure flag is not allowed`，应用一直是 `Unknown/Healthy`。
- 更"干净"的做法是把 tailnet IP 加进 API 证书 SAN（`orb config set k8s.tls_san <ip>` 后重启 OrbStack），
  然后去掉 `insecure`，但这会再重启一次全部容器，所以本测试用 insecure。
- 客户端证书/私钥来自 MacBook 的 kubeconfig，属于敏感信息：**只 kubectl apply，不入 Git**（已加 `.gitignore`）。

### 3. Applications

三个 Application 的 `destination` 用集群名：

```yaml
destination:
  name: macbook-orbstack
  namespace: atlassian
```

```bash
kubectl --context mac-mini-orbstack apply -f k8s/argocd/application-postgres.yaml \
  -f k8s/argocd/application-jira.yaml -f k8s/argocd/application-confluence.yaml
```

### 4. 另一个坑：StatefulSet 永远 OutOfSync

API server 会给 `volumeClaimTemplates[].spec` 补上 `volumeMode: Filesystem`，清单里不写就会一直被判定 OutOfSync。
在清单里显式写上 `volumeMode: Filesystem` 即可（已修）。

### 5. 还有坑：StatefulSet 的 API 默认字段

除了 `volumeClaimTemplates[].spec.volumeMode`，API server 还会给 StatefulSet 补上

```yaml
spec:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Retain
```

清单里不写，ArgoCD 就永远判 OutOfSync（`argocd app diff` 会显示这两个字段）。处理方式二选一：

- 清单里显式写出（本仓库采用）
- 或在 Application 上加 `ignoreDifferences` 针对 `apps/StatefulSet` 的 `/spec/persistentVolumeClaimRetentionPolicy`

需要看具体差异时：`argocd app diff atlassian-postgres`（先 port-forward mini 的 argocd-server）。
