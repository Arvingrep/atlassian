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

## OrbStack VM 内存（关键前置）

k8s 的 pod 和 compose 的容器跑在**同一个** OrbStack Linux VM 里，VM 内存默认 `memory_mib: 16384`（16 GiB）。
两个 Data Center 应用 + PostgreSQL 一起跑会打满这个上限，症状很有迷惑性：

```text
postgres-0 lastTerminated = OOMKilled (exit 137)，占用只有 24 MiB / 限额 2 GiB
jira-0     Startup check failed. Jira will be locked.（启动时连不上库，只检查一次）
/status    500 → readiness 失败 → 单副本 StatefulSet 滚动更新卡住 → helm upgrade 超时
VM 内 /proc/meminfo: MemFree 125 MB, MemAvailable 682 MB
```

macOS 侧可能完全正常（48 GB、内存压力绿色），瓶颈只在 VM 上限。调到 32 GiB 后：

```bash
orb config set memory_mib 32768
orb stop && orb start      # 重启 OrbStack，compose 容器与 k8s pod 一并重启（数据卷不受影响）
# 重启后 VM 内 MemAvailable 从 682 MB 变为 ~20 GiB
```

复验结果（调内存后）：`jira-0 1/1 Running /status=FIRST_RUN`、`confluence-0 1/1 Running`、
两个 pod 的 `-javaagent` 计数均为 0。

## 内网入口（Gateway API + 通配 TLS）

集群装的是 **Envoy Gateway v1.5.8**（提供 Gateway API 实现 + CRD）。GitOps 由 ArgoCD `atlassian-gateway` 管。

```text
GatewayClass  eg                 controller = gateway.envoyproxy.io/gatewayclass-controller
Gateway       atlassian          listener http  :80  -> 只做 301 跳 HTTPS
                                 listener https :443 -> TLS Terminate，通配证书 *.sl-devops.com
HTTPRoute     https-redirect     两个域名的 HTTP 请求 301 到 https（k8s/manifests/gateway.yaml）
HTTPRoute     jira               由 jira chart 创建（values 里的 gateway 段）
HTTPRoute     confluence         由 confluence chart 创建
```

Gateway 与跳转路由在 `k8s/manifests-gateway/gateway.yaml`（独立目录，由独立的 ArgoCD Application 管）；**应用的 HTTPRoute 交给 chart 自己创建**，
因为设置 `gateway.hostnames` 会同时激活 chart 的 gateway 模式，给容器注入
`ATL_TOMCAT_SCHEME=https` / `ATL_TOMCAT_SECURE=true` / `ATL_PROXY_NAME` / `ATL_PROXY_PORT=443`。
不注入这些，Jira/Confluence 在 TLS 终止的反代后面会生成 `http://` 链接并报 base URL 不匹配。

### 1. 装 Gateway API 实现

```bash
helm --kube-context orbstack upgrade --install envoy-gateway \
  oci://docker.io/envoyproxy/gateway-helm --version v1.5.8 \
  -n envoy-gateway-system --create-namespace --wait --timeout 8m
```

chart 自带 Gateway API CRD 与 certgen Job，不需要单独 apply upstream CRD。

### 2. TLS Secret（复用 compose 的 Certum 通配证书，不入 Git）

```bash
kubectl --context orbstack -n atlassian create secret tls sl-devops-wildcard-tls \
  --cert=nginx/ssl/sl-devops.com.crt \
  --key=nginx/ssl/sl-devops.com.key \
  --dry-run=client -o yaml | kubectl --context orbstack apply -f -
```

证书事实：`CN=*.sl-devops.com`，SAN `*.sl-devops.com, sl-devops.com`，
签发 `Certum DV TLS G2 R39 CA`，有效期至 **2026-12-11**，文件里含 4 段证书（叶子 + 中间链，
Gateway 需要完整链才能让浏览器校验通过）。已核对 crt 与 key 的公钥 md5 一致。

### 3. Gateway 与路由

```bash
kubectl --context orbstack apply -f k8s/manifests-gateway/gateway.yaml
kubectl --context orbstack -n atlassian get gateway atlassian \
  -o jsonpath='{range .status.listeners[*]}{.name}={.conditions[?(@.type=="Programmed")].status} attached={.attachedRoutes}{"\n"}{end}'
```

Gateway 会创建 LoadBalancer Service，OrbStack 直接分配一个 macOS 可直连的 IP：

```bash
kubectl --context orbstack -n envoy-gateway-system \
  get svc -l gateway.envoyproxy.io/owning-gateway-name=atlassian \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

### 4. 内网解析（手动，需要 sudo；IP 换成上面查到的值）

```bash
sudo sh -c 'printf "192.168.139.2 jira-k8s.sl-devops.com\n192.168.139.2 conf-k8s.sl-devops.com\n" >> /etc/hosts'
```

### 5. 实测（绕过 hosts，用 --resolve 直连）

```bash
IP=192.168.139.2
for h in jira-k8s.sl-devops.com conf-k8s.sl-devops.com; do
  curl -s -o /dev/null -w "$h http  %{http_code} -> %{redirect_url}\n" -H "Host: $h" http://$IP/
  curl -s -o /dev/null -w "$h https %{http_code} ssl_verify=%{ssl_verify_result}\n" --resolve "$h:443:$IP" "https://$h/"
done
echo | openssl s_client -connect $IP:443 -servername jira-k8s.sl-devops.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

结果：

```text
jira-k8s  http  301 -> https://jira-k8s.sl-devops.com/
jira-k8s  https 302 -> /secure/SetupMode!default.jspa       ssl_verify=0（公网 CA 直接校验通过）
conf-k8s  http  301 -> https://conf-k8s.sl-devops.com/
conf-k8s  https 302 -> /bootstrap/selectsetupstep.action    ssl_verify=0
served cert: CN=*.sl-devops.com / Certum DV TLS G2 R39 CA / notAfter=Dec 11 2026
```

### 注意

- Gateway 的 LoadBalancer IP 由 OrbStack 分配，集群重建后会变，hosts 要同步更新。
- **TLS Secret 不入 Git**，ArgoCD 只管 Gateway/HTTPRoute；集群重建后要先手动建 Secret，
  否则 https listener 会 `Programmed=False`（`InvalidCertificateRef`）。
- 证书 2026-12-11 到期，续期时同一份文件既要更新 compose 的 `nginx/ssl/`，也要重建这个 Secret。
- compose 环境的 `alpha-jira` / `confsys` 域名保持不变，与 `*-k8s` 域名互不冲突。
- Jira/Confluence 现在是 `FIRST_RUN`：安装向导会把**当时访问用的域名**写成 base URL，
  必须用 `https://jira-k8s.sl-devops.com` 打开向导，不要用 port-forward 的 localhost。

### 6. 应用侧代理变量已生效（实测）

```bash
kubectl --context orbstack -n atlassian get pod jira-0 \
  -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep ATL_
# ATL_TOMCAT_SCHEME=https / ATL_TOMCAT_SECURE=true
# ATL_PROXY_NAME=jira-k8s.sl-devops.com / ATL_PROXY_PORT=443
```

重定向的 `Location` 是 `https://jira-k8s.sl-devops.com/...` 绝对 URL（不是 IP、不是 http），
证明 chart 的 gateway 模式把代理信息正确传给了 Tomcat。

### ArgoCD 的两个 drift 坑（都已修，别回退）

1. **同一对象不能被两个 Application 同时声明**。`gateway.yaml` 里一度也写了 jira/confluence
   的 HTTPRoute，与 chart 生成的同名，结果两边永久 `OutOfSync` 且带 `SharedResourceWarning`。
   产品路由归 chart，Gateway/GatewayClass/跳转路由归 `atlassian-gateway`。
2. **Gateway API 的 `group` / `kind` 必须在 Git 里写全**。省略时 API server 会补默认值
   （`certificateRefs` 补 `group: ""` + `kind: Secret`，`parentRefs` 补
   `gateway.networking.k8s.io/Gateway`，HTTPRoute 的 `matches` 补 `PathPrefix /`），
   ArgoCD 会当成 drift。chart 渲染的 `backendRefs` 我们改不了，只能在 Application 里
   `ignoreDifferences` 掉 `/spec/rules/0/backendRefs/0/{group,kind}`。

最终状态：`atlassian-postgres` / `atlassian-gateway` / `atlassian-jira` / `atlassian-confluence`
四个 Application 全部 `Synced/Healthy`，无残余 drift。
