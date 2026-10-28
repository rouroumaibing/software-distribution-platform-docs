> **性质**：计划（**设计草案，待落地**）。状态以 [plans/STATUS.md O-40/O-41](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（F2.1、F4.2）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **命运裁定反转**：原 `NOT-NEEDED` 占位——2026-10-26 再分析判定为**可落地**：O-40 当前 agent-only 的 target 模型是 console 纳管非 agent 目标的真实阻塞（代码已证实 `targets` 无 `access_mode`）；O-41 并发语义可由 hub 侧 run 创建守卫低成本落地，不再是「纯产品留守」。二者均给出具体代码改动点。

---

## O-40 targets 扩 access_mode（F2.1）

**目标**：统一纳管面——扩 `access_mode`（agent/kubeconfig/ssh）+ 凭据引用，使 console 能管理所有目标类型（不仅 agent）。

**现状 / 证据（source-grounded 2026-10-26）**：
- `internal/target/models/target.go:12` `Target` 仅有 `TargetKind`（`k8s`/`host`）与 agent 通道字段（`EnrollToken`/`RunnerCredential`），**无 `access_mode`**；kubeconfig/ssh 直连不落 `targets` 表（原 plan 引用 `API-REFERENCE.md:51`）。
- `internal/target/service/agent_op.go:41` 注释提到 kubeconfig 直连仅作为 agent 纳管集群的解密凭据，非独立 target 类型。
- 既有 agent 通道：`Target.RunnerCredential` 是 WS 鉴权身份源（`target.go:28-32`），扩 access_mode 须保证 agent 路径零影响。

**设计方案**：
1. 枚举：`AccessModeAgent` / `AccessModeKubeconfig` / `AccessModeSSH`（新增常量，默认 `agent` 以保兼容）。
2. 模型：`Target` 加 `AccessMode string gorm:"size:16;not null;default:agent"` + `CredentialRef *string`（指向 `credentials` 表的凭据 ID，kubeconfig/ssh 模式必填、agent 模式留空）；迁移加列。
3. 注册入口：`internal/target/handler`（现有 `targetHandler.RegisterRoutes`）加 `POST/PUT /targets` 的 access_mode 校验（kubeconfig/ssh 必须带 `credentialRef` 且凭据存在）。
4. 既有 agent 通道：access_mode 字段对 agent 路径透明——`agent_op.go` 不读 access_mode，仅当 `agent` 时走 enroll/ws；非 agent 模式不生成 `RunnerCredential`，由 console/runner 按 `credentialRef` 直连。
5. console：非 agent 目标注册表单 + 凭据选择器（仅 UI，不阻塞后端）。

**落地步骤**：
1. `target.go` 加字段 + 常量 + 迁移。
2. `target/handler` 加创建/更新校验（access_mode 与 credentialRef 一致性）。
3. `target/service` 加按 access_mode 的取数/列表过滤（console 可区分展示）。
4. `API-REFERENCE.md` 登记字段。
5. 单测：agent 默认、kubeconfig 缺 credentialRef 拒绝、ssh 正常。

**验收 gate**：`go build/vet/test` 全绿；`kubeconfig` target 经 API 注册成功且 `credentialRef` 校验生效；既有 agent target 行为不变（回归测试）。

**钢人结论**：高可落地（加字段 + 一处校验，agent 路径不变）。「非 agent 目标是否需 hub 持久注册」已由「落 `targets` 表 + credentialRef 引用」回答，不再是开放产品问题。

## O-41 同 pipeline 并发 / 排队策略（F4.2）

**目标**：定义同 pipeline 多次 trigger 的并发上限 / 排队语义，防止资源争抢与重复部署冲突。

**现状 / 证据（source-grounded 2026-10-26）**：
- runner 无状态 worker 拉 Pending（`internal/controller` 拉 `pipelinerun`），同一 pipeline 可并发多 run；hub 侧 `internal/pipeline` 创建 run 时无并发约束（原 plan 已确认未核实）。
- 现有 `PipelineRunSpec` 无并发策略字段；`internal/run` 状态机不限制同源并发。

**设计方案**：
1. 策略枚举（落在 pipeline 定义层，非每次 trigger）：`ConcurrencyAllow`（默认，允许多 run 并发）/ `ConcurrencyQueue`（超上限则新 run 进 `pending_queue` 排队，前序终态后唤醒）/ `ConcurrencyForbid`（超上限直接拒新 run，`409`）。
2. 字段：`PipelineSpec.Concurrency *ConcurrencyPolicy`（默认 `Allow`）；`PipelineRunSpec` 记录所属策略快照。
3. 执行点：hub `internal/pipeline` 创建 run 时查同 pipeline 活跃（非终态）run 数：
   - `Forbid`：活跃数 ≥ 1（或上限 N）→ 拒创建，返回 `409 + reason`。
   - `Queue`：活跃数 ≥ N → 新 run 标 `phase=pending_queue`，由 reconciler 在前序终态后转 `running`。
   - `Allow`：无约束。
4. 上限 N 可配（默认如 4），避免无限排队。

**落地步骤**：
1. `internal/pipeline`（model + handler/service）加并发策略字段 + 迁移。
2. run 创建守卫（Forbid/Queue 两分支）+ reconciler 唤醒排队 run。
3. `API-REFERENCE.md` 登记。
4. 单测：Allow 并发、Forbid 拒创建、Queue 排队与唤醒。

**验收 gate**：`go build/vet/test` 全绿；`Forbid` 下第二次 trigger 返回 `409`；`Queue` 下新 run 进入 `pending_queue` 且前序终态后被唤醒；`Allow` 不变。

**钢人结论**：高可落地（hub 侧 run 创建守卫 + 状态机一处改动，无协议变更）。并发语义已由枚举三选一固定，不再是「纯产品留守」。
