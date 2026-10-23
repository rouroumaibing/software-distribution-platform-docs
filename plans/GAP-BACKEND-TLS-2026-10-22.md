# 网关后端 TLS 化 — Gap 跟踪

> 关联文档：[CERTIFICATES.md](../shared/CERTIFICATES.md)（证书 / secret 契约权威，§3 已含 `hub-tls` / `hub-keycloak-tls`）、[KEYCLOAK.md](../shared/KEYCLOAK.md)（keycloak HTTPS 部署权威）、`env/local-kind-dev/deploy/gateway-sdp.yaml`（网关级资源，留在 env 不进三仓 chart）；**行为规格（已实现部分）见 [shared/features/backend-tls.md](../shared/features/backend-tls.md)**。
> 适用范围：hub / runner / env 三仓 + docs。
>
> **状态**：代码与 chart 侧已落地（hub Go TLS listener、hub/keycloak BackendTLSPolicy、cert-create.sh 四组件、deploy-local.sh 四 secret），`helm template` 渲染全绿 + `go build`/`go vet` 全绿（2026-10-22）。**A 已代码闭环；B/C/D/E 已于 2026-10-23 云上 CCE 重建部署后真集群验证闭环**（网关→hub:8080 TLS / keycloak:8443 全链 200、无传输失败、SNI `www.sdpworkflow.com` 命中）；仅 F（仓 README 同型扫描）遗留（非集群依赖）。本文按 A–F 跟踪，闭环一项勾一项。

## 1. Gap 定义

设计裁定：网关后端全面 TLS 化——hub Go 后端与 keycloak 后端改真 TLS，各配 `BackendTLSPolicy`（envoy 用 CA 校验后端证书）；网关级资源维持留在 env。落地时有三类缺口：

1. **直连方未同步**：hub `:8080` 从明文变 TLS 后，所有**绕过网关直连 hub svc** 的客户端（runner WebSocket、手工 curl/port-forward、脚本）都会握手失败——这是唯一会造成运行时故障的缺口。
2. **真集群未回归**：keycloakx 经 `KEYCLOAK_HTTPS_*` env 自动追加 `--https-*` 启动参数的行为、envoy BackendTLSPolicy 校验、issuer 推导链，均只在渲染层验证过，未在 kind 真集群跑过。
3. **存量环境迁移**：已部署的 kind 集群缺新证书与新 secret，须重跑 cert-create.sh / deploy-local.sh。

## 2. 结论（一句话）

**渲染层全绿，运行层未验证**；其中 A（runner `ws://` 直连）是 P0 运行时故障项，必须在下次真集群部署前修掉，否则 runner 连不上 hub。

## 3. 缺口清单（带落点 + 置信度）

| 编号 | 优先级 | 位置 | 缺口 | 置信度 |
|---|---|---|---|---|
| A | **P0·已闭环（2026-10-22）** | runner 仓 chart + Go | **已落地**：① runner chart values `gateway:`+`hubApi:` 合并为 `hub:` 段（`gatewayUrl`/`apiBaseUrl`/`apiToken`/`caSecretName`），`wss://hub.sdp-workflow.svc:8080/gateway/ws` + `https://hub.sdp-workflow.svc:8080`（SAN DNS.2 覆盖，host 不变只切 scheme）；死配置 `gateway.token` 删除（WS 认证实际取 `TARGET_AUTH_TOKEN`，与 hub `GATEWAY_TOKEN` 成对）。② runner Pod 挂 `hub.caSecretName`（默认 `hub-tls`）+ `SSL_CERT_FILE`（gorilla 默认 dialer 走系统池，零 Go 改码）。③ job Pod CA：TaskRun 控制器把 runner 持有的 CA 同步为 job ns 的 `sdp-hub-ca` ConfigMap（`internal/controller/hub_ca.go`），job Pod 挂载 + `SSL_CERT_FILE`——curl 原生识别，用户上传/下载脚本零改动。④ hub HTTPRoute 补 `/gateway` 规则（集群外 runner 回流硬需求，与 /api 共用 BackendTLSPolicy）。gate：go build/vet/test 全绿 + 双仓 helm template 全绿 | 确认（已落码） |
| B | **已闭环（2026-10-23 真集群验证）** | keycloakx 7.3.2（vendored 子 chart）`statefulset.yaml` 的 env→args 转换 | keycloak 日志 `Listening on: ... https://0.0.0.0:8443`；网关 `httproute/sdp-workflow/keycloak` 上游 `keycloak:8443` 返回 200（`upstream_transport_failure_reason:null`）；`KEYCLOAK_HTTPS_*` 自动 `--https-*` 行为确认有效，无需 fallback | 确认（真集群运行时） |
| C | **已闭环（2026-10-23 真集群部署）** | 存量 kind 集群 | 云上 CCE 重建部署链（`hce-2.0-64bit-deploy.sh`→`run.sh`）已生成 `hub-tls`/`hub-keycloak-tls` secret 与新证书，hub/keycloak 后端真 TLS 起服 | 确认 |
| D | **已闭环（2026-10-23 真集群验证）** | envoy + BackendTLSPolicy | envoy 经 `hub-tls`/`hub-keycloak-tls` 的 `ca.crt` 校验后端通过：网关上游 `hub:8080`(TLS) 与 `keycloak:8443` 均 200、`response_flags:"-"`、`upstream_transport_failure_reason:null`、SNI `www.sdpworkflow.com` 命中；`/api/v1/*` 与 `/keycloak/.../token` 全链路通（BackendTLSPolicy 条件对象未直接读，但无传输失败即 CA 校验通过） | 确认（运行时证伪） |
| E | **已闭环（2026-10-23 真集群验证）** | issuer 推导链 | `/keycloak/realms/sdp/protocol/openid-connect/token` 经网关 200；hub `KEYCLOAK_ISSUER` 钉死 `https://www.sdpworkflow.com:8443/keycloak/realms/sdp`，OIDC 登录全链（console→keycloak→hub token）随今日 canary/taskrun E2E 跑通 | 确认（运行时证伪） |
| F | **已闭环（2026-10-23 扫描同步）** | 三仓 README / env README | 全量递归扫描：仅 `hub/README.md` 的 `HUB_ADDR` 说明由「HTTP 监听地址」更正为「TLS 监听地址（wss/https 同端口 8080）」；`runner`/`console`/`env` README 无 `ws://hub`/`http://hub:8080` 同型明文描述，无需改动。属文档卫生，不阻塞运行 | 确认 |

## 4. 修复顺序建议

1. **A**（runner wss + CA 信任）—— 不修则真集群 runner 起不来，阻塞一切 E2E。
2. **C**（存量环境重跑证书/secret）→ **B/D/E** 在同一次真集群部署中一并回归：hub/keycloak 起来后先看 keycloak 日志 `Listening on`（应含 `https://0.0.0.0:8443`），再 `kubectl get backendtlspolicy` 看条件，最后 curl 走网关全链路 + runner 握手成功。
3. **F** 顺手清（A 修 runner chart 时同步扫 README）。

## 5. 验收 gate（全部闭环的定义）

- `helm template` 三仓全绿（hub 已验，runner 改后须重验）。
- kind 真集群：keycloak 8443 起 HTTPS；`kubectl get backendtlspolicy hub keycloak` 条件 True；`curl --resolve www.sdpworkflow.com:8443:127.0.0.1 https://www.sdpworkflow.com:8443/api/v1/...` 与 `/keycloak/realms/sdp/.well-known/openid-configuration` 通。
- runner Pod 与 hub WebSocket 握手成功（`wss://`）。
- OIDC 登录全链路（console → keycloak → hub token 校验）不回归。

## 6. 外部 runner 信任引导：业界成熟方案对比与选型

> 前提澄清：CA 证书是**公开物**（含公钥不含私钥），业界从不"保密"它——要保护的是**完整性**（防 MITM 整体替换信任根）。自签 CA 无第三方背书，任何经 TLS 的带内通道都无法分发它自己的信任根（bootstrap 悖论），因此成熟方案全部围绕"完整性如何锚定"设计，分三派：

**派别 A：指纹 Pinning（带内取证书、带外验短指纹）**

- kubeadm（默认模式）：节点从 kube-public 的 cluster-info ConfigMap **经不安全连接**取 CA → 用 `--discovery-token-ca-cert-hash`（RFC7469 SPKI SHA256）校验公钥 → 再经安全连接二次比对；hash 可重复多次传入以支持 CA 轮换（kubernetes.io「Implementation details / kubeadm join」）。
- smallstep step-ca：`step ca bootstrap --ca-url --fingerprint`，下载 root CA 后比对 SHA256 指纹（CA 初始化时打印，生产文档 "Production considerations → Root distribution" 同款）。
- 形态：安装物料收敛为**一条 join-command 式命令**（URL + token + 一行指纹）。

**派别 B：约定路径 + 配置管理放文件（带外分发证书文件）**

- GitLab Runner（官方 tls-self-signed 文档）：`/etc/gitlab-runner/certs/<host>.crt` 约定路径，由 CM（Ansible 等）放置；官方另给 `openssl s_client` 一键拉取命令（弱形态：拉取不校验，靠人工核验）。同款范式：containerd 自签 registry CA、etcd `--trusted-ca-file`、kubelet bootstrap.kubeconfig 内嵌 `certificate-authority-data`。

**派别 C：公网端点走 Web PKI，私有 CA 不出集群边界**

- smallstep 生产文档明确列出：部署环境若信任 Web PKI，可把 CA 挂在（本身为公网证书的）HTTPS 静态端点上引导。更广义：SaaS 化平台（GitLab.com 等）根本不面对此问题——公网端点用公网证书，私有 CA 只做内部 mTLS。

**SDP 三阶段选型**

| 阶段 | 派别 | 做法 |
|---|---|---|
| 短期（dev / 内网自签） | B | env 仓安装物料脚本：`kubectl get secret hub-tls` 导出 CA → 放置宿主机 → 渲染 runner env（`SDP_HUB_CA_FILE` / 网关 URL）；CA 不出运维边界 |
| 中期（云上公网域名） | C | 网关入口 listener 换公网证书（ELB 挂证书 / cert-manager HTTP-01），集群外 runner **零 CA 分发**（OS 信任根）；私有 CA 只留在 envoy→hub 后端链路 |
| 演进（配 ADR-0001 per-target token） | A | runner Go 增加 pin 校验（取 CA → 验指纹 → 信任），安装收敛为一条 join-command（URL + enroll token + CA 指纹） |

设计裁定：分发终态以 **join-command 式一条命令**为方向（GitLab `register` / kubeadm `join` / step `bootstrap` 同款范式）；URL 注入与轮换（信任 bundle 多 CA）随安装物料一并落地。

## 7. 变更历史

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-10-22 | 初稿：hub/keycloak 后端 TLS 化落地后的缺口盘点（A runner 直连 P0、B keycloakx https 参数待验证、C 存量环境迁移、D BackendTLSPolicy 真集群验证、E issuer 回归、F 文档同型扫描） | 用户裁定 hub 与 keycloak 后端一并改真 TLS 并各配 BackendTLSPolicy 后，收敛"渲染层绿 / 运行层未验证"的缺口清单 |
| 2026-10-22 | A 闭环：runner 切 wss/https + CA 信任（values `hub.*` 段合并改名、删死配置 `gateway.token`、runner Pod 挂 CA + `SSL_CERT_FILE`、job Pod 经 `sdp-hub-ca` ConfigMap 挂载）、hub HTTPRoute 补 `/gateway` 回流规则。设计裁定：runner 大部分部署在集群外 ⇒ svc 直连非终态，网关路由是硬需求；集群内直连保留为优化路径（URL 契约两态：网关对外地址 / 集群内 svc 地址，同一 CA 信任） | 用户确认拓扑（集群外 runner 为主）+ 裁定 `gateway` 字段命名歧义需改名（`gateway` 实指 hub 进程内 runner 网关模块 internal/gateway，与 Envoy Gateway 撞名） |
| 2026-10-22 | 新增 §6：外部 runner 信任引导业界方案对比（kubeadm SPKI pinning / smallstep fingerprint / GitLab Runner 约定路径 / Web PKI 三派）与三阶段选型（短期 B 物料脚本 → 中期 C 云上公网证书 → 演进 A join-command）；推翻"CA 分发捆进 enroll"的早期设想（bootstrap 悖论：带内通道发不了自己的信任根） | 用户纠偏"CA 证书不会乱发"，要求以成熟案例为依据重新论证分发形态 |
| 2026-10-22 | **设计裁定（钢人论证后）**：runner 安装引导收编为 hub API 能力（join-bundle：gatewayUrl / apiBaseUrl / caPem / caFingerprint / per-target enrollToken），复用 §9.9 enroll-token 铸发端 + OIDC/RBAC。**API 消费方 = 装机管线/操作者会话**（已信任通道），目标机消费的是内嵌进 cloud-init userdata 的 join 数据，不裸连 hub API。无人值守信任锚：云上网关公网证书（Web PKI，首选）或 CA+token 内嵌 userdata（IaC 为带外通道，fallback）。runner 更新走 WS 下发（已有 agent_version 回流通道），不进安装 API。下一步：起草 ADR（join-bundle API + 无人值守引导设计），评审后落码 | 用户裁定存在无人值守安装诉求，人工 join-command 不够；install-as-API 经 kubeadm/smallstep 范式验证 |
| 2026-10-22 | **ADR-0002 落码**：hub `POST /targets/:id/join-bundle`（`internal/target/service/joinbundle.go` + handler，RBAC 同 target 层；`publicUrl`/TLS CA 缺失显式 501；chart 增 `HUB_PUBLIC_URL`/`HUB_TLS_CA_FILE`/values `publicUrl`）；**前端对接信息获取点 = console 目标页「安装命令」弹窗**（`src/utils/runnerInstall.ts` 渲染自举脚本 + `src/api/target.ts` `joinBundle()` + 复制，smoke `scripts/target-smoke.mjs` 6/6 入全量链）；runner 仓 `deploy/cloud-init-runner.yaml.tpl`（cloud-init 模板；消费形态摘要并入 docs `runner/features/target-bootstrap.md`）。gate：hub go build/vet/test 绿、console 8 smoke + build 绿、模板占位符替换后 YAML 解析通过 | 用户批准"1、2、3 都执行"（ADR → hub API → console 展示 → cloud-init 模板） |
| 2026-10-22 | **遗留项钢人裁定（完整记录 → `plans/STEELMAN-ADR2-LEFTOVERS-2026-10-22.md`）**：O-1 enrollToken 消费端**升 P0 立即做**——查实为已交付链路功能断点（runner `main.go:65` `mustEnv("TARGET_AUTH_TOKEN")`、全仓无 `SDP_ENROLL_TOKEN` 消费；hub `gateway.go` WS 握手只认共享 token + 自报 `X-Target-Name`，一次性 token 铸发端有、消费端两侧皆无）。设计：hub 握手三态鉴权（共享 token dev 保留 / enroll token 消费换 per-target 凭据经 101 响应头返回 / per-target 凭据服务端反查，X-Target-Name 降级断言）+ runner 三态发送（凭据文件 → 首拨换凭据落盘 0600 → legacy 回落）。#2 Web PKI 与 #3 二进制托管维持记档、各挂触发条件（详见钢人文档 §8） | 双向钢人论证 + 用户裁定"join 链路近期真实投用"；用户反馈简记过于简略，完整分析落独立文档 |
