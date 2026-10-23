> **来源**：[shared/ADR-0002-runner-install-bootstrap.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-0002-runner-install-bootstrap.md)（Runner 安装引导决策记录：背景 / 备选方案双向钢人 / 安全边界 / 验证记录）；原 `env/runner-install/` 消费形态摘要已并入本文件。
> **拆分说明**：ADR-0002 为**决策记录**（为什么做、方案权衡、安全边界），本文件为**特性规格**（行为契约：谁消费、何时消费、占位符契约、信任锚两态、验收），二者互补不重复。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

集群外 runner 安装需要三样**安装数据**：网关对外 URL（`wss://…/gateway/ws`）、CA 信任根（自签，集群外主机默认不信任）、引导凭据（target / enroll token）。历史形态是"独立于平台的安装物料"（手工拷文件 + 手写 env），与集群实际状态漂移，且无人值守（cloud-init 批量装机）场景下人工搬运不可行。

**约束（bootstrap 悖论）**：自签 CA 无第三方背书，任何经 TLS 的带内通道都无法分发它自己的信任根——包括 enroll 端点。因此"安装数据"的消费方只能是**已信任通道上的主体**：操作者会话（OIDC / kubectl）或装机管线（IaC，如 cloud-init userdata 注入通道）。

**目标**：安装数据单一真源 = hub `join-bundle` API；提供**人工在场 + 无人值守**两条消费路径，目标机首次开机即可自举并与 hub 建 WS 回连。

### 1.1 安装数据构成（来自 join-bundle）

| 字段 | 来源 | 说明 |
| --- | --- | --- |
| `gatewayUrl` | `HUB_PUBLIC_URL` + `/gateway/ws` | 网关对外 WS 地址（URL 契约两态：集群外用网关地址 / 集群内用 svc 地址） |
| `apiBaseUrl` | `HUB_PUBLIC_URL` | REST 下载/上传基址 |
| `caPem` / `caFingerprint` | hub 进程读 `HUB_TLS_CA_FILE`（默认与 server 证书同目录 `ca.crt`） | `caFingerprint` = RFC7469 SPKI SHA256（`sha256:<hex>`，kubeadm 同款格式），供目标机自校验完整性 |
| `enrollToken` | 复用 §9.9 `GenerateEnrollToken`（24h 单次） | per-target 引导凭据；当前 runner 侧未消费（ADR-0001 §5 遗留） |
| `runnerVersion` | 包版本矩阵（§9.10） | 与 `/targets/:id/install` 编排一致 |

## 2. 范围

### 2.1 In-scope
- **人工在场路径**：console 目标页「安装命令」弹窗 → 运维复制自举脚本到目标机 root 执行。
- **无人值守路径**：装机管线（Terraform/cloud-init）调 `join-bundle` → 替换 `deploy/cloud-init-runner.yaml.tpl` 占位符 → 注入 userdata → 目标机首次开机自举。
- TLS 信任锚两态（§5）。

### 2.2 Out-of-scope
- **runner 二进制升级**：走 hub WS 通道下发（`agent_ops` 编排 + `agent_version` 回流），不进安装 API。
- **enrollToken 消费端**（per-target WS 鉴权链）：ADR-0001 §5 同款遗留，未接。
- **平台托管 runner 二进制分发**：ADR-0002 §6 遗留，`join-bundle` 未含 `runnerDownloadUrl`；当前下载源由装机管线决定。

## 3. 任务流

### 3.1 人工在场

console 目标页调 `join-bundle` API → 渲染 env 文件 + 校验命令 + 复制 → 运维在目标机 root 执行（不依赖 cloud-init 模板）。

### 3.2 无人值守（cloud-init 模板，ADR-0002 §2）

1. 装机管线调 `POST /api/v1/targets/:id/join-bundle`（用户 RBAC）取 bundle。
2. 替换 `deploy/cloud-init-runner.yaml.tpl` 三个占位符：
   - `__CA_PEM__`：`caPem` 原文，块标量**每行缩进 6 空格**对齐。
   - `__JOIN_ENV_FILE__`：env 文件内容（格式同 console「复制 env」产物，含 `SDP_HUB_CA_FINGERPRINT` 供指纹自校验），**每行缩进 4 空格**。
   - `__RUNNER_BINARY_URL__`：runner 二进制下载地址（装机管线决定，平台不托管）。
3. 作为 userdata 注入目标机；首次开机自动完成 **CA 落盘 → 指纹校验 → 二进制落位 → systemd 启动**。

**占位符缩进契约**（YAML 块标量）：替换后须 `yaml.safe_load` 解析通过（3 `write_files` + 4 `runcmd`）。缩进错位会导致 cloud-init 渲染失败，装机管线必须按契约注入。

## 4. 后端依赖与 API 契约

- **端点**：`POST /api/v1/targets/:id/join-bundle`，用户 RBAC（与 target 管理/`install` 编排同层鉴权）。
- **不可用语义**：`publicUrl` 未配置 / hub 明文部署（无 CA）时端点返回 **501 + 明确原因**，禁止静默降级（caPem 是公开物，经鉴权 API 下发的意义是完整性由已信任通道保证，非保密）。
- **模板资产位置**：runner 仓 `deploy/cloud-init-runner.yaml.tpl`（随 runner 包发布，**不存任何环境值**，只承载消费形态）。

## 5. 信任锚两态（ADR-0002 §2）

- **云上公网证书（首选）**：网关入口 listener 换公网证书（Web PKI）后，目标机凭 OS 信任根直连，可去掉模板中 CA 落盘与指纹校验段。
- **CA 内嵌 userdata（fallback）**：私有网络 / dev；IaC 通道本身就是带外信任锚。

## 6. 测试与验收

- **单元（hub）**：`go test ./internal/target/...` 覆盖——`publicUrl` 未配置 → `ErrJoinBundleUnavailable`、CA 文件缺失 → 同错误、`ca.crt` 兄弟文件推导、RFC7469 SPKI 指纹与 kubeadm 口径一致、非 PEM 拒绝。
- **console**：`pnpm test` 含 `target-smoke` 6/6（envFile 五要素、CA 路径一致、指纹自校验、heredoc 防展开、verifyCommand、copyText 降级）。
- **模板**：占位符按缩进契约替换后 `yaml.safe_load` 解析通过（3 `write_files` + 4 `runcmd`）。
- **真集群 E2E**（外部主机 join → WS 回连、console 弹窗实测、cloud-init 实装）属部署验收 gate，随 `GAP-BACKEND-TLS-2026-10-22.md` B–E 项一并回归。

## 7. 决策记录（指针）

本特性决策与权衡见 [ADR-0002](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-0002-runner-install-bootstrap.md)：方案 A（hub join-bundle）采纳；方案 B（env 静态物料脚本）降级为 dev/过渡手段保留在 `GAP-BACKEND-TLS` §6；方案 C（enroll 响应返回 CA）因 bootstrap 悖论否决。

## 8. 实现记录

- **hub**：`internal/target/service/joinbundle.go` + `internal/target/handler/target.go`（`POST /targets/:id/join-bundle`）
- **console**：目标页「安装命令」弹窗（`src/utils/runnerInstall.ts` 渲染自举脚本 + `src/api/target.ts` `joinBundle()` + 复制）
- **runner 包部署资产**：`deploy/cloud-init-runner.yaml.tpl`（外部主机部署形态，与 `deploy/helm/` 集群内部署形态并列）
- **权威设计**：docs 仓 `shared/ADR-0002-runner-install-bootstrap.md`
