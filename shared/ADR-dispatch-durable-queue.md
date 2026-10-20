# ADR-002: Hub 下发机制 —— 耐久队列 + 混合交付

- **状态**：Accepted
- **日期**：2026-08-26
- **决策者**：平台 owner（经多轮双向钢人论证确认）
- **相关文档**：[DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)（服务树/组件/三表/快照关系）、[STORY-BACKLOG.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md)

---

## 1. 背景（Context）

hub 触发流水线时，当前链路是：`PipelineRunService.Trigger` 先写 `PipelineRun` + `TaskRun` 行，再经 gateway 的 WebSocket **主动推送** `ApplyPipelineRunPayload` 给 runner（`internal/run/service/pipeline_run.go:77-148`）。

问题：推送是**同步硬闸门**——runner 离线即 `ErrNoRunner`，`Trigger` 把 run 直接标 `Failed` 并返回错误（`pipeline_run.go:141-145`）。这意味着：

1. hub 下发**强依赖 runner 实时在线**，runner 一离线，触发即"失败"，无排队、无重投；
2. 没有"我已被受理、稍后投递"的耐久记录，前端无从得知"卡在队列"还是"在 runner 上跑"。

owner 重新审视了"hub 与 runner 的交接机制 + 状态真相源"，经过五轮钢人论证，定下本 ADR 的两项决策。

---

## 2. 决策（Decisions）

### 决策 A：混合最小改动 —— 保留 K8s 控制器 + CRD 执行 + WS 推送，仅把下发层改为"先落耐久记录、再通知"

- **保留**：runner 是 K8s 控制器（controller-runtime + CRD），spec 经 WS 推送交付、状态走 CR status 回写（已核实 runner 源码**零** Postgres/Redis/轮询）。
- **改变**：hub 下发不再把 WS 推送当硬闸门。改为
  1. 先把"待下发"作为耐久记录落库；
  2. 再尝试经 WS 通知 runner；
  3. runner 离线 → 记录保持 `pending`（**不标 Failed**）；
  4. runner 连线或定时任务重投（re-drain）。

> 否决的方案："runner 轮询 DB/Redis 的 worker、丢掉 controller/CRD 链路"。理由：runner 本质是 K8s 控制器，改成 DB/Redis 轮询 worker 要废弃现有 CRD 执行路径，是大重构，且丢失 CRD 自愈/kubectl 可观测性。

### 决策 B：下发缓冲用**独立队列表 `dispatch_jobs`**，不用 `pipeline_runs` 上的列

- `dispatch_jobs` 为 1:多表：一条 `PipelineRun` 可对应多条下发记录。
- 字段：`id` / `pipeline_run_id`(FK) / `target_id`(即环境 id，环境↔runner 1:1) / `payload`(JSON `ApplyPipelineRunPayload`) / `state`(`pending|dispatching|dispatched|failed|dead`) / `attempts` / `last_error` / `next_retry_at` / `created_at` / `updated_at`。
- 索引：决策按查询形状定为 `(target_id, state, created_at)` 复合索引；**落地实现为三个单列索引**——`pipeline_run_id` / `target_id` / `state` 各建一个（GORM tag `index`，见 `internal/run/models/dispatch_job.go:35-43`）。

> 否决的方案：在 `pipeline_runs` 上加 `dispatch_state/attempts/next_retry_at` 列。理由：见决策变量。

---

## 3. 决策变量（key variable，决定 B 走向）

owner 明确：

- **环境 ↔ runner 1:1**（稳定不变量）；
- **一次流水线下发会扇出到多个环境 / region / k8s 集群**（类生产、生产、不同 region）；
- **页面可"下发重试流水线"**（同一 run 可再次下发）。

→ 一条 `PipelineRun` 会对应**多条下发记录**（每目标环境一条；重试再生成新记录）。下发记录与 run 为 **1:多**。

列方案把"下发"锁死成 run 行的 1:1 属性，扇出/重试时直接撑爆、必返工；独立表的 1:多形状**原生支持扇出 + 重试，零 schema 变更即可扩展**。故选表。

---

## 4. 依赖的上游不变式（Upstream invariants）

本 ADR 建立在已确认的上游决策之上（详见 [DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)）：

1. **流水线锁死单个 component**：pipeline 永远锚定一个 Component，阶段/子任务协同只在单组件内。故"多环境扇出"是同一 pipeline 对不同 target 的多次下发，不涉跨组件编排。
2. **三表规范化拆分正确**：`Pipeline / PipelineStage / PipelineTaskTemplate` + `pipeline_versions` 快照。执行期进度按 `(pipeline_run_id, stage_name, status)` 细粒度、索引化、部分读取；故前端轮询走轻量进度端点，不返回整份定义。
3. **前端有独立视图模型**：DAG 编辑器 → `toPipelineDefinition()` 映射器 → 一次性发送聚合 `PipelineDefinition`；对应发生在"聚合 DTO + 映射函数 + 契约测试"边界，非逐字段镜像实体。

---

## 5. 后果（Consequences）

**正面**
- hub 下发与 runner 可用性解耦：离线=排队，连线即投，定时重投。
- 状态真相源仍是 DB（`pipeline_runs`/`task_runs`），前端只轮询 DB，符合 owner 预期。
- 原生支持多环境扇出 + 页面重试，无需后续 schema 变更。
- 改动局限于 hub 下发层 + gateway 连线钩子，不动 runner 控制器/CRD。

**负面 / 成本**
- 新增一张表、一个 repository、gateway 连线钩子、一个后台 sweep goroutine（运维面略增）。
- 需处理并发重投（`MarkDispatching` 乐观占坑），避免多 ticker/连线重复投。
- 产物/结果落库（`ResultRef`/`ArtifactRefs`）需额外字段 + runner 侧补发（跨模块 gap，单列待排期，见 §6）。

---

## 6. 待办 / 扩展（out of scope 本 ADR，但已登记）

- **D. 产物/结果落库（跨模块）**：`TaskRun` 加 `ResultRef`/`ArtifactRefs`；`runnerapi.TaskRunStatusSummary` 加 `ExitCode`/`ArtifactRefs`/`ResultRef`；`ApplyStatus` 写回；runner 侧需补发这些字段。**（仍单列待排期）**
- **二期·多环境扇出**：✅ 已实现。`TriggerRequest.TargetIDs []uuid.UUID`；`triggerFanout` 每环境建一条独立 `PipelineRun` + 一条 `dispatch_jobs` 并 `tryDeliver`；目标只需存在（不要求在线），离线即排队。
- **二期·页面重试**：✅ 已实现。`Redispatch(ctx, runID)`：取该 run 最近一条 `dispatch_jobs`（`LatestByRun`），拷贝其 payload 建新 `pending` 记录并 `tryDeliver`；`dead`/`failed` 才重投，`dispatched`/`dispatching` 幂等跳过；run 卡 `Failed` 则重置 `Pending`。新端点 `POST /runs/:id/redispatch`。

---

## 7. 备选方案（Alternatives considered）

| 方案 | 结论 |
|---|---|
| runner 轮询 DB/Redis worker（废 CRD） | 否决：大重构，丢 K8s 原生能力 |
| hub 下发 = 同步 WS 推送（现状） | 否决：离线即失败，无队列/重投 |
| `pipeline_runs` 加列表达下发状态 | 否决：1:1 锁死，扇出/重试返工 |
| 独立 `dispatch_jobs` 队列表（**选中**） | 采用：1:多、耐久、解耦、可扩展 |

---

## 8. 验证门禁（Verification gates）

- hub：`go build` / `go vet` / `gofmt` / `go mod tidy` 全绿。
- 单测三态：①离线→run 保持 Pending、job pending；②连线→job 被 dispatch、run 随状态推进；③WS 写失败→attempts++、进入重试。
- 二期补：单 run ↔ 多 `dispatch_jobs`（两环境各一条）验证。

---

## 9. 实现状态（二期已落地）

**新增 / 改动文件**
- `internal/run/models/trigger_request.go`：`TriggerRequest` 增 `TargetIDs []uuid.UUID`。
- `internal/run/service/pipeline_run.go`：
  - 抽出仓库接口 `PipelineRunStore / TaskRunStore / PipelineDefStore / StageStore / TaskTemplateStore / TargetStore`（测试可注入内存 fake，无需 Postgres）。
  - `Trigger` 改返回 `[]*PipelineRun`；新增 `triggerFanout`（每环境一条独立 run，保持 run↔target 1:1 不变式）+ `createRun`（建 run/seed task_runs/入队）。
  - 新增 `Redispatch(ctx, runID)`：`LatestByRun` 取最近 job → 拷贝 payload 建新 `pending` job → `tryDeliver`；返回重取后的 job 状态。
  - `DispatchJobStore` 接口加 `LatestByRun`。
- `internal/run/repository/dispatch_job.go`：新增 `LatestByRun(pipelineRunID)`。
- `internal/run/handler/pipeline_run.go`：`Trigger` 返回 `[]*PipelineRun`；`Redispatch` handler + 路由 `POST /runs/:id/redispatch` + swag 注解。
- 测试：`pipeline_run_dispatch_test.go`（`fakeDispatchStore` 补 `LatestByRun`）；`pipeline_run_phase2_test.go`（内存 fake + 5 个测试：扇出在线/离线、重下发 dead→投、重下发离线挂起、无 dispatch 记录报错）。

**验证门禁（全绿）**：`gofmt` / `go vet ./...` / `go build ./...` / `go mod tidy` / `go test ./internal/run/...`（9 个用例通过）。
**零 schema 变更**：未新增/改动任何表结构（扇出/重试完全复用 `dispatch_jobs` 1:多 形状）。

---

## 10. 线协议类型一致性约定（保持统一）

> 本节约束 hub 与 runner 之间**线协议类型定义**的归属、副本与变更流程；与 §2–§9 的下发机制决策正交，但同属「hub↔runner 线协议」这一跨组件事实，故同住本 ADR。
> 背景与实施方案原计划见 `plans/HUB-DECOUPLE-RUNNER-PROTOCOL-2026-10-13.md`，该计划已于 实施完成并关闭（方案 D：hub 内 `internal/runnerproto` 派生副本）。本节即落地后的权威约定。

### 10.1 事实来源（SSOT）

- **`software-distribution-platform-runner` 仓库的 `api/v1alpha1` 是 hub↔runner 线协议的唯一事实来源**：协议类型、枚举值、JSON tag、`MessageType` 常量、各 `*Payload` 的信封结构，权威定义都在 runner 侧。
- 证据：hub 全仓 28 处 import 全部指向 `.../runner/api/v1alpha1`（19 生产 + 9 测试），是 hub 与 runner 之间唯一的源码级引用边。

### 10.2 hub 派生副本（方案 D）

- hub 在 `internal/runnerproto/` 持有一份**派生快照**：仅含 hub 实际引用的类型 + 其传递闭包（不含 CRD 根对象 `PipelineRun`/`TaskRun`/`Rollout` 及 `*List`/`*Status`、不含 `TaskRunSpec`、不含 `zz_generated.deepcopy.go`、不含 `groupversion_info.go` 的 scheme 注册与 `init()`）。
- 该副本**不是第二真相源**，是 runner 源码的镜像。`internal/runnerproto/doc.go` 头注释须标注**来源 runner commit SHA + 变更流程**，并写明「runner 为 SSOT，本包为派生快照」。
- import 别名保留 `runnerapi`（与原 `runner/api/v1alpha1` 一致），因此 hub 调用点无需逐个改代码。

### 10.3 变更同步流程

任何线协议变更**先在 runner `api/v1alpha1` 落地**，再按下列顺序同步，runner 是变更发起方与权威：

1. runner 侧改类型 / 枚举 / JSON tag；
2. 手动镜像到 hub `internal/runnerproto`（JSON tag 逐字符照抄、常量值逐字照抄、传递闭包全复制、排除 kubebuilder 标记与 `zz_generated`）；
3. 重跑 hub **Phase 3 契约测试**（字节级 JSON round-trip 一致性 + 枚举值断言）；
4. 契约测试失败 = 副本与源不一致，必须先修副本再合并。

### 10.4 兼容性规则（破坏性变更一律升版本）

- 线协议字段与枚举**只增不删、不改枚举字符串值**——枚举字符串已落库（`pipeline_runs`/`task_runs`/`rollout_runs` 的 `phase` 列等），改值即破坏既有数据；
- 新增字段必须 `omitempty` / 向后兼容；
- 破坏性变更须将协议从 `v1alpha1` 升到 `v1beta1`（或 `v1`）并做双版本过渡，不得原地破坏 `v1alpha1` 消费者。

### 10.5 独立构建（禁止源码级跨仓耦合）

- hub / console / runner **三仓各自可独立** `go build ./...` / `go vet ./...` / `go test ./...` / `make package`；独立构建是默认底线，不是功绩（不因此加标榜注释）。
- hub **不再经 `go.mod replace` 跨仓引用 runner 源码**（已拆除，由 §10.2 的 `internal/runnerproto` 副本取代）；`go list -deps ./... | grep -i runner` 必须为空。
- 违反独立构建的典型症状：构建期才以 opaque 错误暴露（如 `make package` 报「找不到 ../software-distribution-platform-runner」超时），属缺陷而非预期行为。

### 10.6 保持统一的守卫

hub `internal/runnerproto` 副本与 runner `api/v1alpha1` 源**必须保持字节级 JSON 一致**；一致性由 hub Phase 3 契约测试守护，不一致即 CI 失败。任何一端改了协议而另一端未同步，都被该测试拦下——这是「保持统一」的唯一可执行机制。

### 10.7 实施状态（已完成 · 方案 D）

- **副本已落地**：`software-distribution-platform-hub/internal/runnerproto/`（`doc.go` / `message.go` / `payload.go` / `phase.go` / `status.go` / `spec.go` / `param.go`），来源 runner commit `cfe8619a0ec2f77b03214bb36a199f100c932b7e`。
- **构建耦合已拆除**：hub `go.mod` 的 `require .../runner` 与 `replace => ../runner` 已删除；28 个 `*.go` 文件（19 生产 + 9 测试）的 import 已从 `runner/api/v1alpha1` 切换为 `internal/runnerproto`，别名 `runnerapi` 保留、调用点零改动。
- **独立构建验证**：`go list -deps ./... | grep -i runner` 为空；`go build ./...` / `go vet ./...` 通过；hub 不再依赖 runner 源码树。
- **契约测试守护**：`internal/runnerproto/contract_test.go` + `internal/runnerproto/testdata/contract/*.json`（14 个 runner 真实序列化样本）。测试用 `DisallowUnknownFields` 解码再编码并 `JSONEq` 比对；已做一次「故意改坏一个 JSON tag → 测试失败」的破坏-恢复验证，证明测试真能拦下漂移。`make package` 的最终独立构建门禁建议在目标 Linux/amd64 机器补跑（本机 macOS 仅跑通 build/vet/单包测试）。
- **未采用方案 A/B**：未抽独立协议仓库、也未在 runner 内建子模块——避免引入版本化模块源（在 `goproxy.cn` 不通的部署环境下反而会被卡死），符合「最小新增基础设施」约束。
