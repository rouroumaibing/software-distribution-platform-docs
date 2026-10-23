> **来源**：[plans/STEELMAN-ADR2-LEFTOVERS-2026-10-22.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STEELMAN-ADR2-LEFTOVERS-2026-10-22.md)（ADR-0002 落码后遗留项双向钢人，#1 升 P0 并落码）；上游 [shared/ADR-0001-runner-first-connect-enrollment.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-0001-runner-first-connect-enrollment.md)（首连自注册）、[shared/ADR-0002-runner-install-bootstrap.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-0002-runner-install-bootstrap.md)（安装引导）。
> **拆分说明**：STEELMAN 文档是**双向论证记录**（为什么做、风险边界、裁定），本文件是**行为规格**（per-target WS 鉴权三态如何工作、信任如何锚定）。#1 已实现；#2（Web PKI）/ #3（二进制托管）为记档项，见 STEELMAN §8。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

历史形态：网关全局 `GATEWAY_TOKEN` + runner 自报 `X-Target-Name`（`gateway.go`）；chart 单值 `TARGET_AUTH_TOKEN` 跨所有 runner 共享，非 per-target 密码学身份。风险：**任何持共享 token 的 runner 可冒名未注册 / 他人 target**（横向移动）。

**目标**：runner 身份由 hub 服务端反查（token → target），自报 `X-Target-Name` 降级为一致性断言；引入 per-target 一次性 enroll token 作强身份锚，消除共享 token 冒名面。

## 2. 范围

### 2.1 In-scope
- hub WS 握手三态鉴权（共享 token / enroll token 首拨换凭据 / per-target 凭据反查）。
- runner 三态发送（凭据文件 → enroll token 首拨收凭据落盘 → legacy 共享 token 回落）。
- 物料零改动：join 命令 env 已含 `SDP_ENROLL_TOKEN`，共享 `TARGET_AUTH_TOKEN` 从装机物料消失。

### 2.2 Out-of-scope
- **#2 云上公网证书（Web PKI）**：与 #1 正交，触发条件 = 域名控制权确认 + 外部 runner 部署时间表。
- **#3 runner 二进制平台托管分发**：升级自动化立项时做，须带完整性校验/签名。
- 以上两项记档于 STEELMAN §8，未立项。

## 3. hub 握手三态鉴权（`internal/gateway/gateway.go` ServeWS）

1. `Bearer == GATEWAY_TOKEN` → **共享路径保留**（dev/内网过渡）。
2. 命中**未消费、未过期**的一次性 enroll token → 标记 used、生成 per-target 凭据（`crypto/rand`）落库（targets 新增 `runner_credential` 列，AutoMigrate 只加不删）、**101 响应头 `X-SDP-Runner-Credential` 返回**、按 enroll token 绑定的 target id 解析身份。
3. 命中某 target 的 `runner_credential` → **服务端反查 target**（身份源 = token），`X-Target-Name` 降级为一致性断言。

过期/已用 token → 拒绝（哨兵 `ErrEnrollTokenInvalid` 统一映射）。

## 4. runner 三态发送（`pkg/connector/client.go` + `cmd/runner/main.go`）

- 凭据文件存在（`SDP_RUNNER_CREDENTIAL_FILE`，缺省 `/etc/sdp-runner/credential`）→ 用 per-target 凭据拨号。
- 否则有 `SDP_ENROLL_TOKEN` → 用它首拨、从 101 响应头收凭据落盘 `0600`（gorilla `Dialer.Dial` 返回 resp，读响应头零障碍）。
- 都没有 → 回落 legacy 共享 token（dev 不破坏）。

`cmd/runner/main.go` 放掉 `mustEnv("TARGET_AUTH_TOKEN")`，改三态 env 接线；全无凭据 fail-fast。

## 5. 物料零改动

console / cloud-init 装机物料无需修改——join 命令 env 已含 `SDP_ENROLL_TOKEN`；共享 `TARGET_AUTH_TOKEN` 从物料中消失（见 `runner/features/target-bootstrap.md`）。

## 6. 代码证据（实测 file:line）

| 行为 | 位置 |
|------|------|
| targets `runner_credential` 列 | `hub/internal/models/target.go`（`RunnerCredential`） |
| enroll token 原子消费 | `hub/internal/repository/target.go`（`BurnEnrollToken` 事务内条件 UPDATE，RowsAffected==0 ⇒ 单次生效由 DB 保证） |
| 凭据反查 | `hub/internal/repository/target.go`（`GetByCredential`） |
| 凭据服务 | `hub/internal/service/credential.go`（`ConsumeEnrollToken`/`GetByCredential`，`ErrEnrollTokenInvalid`） |
| WS 三态鉴权 | `hub/internal/gateway/gateway.go`（`ServeWS` 鉴权段 + `serveTarget` 公共段） |
| runner 三态发送 | `runner/pkg/connector/client.go`（`WithEnrollBootstrap` + `currentToken` 三级解析 + `persistCredential` 0600） |
| runner 三态 env 接线 | `runner/cmd/runner/main.go`（放掉 `mustEnv("TARGET_AUTH_TOKEN")`） |

## 7. 测试与验收

- **单元（hub/runner 各自）**：`go build`/`go vet`/`go test` 全绿；鉴权三态单测覆盖——共享 token、enroll token 首拨换凭据、per-target 凭据反查、过期/已用 token 拒绝（新增 `credential_test` 两侧）。
- **真集群 E2E**：外部主机 join → 三态握手 → 凭据落盘 → 后续拨号走 per-target 凭据，随 `GAP-BACKEND-TLS` B–E 一并回归。
- **状态**：代码已落盘（§6），真集群 E2E 待回归。

## 8. 决策记录（指针）

双向钢人论证、判定理由、#1 三态鉴权设计方案、#2/#3 记档条件见 [STEELMAN-ADR2-LEFTOVERS-2026-10-22.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STEELMAN-ADR2-LEFTOVERS-2026-10-22.md)。ADR-0001 的 ⚠️（共享 token + 自报身份）在 per-target 态收口。

## 9. 实现记录

- **hub**：`internal/models/target.go`、`internal/repository/target.go`、`internal/service/credential.go`、`internal/gateway/gateway.go`
- **runner**：`pkg/connector/client.go`、`cmd/runner/main.go`
- **关联特性**：`runner/features/target-bootstrap.md`（安装数据与 CA 信任锚）
