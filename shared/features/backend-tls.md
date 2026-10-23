> **来源**：[plans/GAP-BACKEND-TLS-2026-10-22.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/GAP-BACKEND-TLS-2026-10-22.md)（后端 TLS 化 Gap 跟踪：缺口清单 + 验证 gate + 业界方案对比）；权威证书/secret 契约为 [shared/CERTIFICATES.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CERTIFICATES.md) 与 [shared/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md)。
> **拆分说明**：GAP 文档是**跟踪记录**（哪些缺口、验证状态、置信度），本文件是**行为规格**（hub/runner 后端 TLS 如何工作、信任如何锚定）。A–F 全部闭环（A 代码 + B–E 真集群 2026-10-23 + F 仓 README 扫描），验收证据见 §6 与 `plans/GAP-BACKEND-TLS-2026-10-22.md`。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

hub 后端（WS 回流通道 + REST API）历史上以明文 `8080` 提供，runner 与目标机脚本（curl 上传/下载）不校验对端身份，存在 MITM / 凭据泄露面。目标：hub 后端以 TLS 提供（wss/https 同端口 `8080`），runner 与目标机凭 CA 信任 hub 后端，用户脚本零改动。

**约束（bootstrap 悖论）**：自签 CA 无第三方背书，任何经 TLS 的带内通道都无法分发它自己的信任根。因此 CA 的信任锚必须是**带外通道**：集群内 = secret 挂载（k8s 内信任）；集群外 = 装机物料（IaC 通道，见 `runner/features/target-bootstrap.md` §5）。

## 2. 范围

### 2.1 In-scope
- runner→hub 连接改为 `wss://` + `https://`，CA 由 secret 挂载注入。
- job Pod（任务容器）挂载 hub CA ConfigMap，使任务内 curl 原生信任 hub 后端。
- hub HTTPRoute 增加 `/gateway` 规则（runner 回流通道），与 `/api` 共用 `BackendTLSPolicy` 后端 TLS 校验。

### 2.2 Out-of-scope
- keycloak 双端口 HTTPS（8443）：GAP-BACKEND-TLS B/E 项，**已真集群验证（2026-10-23 闭环）**。
- 云上公网证书（Web PKI）：见 `runner/features/target-bootstrap.md` §5 与 STEELMAN-ADR2 #2，触发条件未到。
- 网关级资源（GatewayClass/EnvoyProxy/Gateway）：运行方/本地脚手架持有（`env/local-kind-dev/deploy/gateway-sdp.yaml`），不随三仓 chart 分发。

## 3. 信任模型

- **CA 是公开物**（含公钥不含私钥）：保护的是**完整性**（防 MITM 整体替换信任根），非保密。
- **集群内**：runner Pod 挂 `hub.caSecretName` 所指 secret（默认 `hub-tls`）的 `ca.crt` → 经 `SSL_CERT_FILE` 注入 gorilla 默认 dialer 系统池 → 信任 hub 后端。
- **job Pod**：runner 持有的 CA 同步为 job 所在 ns 的 `sdp-hub-ca` ConfigMap → job Pod 挂载 + `SSL_CERT_FILE` → 任务内 curl 信任 hub 后端。真实 PKI 部署（CA 为空）时整条链路 no-op，走系统信任池。

## 4. 实现机制（A 项，已落地）

### 4.1 runner chart `hub:` 合并段（`build/runner/charts/.../values.yaml:30-34`）
原 `gateway:`+`hubApi:` 合并为 `hub:`：`gatewayUrl`（`wss://hub.sdp-workflow.svc:8080/gateway/ws`）、`apiBaseUrl`（`https://hub.sdp-workflow.svc:8080`）、`apiToken`、`caSecretName`（默认 `hub-tls`）。集群外 runner 把两个 URL 覆盖为网关对外地址。

### 4.2 runner Pod CA 挂载（`deployment-runner.yaml:37-40,64-67,93-98,106-116`）
`hub.caSecretName` 非空时：挂 `hub-certs` 卷（secret `{{ .Values.hub.caSecretName }}`，item `ca.crt` → `/etc/hub-certs/ca.crt`）；注入 `SSL_CERT_FILE=/etc/hub-certs/ca.crt` 与 `SDP_HUB_CA_FILE=/etc/hub-certs/ca.crt`。空则跳过挂载与注入（真实 PKI 路径）。

### 4.3 job Pod CA 同步（`internal/controller/hub_ca.go` + `pkg/executor/job_builder.go:102-148`）
`TaskRunReconciler.ensureHubCAMap` 在 Job 创建前把 runner 持有的 CA bundle upsert 为 job ns 的 ConfigMap `sdp-hub-ca`（`executor.HubCAConfigMapName`，key `ca.crt`）。`job_builder.go` 在 `HubCABundle != ""` 时挂该 CM + 设 env `SSL_CERT_FILE=hubCAMountPath/ca.crt`。空 bundle 整条 no-op。

### 4.4 hub 后端 TLS + 路由（`build/hub/charts/.../templates/httproute.yaml`）
`HTTPRoute hub` 两条规则：`/api`（console/用户面）、`/gateway`（runner 回流通道，WS 长连 idle timeout 由 EnvoyProxy 侧调优）。`BackendTLSPolicy hub` 引用 `gatewayRoute.caSecretName` 校验 hub 后端证书（SAN 覆盖 `hub.<ns>.svc.cluster.local`，见 `cert-create.sh`）。hub 后端 TLS 由 deployment 挂 `hub-tls` + `HUB_TLS_*` 环境变量开启。

## 5. 代码证据（实测 file:line）

| 行为 | 位置 |
|------|------|
| runner `hub:` 合并段 | `build/runner/charts/software-distribution-platform-runner/values.yaml:30-34` |
| runner Pod CA 挂载 + `SSL_CERT_FILE`/`SDP_HUB_CA_FILE` | `build/runner/charts/software-distribution-platform-runner/templates/deployment-runner.yaml:37-40,64-67,93-98,106-116` |
| job CA ConfigMap 同步 | `internal/controller/hub_ca.go:21-43`（`ensureHubCAMap`） |
| job Pod 挂 CM + `SSL_CERT_FILE` | `pkg/executor/job_builder.go:102-106`（`HubCAConfigMapName`/`HubCAKey`）、`:137-148`（挂载 + env） |
| hub HTTPRoute `/api`+`/gateway` | `build/hub/charts/software-distribution-platform-hub/templates/httproute.yaml`（`HTTPRoute hub`） |
| hub `BackendTLSPolicy` | 同上文件（`BackendTLSPolicy hub`，引用 `gatewayRoute.caSecretName`） |

## 6. 测试与验收

- **静态 gate（已满足）**：三仓 `helm template` 全绿；runner `go build/vet/test` 全绿。
- **真集群 gate（全部闭环，2026-10-23 云上重建后回归，见 GAP 文档 §3）**：
  - **B（已闭环）**：keycloakx `statefulset` env→args 自动追加 `--https-*` 真生效——keycloak 日志 `Listening on: https://0.0.0.0:8443`；网关 `httproute/keycloak` 上游 `keycloak:8443` 返回 200。
  - **C（已闭环）**：重建部署链（`hce-2.0-64bit-deploy.sh`→`run.sh`）已生成 `hub-tls`/`hub-keycloak-tls` 四 secret，hub/keycloak 后端均以 TLS 起。
  - **D（已闭环）**：envoy 用 `hub-tls`/`hub-keycloak-tls` 的 `ca.crt` 校验后端——网关上游 `hub:8080`(TLS)/`keycloak:8443` 均 `response_flags:"-"`、`upstream_transport_failure_reason:null`、SNI `www.sdpworkflow.com` 命中，`BackendTLSPolicy` CA 校验通过（运行时证伪）。
  - **E（已闭环）**：`proxy.mode=xforwarded` 下 issuer 推导 + `KEYCLOAK_ISSUER`（钉死 `https://www.sdpworkflow.com:8443/keycloak/realms/sdp`）+ `auth.resolveHostIp` hostAlias 回归；`/keycloak/.../token` 经网关 200。
  - **F（已闭环）**：三仓 README 扫描 `ws://hub`/`8080 明文`同型描述并同步（docs 两份权威文档已修；仓内 README 已于 2026-10-23 全量扫描：仅 `hub/README.md` 的 `HUB_ADDR` 描述更正，其余无遗留）。
- **状态**：**A–F 全部闭环**——A 代码落盘（§5 证据）+ B–E 真集群验证（2026-10-23 云上重建后 E2E，网关 TLS 全链 200、无传输失败）+ F 仓 README 扫描同步。

## 7. 决策记录（指针）

后端 TLS 化方案权衡、业界成熟方案对比（指纹 Pinning / 短时效凭证 / 公网 PKI 三派）、bootstrap 悖论论证见 [GAP-BACKEND-TLS-2026-10-22.md §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/GAP-BACKEND-TLS-2026-10-22.md)。

## 8. 实现记录

- **runner chart**：`build/runner/charts/software-distribution-platform-runner/{values.yaml,templates/deployment-runner.yaml}`
- **runner Go**：`internal/controller/hub_ca.go`、`pkg/executor/job_builder.go`、`cmd/runner/main.go:273`
- **hub chart**：`build/hub/charts/software-distribution-platform-hub/templates/httproute.yaml`
- **权威证书契约**：docs `shared/CERTIFICATES.md` §3（`hub-tls`/`hub-keycloak-tls`）
- **关联特性**：`runner/features/target-bootstrap.md`（集群外 CA 信任锚两态）
