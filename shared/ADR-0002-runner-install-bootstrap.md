# ADR-0002：Runner 安装引导（join-bundle API，安装数据收编为 hub 能力）

- 状态：已采纳（2026-10-22 钢人论证 + 用户裁定存在无人值守安装诉求）
- 关联：`ADR-0001-runner-first-connect-enrollment.md`（首连自注册）、`DATA-MODEL.md` §9.9（enroll-token / agent_ops 接入编排）、`plans/GAP-BACKEND-TLS-2026-10-22.md` §6（业界方案对比与选型）、`CERTIFICATES.md` §3（`hub-tls` secret 契约）
- 落码：hub `internal/target/service/joinbundle.go` + `internal/target/handler/target.go`（`POST /targets/:id/join-bundle`）；console 目标页安装命令展示；runner 仓 `deploy/cloud-init-runner.yaml.tpl`

## 1. 背景与问题

hub/keycloak 后端 TLS 化后（`hub-tls` 体系），集群外 runner 安装需要三样安装数据：**网关对外 URL**（`wss://…/gateway/ws`）、**CA 信任根**（自签，集群外主机默认不信任）、**引导凭据**（target / enroll token）。历史形态是"独立于平台的安装物料"（手工拷文件 + 手写 env），与集群实际状态漂移，且无人值守（cloud-init 批量装机）场景下人工搬运不可行。

**约束（bootstrap 悖论）**：自签 CA 无第三方背书，任何经 TLS 的带内通道都无法分发它自己的信任根——包括 enroll 端点。目标机在信任建立前连不上任何 hub API。因此"安装数据"的消费方只能是**已信任通道上的主体**：操作者会话（OIDC / kubectl）或装机管线（IaC，如 cloud-init userdata 注入通道）。

业界范式（`GAP-BACKEND-TLS` §6）：kubeadm `join`（token + CA pinning hash，在已信任机器上生成、带到无信任节点）、smallstep `step ca bootstrap --fingerprint`、GitLab Runner `certs/` 约定路径 + CM 分发、SaaS 平台公网端点走 Web PKI。共同点：**join 数据在信任侧生成，无信任侧只消费产物**。

## 2. 备选方案与双向钢人

### 方案 A：hub join-bundle API（已采纳）

hub 新增 `POST /api/v1/targets/:id/join-bundle`（用户 RBAC，与 target 管理同层鉴权），一次性返回：

| 字段 | 来源 | 说明 |
| --- | --- | --- |
| `gatewayUrl` | hub 配置 `HUB_PUBLIC_URL` + `/gateway/ws` | 网关对外地址（URL 契约两态：集群外用网关地址 / 集群内用 svc 地址） |
| `apiBaseUrl` | `HUB_PUBLIC_URL` | REST 下载/上传基址 |
| `caPem` / `caFingerprint` | hub 进程读 `HUB_TLS_CA_FILE`（默认与 server 证书同目录 `ca.crt`） | fingerprint = RFC7469 SPKI SHA256（kubeadm 同款格式 `sha256:<hex>`），供目标机自校验完整性 |
| `enrollToken` | 复用 §9.9 `GenerateEnrollToken`（24h 单次） | per-target 引导凭据；消费端 = per-target WS 鉴权链（演进中），当前 runner 侧仍走 ADR-0001 自注册 + 共享 `GATEWAY_TOKEN` |
| `runnerVersion` | 包版本矩阵（§9.10） | 与 `/targets/:id/install` 编排一致 |

消费方与消费路径：

- **人工在场**：console 目标页调同一 API 展示 join-command（env 片段 + 校验命令），运维复制到目标机执行。
- **无人值守**：装机管线（Terraform/cloud-init）先调 API 取 bundle → 内嵌进 target 主机的 userdata → 目标机开机自举（写 CA / 渲染 env / systemd 启动 runner）。**IaC 本身就是带外信任通道**。
- **TLS 信任锚两态**：云上有公网域名 → 网关入口换公网证书（Web PKI），目标机 OS 信任根直连，`caPem` 仅作校验冗余（首选）；私有网络 / dev → bundle 的 `caPem` 内嵌 userdata 建信任（fallback）。

| 钢人（支持） | 反钢人（反对） |
| --- | --- |
| kubeadm join-command 同款范式，业界已验证；安装数据单一真源 = hub，杜绝文档漂移 | API 面扩大是长期契约（鉴权/RBAC/文档/兼容），而 per-target 鉴权尚未闭环，有建在半成品之上的风险 |
| 复用 §9.9 enroll-token 铸发端与 target RBAC，零新信任面 | `HUB_PUBLIC_URL` 是新增配置（hub 需知道对外地址），配错则 bundle 不可用——需启动日志显式提示 |
| 人工/无人值守一套代码：console 展示与 cloud-init 消费同一端点 | CA 读取依赖 hub-tls 挂载（明文部署的 hub 无 CA，端点须明确降级 501 而非静默返回空） |

### 方案 B：env 仓静态安装物料脚本（未采纳为主路径）

`kubectl get secret hub-tls` 导出 CA → 渲染 env 文件 → scp 到目标机（`GAP` §6 短期 B 派）。

| 钢人（支持） | 反钢人（反对） |
| --- | --- |
| 零 hub 改码，dev 立即可用 | 物料旁支于平台，与集群状态漂移（正是本 ADR 要消灭的形态） |
| 不依赖 `HUB_PUBLIC_URL` 新配置 | 无人值守场景没有"运维跑脚本"的位置，管线下发仍是手工拼装 |

**裁定**：B 降级为 dev/过渡手段保留在 `GAP` §6，不作为终态。

### 方案 C：enroll 响应返回 CA（否决）

bootstrap 悖论直接否决：enroll 经网关 TLS，目标机连 enroll 前就要先信任——带内通道发不了自己的信任根。该设想已在钢人论证中废弃，仅存档。

### 与 ADR-0001 / §9.9 的关系

互补不冲突，且是 ADR-0001 §5 遗留的收口第一步：ADR-0001 解决"target 不存在时自动建行"（凭据 = 共享 `GATEWAY_TOKEN`）；本 ADR 解决"安装数据怎么可靠到达目标机"（凭据 = 用户 RBAC 铸发 per-target enrollToken）。演进路径：join-bundle v1（安装数据单源化）→ per-target WS 鉴权链落地后 enrollToken 被消费 → 共享 token 收敛为纯引导凭据（ADR-0001 §5 的终态）。

## 3. 安全边界

- join-bundle 走用户 RBAC（Keycloak → hub 权限权威），与 target 管理/`install` 编排同层；**不是**机器凭据通道。
- `caPem` 是公开物（公钥证书），经鉴权 API 下发的意义是**完整性由已信任通道保证**，非保密；fingerprint 供目标机侧二次自校验（kubeadm 语义）。
- `enrollToken` 沿用 §9.9 语义：单次、24h、明文只返回一次；在 per-target 鉴权落地前它只是预留凭据，不参与当前 WS 鉴权。
- `HUB_PUBLIC_URL` 未配置或 hub 明文部署（无 CA）时端点返回 501 + 明确原因，禁止静默降级。

## 4. 更新生命周期的边界

runner **二进制升级不走安装 API**：走既有 WS 通道下发（`agent_ops` 接入编排 + `agent_version` 回流闭环已就绪）。低频高危的信任引导与高频常规升级分属两个 API 面，避免耦合。

## 5. 验证记录（2026-10-22 落码实测）

- hub：`go build ./...` + `go vet` 全绿；`go test ./internal/target/...` 全绿（join-bundle 单测覆盖：PublicURL 未配置 → `ErrJoinBundleUnavailable`、CA 文件缺失 → 同错误、`ca.crt` 兄弟文件推导、RFC7469 SPKI SHA256 指纹与 kubeadm 口径一致、非 PEM 拒绝；enrollToken 复用 §9.9 路径依赖 DB，单测不覆盖，由真集群 E2E 兜底）。chart 渲染：无 `publicUrl` 不出 `HUB_PUBLIC_URL`、`gatewayRoute.enabled` 下 `HUB_TLS_CA_FILE` 恒在；`--set publicUrl=…` 正确渲染。
- console：`pnpm test` 8 个 smoke 全绿（新增 `target-smoke` 6/6：envFile 五要素、CA 路径一致、指纹自校验、heredoc 防展开、verifyCommand、copyText 降级）+ `pnpm build`（vue-tsc）绿。
- runner：`deploy/cloud-init-runner.yaml.tpl` 占位符按缩进契约替换后 `yaml.safe_load` 解析通过（3 write_files + 4 runcmd）。
- 真集群 E2E（外部主机 join → WS 回连、console 弹窗实测、cloud-init 实装）属部署验收 gate，随 `GAP-BACKEND-TLS-2026-10-22.md` B–E 项一并回归。

## 6. 遗留

- enrollToken 消费端仍未接（per-target WS 鉴权链，ADR-0001 §5 同款遗留）。
- 云上网关公网证书（Web PKI 信任锚）未实施——本地 kind 仍自签，外部主机 join 验证走 caPem 内嵌路径。
- join-bundle 未含 runner 二进制分发地址（下载源/镜像），装包仍由装机管线决定；如后续要平台托管安装包，扩 `runnerDownloadUrl` 字段。
