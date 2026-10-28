> **来源**：[plans/release-governance.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/release-governance.md)（O-38/O-39 设计草案）与 [plans/target-runtime.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/target-runtime.md)（O-41 设计草案）；API 契约以 [shared/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) 为准。
> **拆分说明**：plans 文档是**设计起草记录**（证据 + 改动点 + 钢人），本文件是**行为规格**（运行治理三件套如何工作：可部署版本来源、运行级超时、同 pipeline 并发/排队）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

运行治理三缺口：① canary 回滚到指定版本缺目标来源（制品库里的"可部署版本"没有只读端点）；② 长尾/卡死 run 无自动终止，占住 target 与配额；③ 同 pipeline 可无限并发 trigger，资源争抢与重复部署冲突无约束。

## 2. 可部署版本（O-38）

- `GET /components/:id/versions`：返回组件**可部署版本**列表（新→旧）。数据源 = `artifacts` 表中该组件 `cleanup_state<>'pending_deletion'` 的制品行，按版本去重、每版取最新一条；非全历史、非 pipeline 结构快照。
- 限流参数：`?limit=` 默认 50、上限 100（超过夹取，非 400——与 pipeline versions 端点的"超限 400"语义**不同**，前者是分页窗口、本端点是展示上限）。
- 响应项：`{ version, publishedAt, source: "artifact", artifactRef }`。
- 消费方：console 灰度控制台「回滚到指定版本」的目标选择器（契约：`console/features/ui-09-backend-deps-api-contract.md` 附 A · N-33）。

## 3. 运行级超时（O-39）

- **字段链**：触发体可选 `timeoutSeconds` → `TriggerRequest.TimeoutSeconds` → `PipelineRunSpec.TimeoutSeconds`（runnerproto 既有协议字段）→ `pipeline_runs.timeout_seconds`（迁移 0021）。`0`/缺省 = 不限。
- **计时口径**：`COALESCE(start_time, created_at) + timeout_seconds`——run 未被 runner 领取（仍 Pending）也计时，从创建时刻起算。
- **清扫作业**：hub `SweepRunTimeouts`（ticker `RUN_SWEEP_INTERVAL`，默认 **0=关闭**，与 `ARTIFACT_GC_INTERVAL` 同款"会改状态的作业不由部署悄悄打开"约定）把超时且非终态的 run 批量置 `Failed`，`Message=PipelineRunTimeout`（无独立 reason 列，前端按 Message 展示"超时失败"），写 `CompletionTime`。
- **副作用链**：与任何其他终态转换一致——finished-hook（trigger 评估）与通知订阅 sink 照常触发，panic 隔离。
- **边界**：清扫是 hub 侧软终止——不向 runner 发 cancel、不清理 runner 在途任务容器；runner 侧任务结束后回报的状态被 ApplyStatus 的终态幂等短路丢弃（run 已 Failed 不再改写）。

## 4. 同 pipeline 并发/排队（O-41）

- **策略落点**：pipeline 定义层（`pipelines.concurrency_policy`，迁移 0023），非每次 trigger。三枚举：`allow`（默认，行为与历史完全一致）/ `queue` / `forbid`。空值归一为 `allow`；非法值在 pipeline Create/Update 即 400。
- **容量口径**：活跃 run = `Pending` + `Running` + `WaitingApproval`。**`PendingQueue` 不占容量**（排队 run 不占坑，否则前序终态后永远无空位可唤醒）。上限 N = `RUN_CONCURRENCY_LIMIT`（默认 4）。
- **守卫时机**：`createRun` 内、任何持久化之前——
  - `forbid`：活跃数 ≥ 1 → `409 + {reasons}`（`ERR.09xx...`），不留半个 fan-out（多 target fan-out 下第一个 target 成功、后续 forbidden 时整体回滚不发生——守卫在 per-target createRun 层，fan-out 前序成功行保留）。
  - `queue`：活跃数 ≥ N → 新 run 直接落 `PendingQueue` 阶段（迁移新增运行阶段，非终态），其首个 dispatch job 落 **held** 态：`SweepPending`/`DrainTarget`/`MarkDispatching` 均按 state 过滤跳过 held，不会投递。
- **唤醒**：`SweepQueued`（与超时清扫同一 ticker）按 pipeline 分组，从最老排队 run 开始补足容量：run 回 `Pending` + held job 释放为 `pending`，之后走正常派发链（DrainTarget/SweepPending）。
- **排队 run 的取消**：`POST /runs/:id/cancel` 对 `PendingQueue` 为 **hub 侧本地终态**（未派发、无 runner 在途工作）：直接置 `Cancelled` + held job 退役（dead），不需要 runner 在线。
- **runner 感知面**：`PendingQueue` 是 hub 侧状态机概念，runner 永远收不到 PendingQueue 的 run（held job 不投递）；runner 状态机/协议零改动。

## 5. 验证 gate

- 单测（`internal/run/service`）：forbid 第二次触发 409 且不落库；queue 排队落 PendingQueue + held job、前序终态后 SweepQueued 唤醒回 Pending 并释放 job；超时清扫只打超时非终态 run（新鲜/无超时 run 不动）。
- 全量：hub `go build`/`vet`/`test` + `gofmt -l` 全绿（31 包 ok）。
- 静态契约：`API-REFERENCE.md` 已登记 `concurrencyPolicy` / `timeoutSeconds` / `/components/:id/versions` / PendingQueue 语义。

## 6. 变更历史

| 日期 | 变更 |
| --- | --- |
| 2026-10-26 | 首次成文：O-38/O-39/O-41 行为规格，随代码落地（hub 31 包 gate 绿）。 |
