# 平台入口网关（Envoy Gateway / Gateway API）

> **定位**：平台统一入口的架构说明与运维手册——控制面/数据面角色、Gateway API 资源模型与职责分工、双环境入口形态、资产边界、三仓路由清单、Policy 现状、部署顺序与验证。
> **权威指针**：证书/secret 契约 → [shared/CERTIFICATES.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CERTIFICATES.md)；后端 TLS 行为规格 → [shared/features/backend-tls.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/features/backend-tls.md)；认证子系统 → [shared/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md)；双环境保真度差异 → [plans/FIDELITY-KIND-VS-CLOUD-2026-10-09.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/FIDELITY-KIND-VS-CLOUD-2026-10-09.md)；活跃缺口跟踪（WS 长连超时 / ELB 探针）→ [plans/GAP-GATEWAY-POLICY-2026-10-26.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/GAP-GATEWAY-POLICY-2026-10-26.md)（STATUS O-42）。
> 网关级资源 manifest 真源：本地 = env 仓 `local-kind-dev/deploy/gateway-sdp.yaml`；云上 = CCE 官方 Envoy Gateway 插件（托管）。两者均**不随三仓 chart 分发**（§4）。

## 1. 角色：控制面 ≠ 数据面

| 组件 | 角色 | 职责 | 平台落点 |
| --- | --- | --- | --- |
| Envoy Gateway | 控制面 | 监听 Gateway API 资源（GatewayClass/Gateway/HTTPRoute/Policy），翻译为 Envoy 配置 | EG v1.6.1（本地 helm 自装；云上为 CCE 官方插件） |
| Envoy Proxy | 数据面 | 真正接收、匹配、转发请求；负载均衡、TLS 终止、指标与访问日志 | distroless-v1.36.x（与 EG v1.6 官方兼容矩阵，镜像经本地 registry 预推） |

控制链路：`Gateway API 资源 → Envoy Gateway Controller → Envoy 配置 → Envoy Proxy`。

## 2. Gateway API 资源模型与职责分工

| 资源 | 职责 | 平台维护方 |
| --- | --- | --- |
| GatewayClass | 声明由哪个 controller 管理（本地 `sdp-eg` / 云上 `envoy-gateway`） | env 仓脚手架 / CCE 插件 |
| EnvoyProxy | EG 行为配置（Envoy 部署形态、数据面 service 类型、镜像） | env 仓脚手架（仅本地使用） |
| Gateway | 监听端口、协议、TLS 证书、allowedRoutes | env 仓脚手架（本地）；云上由插件按 Gateway listener 自动建独享 ELB |
| HTTPRoute | 业务路由（域名 + 路径 → 后端 Service） | 三仓各自 chart |
| BackendTLSPolicy | 网关→后端 TLS 校验（CA + validation hostname） | 三仓各自 chart |

关键收益：入口基础设施（Gateway，运行方持有）与业务路由（HTTPRoute，组件 chart 自带）分离，三仓互不依赖对方的路由资源。

## 3. 双环境入口形态

| 维度 | 本地 kind | 云上 CCE |
| --- | --- | --- |
| EG 安装 | env 仓 helm chart（v1.6.1 自装） | CCE 官方 Envoy Gateway 插件 |
| GatewayClass | `sdp-eg` | `envoy-gateway` |
| 数据面 service | ClusterIP + `deploy-local.sh` port-forward（host 8082→http / 8443→https） | 按 Gateway listener 自动建独享 ELB，https=443 |
| https 端口 | 8443（刻意非 443：issuer/浏览器/hub 三方 URL 端口一致，listener 8443 ⇒ `X-Forwarded-Port=8443`） | 443（标准端口，issuer 推导不带端口） |
| 访问验证 | `curl --resolve www.sdpworkflow.com:8443:127.0.0.1 --noproxy '*'` | 内网 DNS 解析 `www.sdpworkflow.com` |
| 自建 EG 数据面 | 使用 | 禁用（ClusterIP 无 LB） |

本地 Gateway listener（`gateway-sdp.yaml`）：http 80 + https 8443（hostname `www.sdpworkflow.com`，TLS secret `console-ingress-tls`），两者 `allowedRoutes` 限同 namespace（sdp-workflow）。

## 4. 资产边界：Gateway 级资源不随三仓 chart 分发

- GatewayClass / EnvoyProxy / Gateway 属**集群级共享基础设施**，由运行方持有：本地在 env 仓脚手架 `local-kind-dev/deploy/gateway-sdp.yaml`，云上为 CCE 插件托管。三仓 chart 不打包、不重复定义。
- 三仓 chart 只携带**各自的** HTTPRoute（+ BackendTLSPolicy），按名字引用网关（hub `gatewayRoute.name` / console `gatewayRoute.gatewayName`，均可 `--set` 覆盖），保持三仓独立可装。
- 网关不存在时，HTTPRoute 处于 Pending（不 Accepted），组件自身运行不受影响。

## 5. 三仓路由清单

| 路由 | chart | 规则 | 后端 | 后端 TLS（BackendTLSPolicy） |
| --- | --- | --- | --- | --- |
| HTTPRoute `console` | console | `/`（前端 SPA） | console svc:externPort（TLS） | CA=`console-tls` 的 ca.crt；hostname=`console.<ns>.svc.cluster.local` |
| HTTPRoute `hub` | hub | `/api`（用户面 API）、`/gateway`（runner 回流 WS） | hub svc:externPort | CA=`hub-tls`；hostname=`hub.<ns>.svc.cluster.local` |
| HTTPRoute `keycloak` | hub | `/keycloak` | `hub-keycloak-http:8443`（keycloakx HTTPS） | CA=`hub-keycloak-tls`；hostname=keycloak svc FQDN |

共性约束：

- **每条 HTTPRoute 显式声明 `hostnames`**（取 `gatewayRoute.hostname`=`www.sdpworkflow.com`）。共享 Gateway 下无 hostname 的路由会匹配所有域名，与其他 Route 重叠——新增路由必须带 hostname。
- keycloakx 子 chart 自带 `httpRoute` 保持 `enabled: false`，keycloak 路由由 hub chart 自有模板渲染（hostnames 无条件生成，不依赖子 chart 默认值）。
- parentRefs 不指定 sectionName ⇒ 路由同时挂 http/https 两个 listener。

## 6. Gateway API Policy 映射与现状

| 流量策略 | Gateway API 载体 | 平台现状 |
| --- | --- | --- |
| 后端 TLS 校验 | BackendTLSPolicy | **已用**：console / hub / keycloak 三后端全量（见 backend-tls.md） |
| 超时 / 重试 | BackendTrafficPolicy | **已用（超时）**：hub chart 对 `/gateway` 规则（runner 回流 WS）挂 `timeout.http.streamIdleTimeout`（默认 `3600s`，`gatewayRoute.streamIdleTimeout` 可覆盖），sectionName 精确到 rule、`/api` 不受影响；重试未配置 |
| 认证 / CORS | SecurityPolicy | 未用：认证链由 hub + keycloak 承担（KC 只做身份、hub 唯一权限权威），网关层不做 JWT 校验 |
| Header / 客户端策略 | ClientTrafficPolicy | 未用：issuer 推导依赖 `X-Forwarded-*`，由 EG 按 listener 端口自动生成，无额外改写需求 |

Policy 体系是 Gateway API 对旧一代 Ingress annotations 的正解替代：策略与路由解耦、Controller 无关。

## 7. 部署顺序与运维

### 7.1 顺序（不可反）

1. EG controller 就绪（本地 helm / 云上 CCE 插件）。
2. Gateway 级资源 + listener 证书 secret（`console-ingress-tls`，本地由 cert-create.sh 先建；本地为 `gateway-sdp.yaml` 一并 apply）。
3. 组件 chart 部署（自带 HTTPRoute / BackendTLSPolicy；secret 契约见 CERTIFICATES.md §3）。
4. 验证后放流量：路由 `Accepted` + `Programmed`、网关→后端探活 200、全链 4xx/5xx 正常。

顺序颠倒不会使组件 Pod 挂死（路由按名引用、Pending 不影响运行），但流量验证会失败；本地 `deploy-local.sh` 已固化以上顺序。

### 7.2 健康检查

- LB / 探针**不得依赖业务 hostname 路由**探活：Envoy 对无匹配 HTTPRoute 的请求返回 404，会把健康后端误判为不健康。使用 Envoy 数据面专用就绪端点（EG 数据面 Pod 自带 readiness 探针；云上 ELB 探针参数以 CCE EG 插件默认为准）。
- 网关→后端链路健康判据：上游 `response_flags` 为 `-`、`upstream_transport_failure_reason` 为空（BackendTLSPolicy 校验通过的表现）。

### 7.3 观察项

- Gateway / HTTPRoute status：`Accepted`、`Programmed`。
- 上游 4xx/5xx 比例；WS 长连（`/gateway` 回流通道）存续时长。
- 证书轮换须同步 listener secret（`console-ingress-tls`）与后端 CA secret（`console-tls` / `hub-tls` / `hub-keycloak-tls`）。

### 7.4 回滚 / 重建

- 组件级：helm 重装 / 镜像回退（`kubectl set image`），路由与网关无需变动。
- 网关级（本地）：teardown 后重跑 `deploy-local.sh` 全链重建（改 kind 集群配置必须重建集群）。
- 网关级（云上）：CCE 插件卸装重装 + 重跑 `env/prod-deplyment/` 部署链（`hce-2.0-64bit-env.sh` → `run.sh` → `hce-2.0-64bit-deploy.sh`）。

## 8. 变更历史

| 日期 | 变更 |
| --- | --- |
| 2026-10-22 | 网关边界裁定：Gateway 级资源（GatewayClass/EnvoyProxy/Gateway）不搬进三仓 chart，留 env 仓脚手架；三仓只带各自 HTTPRoute + BackendTLSPolicy，按名引用 `sdp-gateway`（原记录见 env `gateway-sdp.yaml` 头注释与 GAP-BACKEND-TLS 跟踪文档）。 |
| 2026-10-26 | 首次成文（内容汇编自 env 脚手架注释、plans/GAP-BACKEND-TLS-2026-10-22、plans/FIDELITY-KIND-VS-CLOUD-2026-10-09 与三仓 chart 实现事实）。 |
