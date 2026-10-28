> **性质**：计划（**设计草案，待落地**）。状态以 [plans/STATUS.md O-38/O-39](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（F2.2、F4.3）与 `plans/PLAN-DRAFT-ACTIONABLE-2026-10-20.md`（F2.2、F4.3）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **命运裁定反转**：原 `NOT-NEEDED-NOW` 占位——2026-10-26 再分析判定为**可落地**：O-38 是 canary 回滚闭环的最后一环（阻塞项），O-39 是长尾 run 资源占用的真实治理缺口，二者均有清晰代码改动点，不再推迟。

---

## O-38 组件可部署版本端点（F2.2，canary 回滚闭环）

**目标**：实现 `GET /components/:id/versions` 端点，为灰度「回滚到指定版本」提供目标来源，闭合 canary 回滚最后一环；配套 console picker。

**现状 / 证据（source-grounded 2026-10-26）**：
- `cmd/hub/main.go:573` `componentHandler.RegisterRoutes(api)` 已挂载组件路由，但 `internal/component/handler/component.go:22` 的 `RegisterRoutes` 无 `/versions` 子路由。
- `internal/component/handler/config_version.go:34` 已有 `ConfigVersionHandler.RegisterRoutes`，证明组件侧「版本」概念已存在（配置版本）；可部署版本的数据源 = 已发布/已落仓的制品版本，与 `internal/artifact` 同源。
- `API-REFERENCE.md` 的端点登记待补（原 plan 引用 `:105`），路由清单无该端点；canary 回滚缺目标版本来源（关联 O-17 版本/发布联动）。

**设计方案**：
1. 数据源：可部署版本 = 该 component 下 `status=released`/`published` 的制品版本（复用 `internal/artifact` 查询），不引入新存储；必要时叠加最近 N 次成功 `PipelineRun` 的产出版本作为回滚候选。
2. 新增 `ComponentHandler.ListDeployableVersions(c, componentID)`：返回 `[]DeployableVersion{Version, PublishedAt, Source(artifact|run), ArtifactRef}`；分页 + 上限（默认 50，与 `notification.List` 同型夹取）。
3. 路由：`component.go` 的 `RegisterRoutes` 内 `api.GET("/components/:id/versions", h.ListDeployableVersions)`。
4. console：`console` 仓库 canary 回滚弹窗接入该端点做 version picker（仅 UI 消费，不阻塞后端落地）。

**落地步骤**：
1. `internal/component/handler/component.go` 加 `ListDeployableVersions` + 路由。
2. `internal/component/service` 加 `ListDeployableVersions` 取数（复用 artifact repo 的 released 查询）。
3. `API-REFERENCE.md` 补端点登记 + swagger 注释（仿 `config_version.go` 的 swagger 风格）。
4. 单测：返回已发布版本、排除未发布、分页上限。

**验收 gate**：`go build/vet/test` 全绿；`curl /api/v1/components/:id/versions` 返回已发布版本列表；单测覆盖取数边界；console picker 可选项触发回滚（UI 侧端到端可选）。

**钢人结论**：高可落地（纯读端点、复用现有 artifact 查询、无 schema 变更）。原「数据源需先拍板」已被现有 released-artifact 模型消解。

## O-39 运行级超时 / 截止（F4.3，运行治理）

**目标**：为整个 PipelineRun 增加运行级超时/截止字段 + reconciler 终止逻辑，避免长尾/卡死 run 无自动终止、占用 target 与配额。

**现状 / 证据（source-grounded 2026-10-26）**：
- 任务级 `timeoutSeconds` 已存在（`API-REFERENCE.md:152` 引用），但 PipelineRun 级运行超时/SLA 截止无字段。
- `internal/run`（pipelinerun/taskrun controller 在 runner 仓）是终态管理位置；hub 侧 `internal/pipeline` 负责 run 创建与状态。

**设计方案**：
1. 字段：`PipelineRunSpec.TimeoutSeconds *int32`（仿任务级 `timeoutSeconds` 语义，零值=不限制）；`API-REFERENCE.md` 登记。
2. 终止语义：**超时 → `failed`**（带 `reason=PipelineRunTimeout`），与任务级超时不致命但 PipelineRun 级视为失败一致；取消语义留给 O-41 并发策略，不在此混用。
3. 执行点：hub `internal/pipeline` 的 run 状态机/reconciler 在每次状态推进时校验 `startedAt + TimeoutSeconds < now()` 且非终态 → 置 `failed`；或在 ticker 中统一扫描超时 run（与 O-37 的 `RunLogGC` ticker 同源，可合并）。
4. 前端：`console` 呈现超时 failed 原因。

**落地步骤**：
1. `internal/pipeline`（model + handler/service）加 `TimeoutSeconds` 字段 + 迁移（新增 nullable 列）。
2. reconciler/ticker 加超时校验，置 `failed(reason=PipelineRunTimeout)`。
3. `API-REFERENCE.md` 登记 + swagger。
4. 单测：超时 run 被自动 failed、未超时不动、零值不限。

**验收 gate**：`go build/vet/test` 全绿；构造 `TimeoutSeconds=1` 的 run，等待后状态为 `failed` 且 reason 正确；零值 run 不受影响。

**钢人结论**：高可落地（字段 + 状态机一处校验，无协议变更）。终止语义拍板为 `failed`（非 `cancel`），已在设计中固定，不再「等产品决策」。与 O-38 同属运行治理议题，可同批。
