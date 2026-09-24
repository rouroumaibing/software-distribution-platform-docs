# 数据模型关系说明（Data Model Relationship）

> 本文档钉死软件分发平台 hub 的核心关系链，作为后续建模与代码审查的权威参考。
> 来源：`internal/org`、`internal/catalog`、`internal/component`、`internal/pipeline`、`internal/run` 各 `models` 包（已读源码核实，非推测）。
>
> **项目目标（对齐 console / runner）**：hub 是 SDP 的控制平面，为"通过界面交互把软件构建、测试、发布到多套环境"提供数据模型与 REST API 支撑。核心能力 = 组织 / 服务树 / 组件 / 环境 / 配置 / 流水线 / 运行 的 CRUD 与编排下发，以及运行态状态回收。标准流水线模式（日常 / 版本归档 / 转测 / 生产，见 console `CONSOLE-UI-DESIGN.md` §1.1）由 Pipeline（锚定单 Component）+ 阶段 + 三态任务（Build/Release/Approval）表达。落地顺序：先贯通基本功能（G1–G6 已完成），**权限管控（G7）已落实（P1 建表 / P2 审批子系统 / P3 Enforcement，见 §7）**。

## 0. 四条不动式（先记住这四句话）

1. **服务树是"导航/归属"层级，不是执行层级。**
2. **Component（服务组件）是资源边界**——流水线、环境、制品、组件配置、权限绑定都以它为锚。
3. **Pipeline 永远锚定单个 Component（不变式）**：一条流水线只关联一个组件，跨 component/service 编排不在范围内。
4. **运行期是快照语义**：`TaskRun` / `PipelineRun` 记录的是"触发那一刻的 DAG"，不持有对可变定义的对外键，权威阶段靠 `TaskTemplateID` 反查。

---

## 1. 定义链（配置态，规范化、有外键）

```
Org  ──1:1──▶  ServiceTree        (service_trees.org_id, unique)
  │
  └──1:N──▶  Service             (services.service_tree_id)   业务服务分组，如"交易服务"
               │
               └──1:N──▶  Component   (components.service_id)  叶子=服务组件，绑定一个 git 仓库
                              │
                              └──1:N──▶  Pipeline       (pipelines.component_id, not null)  定义级模板
                                             │
                                             └──1:N──▶  PipelineStage       (pipeline_stages.pipeline_id, sequence 排序)
                                                            │
                                                            └──1:N──▶  PipelineTaskTemplate (pipeline_task_templates.stage_id)
                                                                      Type: Build / Release / Approval
                                                                      Produces / Consumes (JSON) = 任务间产物依赖
                                                                      Build: Image + Command/Args（或 ScriptPath 脚本逃生通道）
                                                                      Release: ReleaseConfig（chart/manifest 源 + 从参数管理注入的 values）
                                                                      Approval: ApprovalConfig（Approval 专用）
```

### 1.1 关键交互语义
- **阶段间顺序执行**：`PipelineStage.Sequence` 决定先后。
- **阶段内子任务按 `ExecutionMode` 执行**（`PipelineStage.ExecutionMode`，**字段已落地 2026-09-22，见 §6.4**）：`Parallel`（**默认值**，同阶段子任务同时可运行、无相互依赖）/ `Serial`（**字段与 UI 已就绪、调度待实现**，同阶段子任务按序执行）。设计上 `Serial` 由 hub `buildSpec` 按序推导阶段内 `DependsOn` 链实现；runner 消费的是已解析 DAG，无需感知"串行/并行"——它只看 `DependsOn`。阶段间恒串行（跨阶段 `DependsOn`，**已实现**）。注（2026-09-22 更新）：`ExecutionMode` **字段已落地**（`pipeline_stages.execution_mode`，迁移 `0010`），阶段内 `DisplayOrder` 排序一向可写；**仍缺的是 `Serial` 的调度行为** —— hub `buildSpec` 尚未按序推导阶段内 `DependsOn` 链（backlog C-06），故 serial 阶段里的子任务在 runner 侧**仍并发启动**。
- **子任务交互**：`Produces`/`Consumes`（JSON 键）描述产物产出与消费；触发时 run service 直接 copy 进 `runnerapi.PipelineTaskSpec`，并跨 stage 推导 `DependsOn`。
- **类型分工**：`Build`=内联命令执行（如 `pytest`/`go build`，跑在 `Image` 工具镜像里；也支持 `ScriptPath` 脚本逃生通道）；`Release`=施加一个软件单元（`ReleaseConfig` 里的 chart/manifest 源 + 从参数管理注入的 `values`），可选 `RolloutConfig` 做金丝雀；`Approval`=人工卡点（结果写 runner CR 的 `ApprovedBy/RejectedBy`）。

---

## 2. 运行链（执行态，快照）

```
Pipeline  ──1:N──▶  PipelineRun    (pipeline_runs.pipeline_id + target_id + CRName + CRNamespace + pipeline_version)
                       │               PipelineRun 是 runner PipelineRun CR 的长期真源（CR 仅短 TTL 保留）
                       │
                       └──1:N──▶  TaskRun   (task_runs.pipeline_run_id)
                                     TaskTemplateID ──▶ PipelineTaskTemplate（反查权威 StageID）
                                     StageName        ── denormalized 快照字符串（带索引，仅供查询/分组，非 FK）
                                     Type / Phase / RetryCount / ExitCode / LogsRef / Message
```

### 2.1 为什么运行期不持有 Stage 外键
- `PipelineRun` 应比可变的 `Pipeline` 定义活得更久；pipeline 有 `version`，run 记录的是触发那一刻的 DAG 快照。
- 若给 `TaskRun` 加 `PipelineStage` 外键，会在 pipeline 版本变更/编辑时制造迁移痛，且破坏快照自洽性。
- 因此：**子任务↔阶段的权威关联在定义层靠 `stage_id`（FK），在运行层靠 `TaskTemplateID → StageID`（反查） + `StageName`（快照展示）。两者一致即可。**

---

### 2.2 阶段进展聚合（可选 `stage_runs`，高频查询用）

`task_runs` 已含 `StageName`（带索引），"阶段进展"可由 `WHERE pipeline_run_id=? GROUP BY stage_name` 现算（derive-on-read，零额外维护，**MVP 采用，已确认**）。若运行子任务极多、轮询频率高，可加 `stage_runs` 冗余聚合表（见 §6.4），由 `ApplyStatus` 同路径在每次 task save 后重算阶段 rollup，保持与 `task_runs` 一致。两种方案**双向钢人论证**见 §6.3（结论：确认不建 `stage_runs`，用户决策）。

---

## 3. Component 是资源边界（锚点一览）

以下资源表均以 `component_id` 为锚，印证"进组件页管理其全部资源"的使用方式：

| 资源 | 模型文件 | 锚点字段 |
|------|----------|----------|
| Pipeline（流水线） | `internal/pipeline/models/pipeline.go` | `ComponentID` |
| Environment（环境） | `internal/environment/models/environment.go` | `ComponentID` |
| Artifact（制品） | `internal/artifact/models/artifact.go` | `ComponentID` |
| Component Config（组件配置） | `internal/component/models/config.go` | `ComponentID` |
| Permission Binding（权限绑定） | `internal/permission/models/binding.go` | `ComponentID` |

---

## 4. 外键关系速查表

| 子表 | 字段 | 父表 | 说明 |
|------|------|------|------|
| `service_trees` | `org_id` | `orgs` | 1:1 |
| `services` | `service_tree_id` | `service_trees` | 1:N |
| `components` | `service_id` | `services` | 1:N |
| `pipelines` | `component_id` | `components` | 1:N（不变式：单组件） |
| `pipeline_stages` | `pipeline_id` | `pipelines` | 1:N，按 `sequence` 顺序 |
| `pipeline_task_templates` | `stage_id` | `pipeline_stages` | 1:N（子任务↔阶段权威关联） |
| `pipeline_runs` | `pipeline_id` | `pipelines` | 1:N，加 `target_id` + `version` 快照 |
| `task_runs` | `pipeline_run_id` | `pipeline_runs` | 1:N |
| `task_runs` | `task_template_id` | `pipeline_task_templates` | 可空，反查权威 `stage_id`（**不是** stage FK） |
| `environments` | `component_id` | `components` | 1:N（`ON DELETE CASCADE`，但组件是**软删** → cascade 不触发，见 §8.4） |
| `environments` | `target_id` | `targets` | **NOT NULL**；**裸 FK 无 cascade** → 删被引用的目标会 **FK 报错（500）**（见 §9.2） |
| `environments` | `group_id` | `environment_groups` | 可空（§8；**已落地** 2026-09-22，见 §8.9） |

---

## 5. 维护约定（给后续开发）

- 新增"资源"时，默认以 `Component` 为锚，保持组件页是唯一管理入口。
- 任何让 `Pipeline` 脱离单 `Component` 的改动的都违反不变式 #3，需先回到设计评审。
- 改动 `TaskRun.StageName` 语义前，先读 `internal/run/models/task_run.go` 的字段注释（快照、非 FK）。
- 运行态与定义态的关联一律走 `TaskTemplateID` 反查，不要在运行表新建对定义表的外键。

---

## 6. 流水线下发与进展回收（含双向钢人论证）

> 本章是 console `CONSOLE-UI-DESIGN.md` §6.0、runner `STORY-runner-implementation.md` §4.3 的落地依据。聚焦三个你点名的开放问题：① runner 怎么取任务；② 进展记在哪；③ 命令怎么跑。每个都做双向钢人论证后给推荐。

### 6.1 任务落地与下发机制（现状，推送模型）

触发 `POST /pipelines/:id/runs` → `PipelineRunService.Trigger`：
1. 落 `pipeline_runs` 一行（Pending）+ 按 spec 种子 `task_runs`（每 DAG 节点一行，Pending）—— **"任务先落实到数据库"在 hub 侧成立**；
2. 入队 `dispatch_jobs`（Pending）携带完整 `ApplyPipelineRunPayload`；
3. 立即尝试下发；Runner 离线则 job 保持 Pending，重连（`DrainTarget`）/ 周期扫（`SweepPending`）重投，运行不失败（状态机见 `dispatch_job.go`）；
4. Runner 经出站长连接收 `apply_pipeline_run` → 建 `PipelineRun` CR → 调度执行 → 每状态变更经 `status_update` 流回 → hub `ApplyStatus` 写回 `task_runs` / `pipeline_runs`。

> 结论前置：你设想的"任务先落 DB、runner 按 DB 任务执行"在 **hub 侧完全满足**；差异仅在"runner 怎么拿到任务"——是 DB 直连拉取，还是 hub 推送 spec 快照。见 §6.2。

### 6.2 双向钢人论证①：runner 拉 DB vs hub 推 spec

**正方（runner 直接读 hub DB 拉任务）**
- 极简心智：runner 是无状态 worker，定时 `SELECT * FROM task_runs WHERE target_id=? AND phase=Pending`，天然幂等，断线重连零成本；
- 单一真相源在 Postgres，排查只查一处；无需 WS 长连接与帧协议；
- 与你最初设想"任务先落 DB、runner 按 DB 执行"一字不差。

**反方（保留 hub 推送 spec + runner CRD 执行）** —— 现状采用
- **安全边界**：runner 是部署在各业务集群的 agent，不应持有 hub Postgres 凭据；推送模型 runner 只持 `TARGET_AUTH_TOKEN` 连 hub 网关，凭证/权限留在 hub（G7 在 hub 侧统一落实）；
- **离线容忍已内建**：`dispatch_jobs` 状态机让"集群暂时离线"不丢工作、不失败触发，重连即补投，比 DB 轮询更易保证"至少一次"投递；
- **执行态本就在集群内**：runner 是 K8s Operator，任务实际跑成 Job/CRD/etcd；让 runner 回头查 hub DB 是绕回控制面，违背"执行平面自治"；
- **实时回流**：WS 让状态秒级回写（进度轮询 2~3s 足够），DB 轮询要么高频打库、要么延迟大；
- **代价**：需维护长连接 + 帧协议 + 重投，复杂度高于轮询。

**结论（已确认）**：保留推送模型，DB 直连 runner 被否决（用户已确认此方向正确）。"任务先落 DB"诉求已通过 `pipeline_runs`+`task_runs`+`dispatch_jobs` 在 hub 侧满足——runner 执行的是 hub 已落库并下发的 spec 快照。若未来要支持"runner 主动拉取"（如边缘离线集群），应做**拉取适配器**：经 hub 只读 API + 游标/租约，而非让 runner 直连 Postgres。

### 6.3 双向钢人论证②：进展记在哪 + 高频查询（聚焦「`stage_runs` 表的创建必要性」）

**共识**：hub `task_runs` 是进展的**系统记录（system of record）**，runner CRD 仅短 TTL 执行态。console 只问 hub，不直接问 runner/集群。阶段进展 = 在 `task_runs` 上按 `StageName`+`sequence` 分组聚合的结果。

**方案 A：derive-on-read（读时聚合，不建 `stage_runs`）** —— 当前采用
- 每次 `GET /runs/:id/stage-progress`（或 `progress`）由 hub 后端按 `StageName` 分组现算阶段 rollup，随响应一并发出。
- 正方：零额外表、零一致性风险；`task_runs` 已按 `(pipeline_run_id, StageName)` 索引，单次轮询 O(N_tasks)，在现实并发（数十运行、每运行 <100 任务）下可接受；阶段状态永远等于其子任务状态的函数，**无漂移**。
- 反方：子任务极多（数百/千）时每次轮询扫全量 task 行，虽有索引仍随规模线性增长；阶段级"开始/结束时间"需从子任务 min/max 推算。

**方案 B：冗余 `stage_runs` 聚合表（建表）**

> 下面把"是否该建这张表"本身当作命题，做**正反双向钢人论证**。

**正方（应该建 `stage_runs`）—— 站在「高频查询 + 阶段级操作」立场**
1. **读路径与写路径解耦**：进度轮询是读主导（console 每运行 2~3s 一次的 stage 卡），而 `task_runs` 同时承受高频写（每个子任务状态变更）。把阶段级聚合固化成 `stage_runs` 一行，轮询只读几行、不再扫 task 热表，避免"读放大打在写热点上"。
2. **阶段状态机有唯一落点**："阶段完成 → 推进下一阶段""阶段失败 → 整阶段跳过/重试"这类**门控决策**目前需实时聚合全部子任务来判定。固化 `stage_runs.status` 后，门控逻辑与 runner DAG 推进只读一行，避免重复计算与"计算值 ≠ 存储值"的漂移。
3. **天然服务阶段级 UI 与操作**：console §7.6 顶部阶段卡要 X/Y 与阶段级起止时间；未来"暂停/恢复/重跑某一阶段"需一个阶段级实体来挂载。当前 `StageName` 只是字符串，没有实体身份，无法挂状态/操作。
4. **索引友好**：`stage_runs(pipeline_run_id, sequence)` 是极小顺序读（每运行仅数行），而 `task_runs` 聚合是范围扫 + group。运行规模越大，差距越显著。

**反方（不该建 / 暂缓）—— 站在「单一真相源 + 不做 YAGNI」立场**
1. **派生态永远正确，存储态会漂移**：阶段状态是子任务的纯函数。另存一份就要在每次子任务变更时同步更新第二个写入路径；任何同步 bug 都会让 `stage_runs` 陈旧而 `task_runs` 为真——"两个真相源"是经典数据完整性陷阱。
2. **尚未测到需要它的规模**：诉求是"高频查询"，但还没人测量过。YAGNI：真实并发下带复合索引 `(pipeline_run_id, stage, phase)` 的 derive-on-read 足够快。建冗余表是 premature optimization。
3. **写放大 + 热行争用**：方案 B 让每次 `task_runs` 相位变更都连带 upsert 父阶段行（重算或增计数）。并行阶段里大量子任务"同时"完成会**全部争用同一 `stage_runs` 行**，引入行级锁争用——可能比它要替代的读聚合更糟（热行问题）。
4. **runner 集群内已有阶段态**：推送模型下，runner 的 `PipelineRun`/`TaskRun` CRD 本就持有权威阶段 DAG 态。实时进展完全可由 hub 内存进度缓存（或 CRD）而非新 DB 表提供。热实时态放 DB 表是选错了层。
5. **更简单的正确路径**：保留 `task_runs` 为唯一真相源，优化读路径即可：(a) 复合覆盖索引；(b) `stage-progress` 由 hub 后端算一次（非客户端聚合）；(c) 必要时服务端对"上次算出的阶段 rollup"做带失效的 memoize。`stage_runs` 相对"良好索引的派生计算"收益有限。

**钢人结论（已确认：不建 `stage_runs`，用户决策）**
- **MVP 采用方案 A**：后端在 `Progress`/`stage-progress` 响应里**顺手算好阶段 rollup** 一起下发（一次查询、后端聚合、前端零计算）。
- **未来若规模迫使必须引入（当前决策为不建），触发条件如下**：① 实测 progress 查询 p95 延迟在真实并发下超预算；或 ② 出现"阶段级操作"需求（暂停/恢复/重跑某一阶段）需要阶段实体身份。届时 `stage_runs` **只能作为派生缓存**——由 `ApplyStatus` 同一事务/路径、从 `task_runs` **重算**（而非增计数）写入，杜绝双真相源漂移。
- 阶段进展 API：`GET /runs/:id/stage-progress`（见 §6.5）✅ **已落地（2026-09-23）** —— `PipelineRunHandler.StageProgress`（`cmd/hub/main.go` `scoped.GET("/runs/:id/stage-progress")`）在读取时聚合阶段 rollup（`name/sequence/executionMode/status/done/total`），呼应本节的「后端算一次、前端零计算」；`GET /runs/:id/progress` 仍保留为高频轮询端点（返回 `phase + per-task`）。⚠️ 当初「待实现」的陈述已过时。

### 6.4 DB 表设计变更（本次新增/推荐）

**① `pipeline_stages` 加 `execution_mode`**（实现阶段内串行/并行；**已确认方向为放 Stage 级**）✅ **已落地（2026-09-22）**：`PipelineStage` 已含该字段，迁移见 `migrations/0010`。✅ **`Serial` 的调度行为已落地（2026-09-23，backlog C-06 闭口）**：hub `buildSpec` 为 serial 阶段内任务按模板顺序派生「紧邻前驱」`DependsOn` 链（与跨阶段推导叠加；调用方手写 `DependsOn` 完全优先）；parallel 阶段不派生阶段内依赖，语义不变。
```sql
ALTER TABLE pipeline_stages ADD COLUMN execution_mode varchar(16) NOT NULL DEFAULT 'parallel';  -- 取值统一**小写**（以面向客户端的 API 契约为准）；实际落地见 migrations/0010
-- 枚举: 'Parallel' | 'Serial'
```
- ✅ **已实现（2026-09-23，backlog C-06 闭口）**：`Serial` 时 hub `buildSpec` 在同阶段任务间按模板顺序推导「紧邻前驱」`DependsOn` 链（与跨阶段推导叠加；调用方手写 `DependsOn` 完全优先）；parallel 阶段不派生阶段内依赖，语义不变。runner 无新字段，纯消费 DAG（CRD 类型无需改）。`pipeline_run_serial_test.go` / `stage_execution_mode_test.go` 钉住。
- store 层 `ListByPipelineID` 已按 `sequence` 返回；UI 并行/串行开关写入此列后由 `buildSpec` 消费 ✅ **已接线**。

**②（确认不建）`stage_runs` 聚合表** —— 见 §6.3 双向钢人论证，结论：**确认不建（用户决策）**，derive-on-read 为终态方案；DDL 仅留作未来参考（若触发条件出现再评估）。
```sql
CREATE TABLE stage_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pipeline_run_id uuid NOT NULL REFERENCES pipeline_runs(id),
  stage_name varchar(128) NOT NULL,
  sequence int NOT NULL,
  status varchar(32) NOT NULL DEFAULT 'Pending',
  started_at timestamptz,
  completed_at timestamptz,
  UNIQUE (pipeline_run_id, stage_name)
);
```

**③ 命令执行（已落地，记录于此）**：`Build`/`Release`（非金丝雀）→ 目标 namespace 的 K8s Job（init 容器 git checkout + 构件 fetch，主容器跑 `command`/`sh {ScriptPath}`）；`Release`+`RolloutSpec` → `Rollout` CR 渐进发布；`Approval` → 不建 Job、挂起等 hub 决策。详见 runner §4.2/§4.3。

### 6.5 进展相关 API（落 hub `internal/run/handler`）

| 方法 & 路径 | 返回 | 说明 |
| --- | --- | --- |
| `GET /runs/:id/progress` | `{ run: PipelineRun, tasks: TaskRun[] }` | 现状；高频轮询主入口 |
| `GET /runs/:id/stage-progress` | `{ run, stages: [{name, sequence, executionMode, status, done, total}] }` | ✅ **已落地（2026-09-23）**（derive-on-read 实现）；后端按 `StageName` 聚合，供 console §7.6 顶部阶段卡；定义漂移（快照名不在定义中）以合成行追加（`sequence=0`） |

### 6.6 运行终态操作：取消与单任务重跑（2026-09-24 落地，实施裁定归档）

> 原载于已清理的计划文档 §18，此处为唯一权威落点。两条裁定的共同背景：**reconciler 是 pipeline_runs/task_runs 相位的唯一 status writer**——任何绕过 reconciler 的直写都会被陈旧副本覆回。

**取消运行中流水线**（`POST /runs/:id/cancel`，hub `CancelRun` 终态 409 `ERR.09409001`）：
- **协议**：新增 `cancel_pipeline_run` 消息（hub→runner）+ `CancelPipelineRunPayload`；runner `dispatch.CancelHandler` 收到后**只打注解** `sdp.io/cancel-requested`，由 `PipelineRunReconciler.applyCancelIfRequested` 落 `Cancelled` 相位并清在途 TaskRun。
- **核心裁定：取消必须走注解而非 handler 直写 status**——handler 直写会被 reconciler 的陈旧副本覆回 `Running`；注解让取消进入 reconciler 的事件流，与唯一 status writer 会合。

**单任务重跑**（`POST /runs/:id/tasks/:name/rerun`）：
- Runner 侧 `RerunHandler` 按 pipeline-run/task 标签定位 TaskRun，清终态并删底层 Job/Rollout 重建，下游 DAG 自动重算。
- **核心裁定：重跑须把 `Failed` 的 run 拉回 `Running`**——reconciler 对终态相位短路，只复位 TaskRun 会静默无效；`Cancelled` **不复活**（用户显式取消的语义优先）。

---

## 7. 授权模型（权限管控 G7；目标态 = 多 org；P1 建表 / P2 审批 / P3 Enforcement 均已落地；**平台级 HTTP 端点 ✅ 已落地（2026-09-22，C-10）**）

> ✅ **当前状态（2026-09-22 更新）**：本节 §7 表 + Enforcement 中间件已落地，**平台级 HTTP 端点也已注册**（`internal/permission/handler/platform_role.go` / `platform_binding.go`；`main.go` 已接线）—— C-10 关闭，平台管理员绑定现在可经 API 配置。两张绑定表同批补上 **`expires_at`**（`migrations/0011`），且 `ListMatching` **排除过期授权** —— §7.4 的「到期回收」不再只是文档承诺（过期行保留供审计，由回收作业另行清理）。仍未做：platform 级路由的**权限守卫**（随 `ACCOUNT-PERMISSION-MODEL.md` §11 步骤 4「中间件重排」收口）、console 侧权限管理 UI。

> 双向钢人论证结论（见 [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) / 对话记录）：Keycloak 与 k8s RBAC 均**退到边界**——KC 只做身份+组，k8s RBAC 只管 runner 集群操作；承载"用户对组件能做什么 + 谁能审批"的是 **hub 内的两层 RBAC + 审批表**。这同时满足：① 组件级权限以"管理员/组映射为主"（无运行时自助需求 → 不引入 Keycloak UMA）；② 默认审批人 = 组件 owner/管理员（所有权在 app，见 §7.4）。

> ⚠️ **实现现状（V1，已在代码）≠ 本章设计（目标态，迁移中）**——V1 与 §7 表并存是**有意为之的增量迁移**，不是两套对立设计：
>
> | 维度 | V1（已实现，M1） | 本章设计（目标态，M2，**多 org**） | 迁移相位 |
> | --- | --- | --- | --- |
> | 角色表 | 单张 `roles`（`permissions jsonb`，`org_id` 归属） | `platform_roles` + `component_roles`（`actions[]` 枚举，**均带 `org_id`**） | P1 建表；P3a §7 action 权威 |
> | 绑定主体 | `component_role_bindings.user_id uuid NOT NULL`（无组） | `subject_type[user\|group] + subject_id` + **`org_id`**（冗余隔离） | P1 加列+回填；P3a/c Enforcement+console 切换；**D3（`0015`）已删 `user_id`/`role_id`** |
> | 平台级 | **无** | `platform_roles` / `platform_role_bindings` | P1 建表；P3a Enforcement 就绪（console UI 待落地） |
> | 组件所有权 | **无** `owner_sub`/`owner_group` 列 | `components.owner_sub`（text，D3 前为 `owner_user uuid`）/`owner_group` | P1 加列；P3b owner 自动绑 component-admin；D3（`0015`）把 `owner_user` 回填成 `owner_sub` = token `sub` |
> | 审批表 | `approvals`（`task_run_id, approver, decision, comment`） | `pipeline_approvals`（`org_id, run_id, task_run_id, component_id, status, requested_by, approver, ...`） | P1 建表；P2 已切换 Enforcement |
> | **org 维度** | `roles.org_id` 有；其余表无 | **所有 RBAC 表均带 `org_id`**（修复 V1 缺 org 的倒退） | P1 已落地 |
>
> **多 org 决策（2026-09-14 裁定）**：平台按多租户推进，故 §7 全部 RBAC 表带 `org_id`；`component_role_bindings.org_id` / `pipeline_approvals.org_id` 由「组件 → 服务 → 服务树 → org」解析后冗余存储，使鉴权查询可按 org 隔离而无需 join。
>
> 代码锚点：`internal/permission/models/{role.go,binding.go,platform_role.go,platform_role_binding.go,component_role.go}`、`internal/run/models/{approval.go,pipeline_approval.go}`、`internal/component/models/component.go`、`internal/db/db.go`（已 AutoMigrate 上述全部表）；演进回填见 `migrations/0004_rbac_multiorg.sql` + `migrations/0005_rbac_p3.sql`，预置角色见 `cmd/hub/conf/09_rbac_multiorg.sql`（含 `component-admin`）。
>
> **实现相位状态（截至 2026-09-14）**：
> - **P1（已落地）**：§7 全部表建表 + 列 + `org_id` 冗余 + 预置角色（含 `component-admin`）。
> - **P2（已落地，审批子系统切换 §7）**：`pipeline_approvals` 取代 V1 `approvals`——run 触发时为每个 Approval 子任务 seed `PipelineApproval`（org/component/run 作用域，`requested_by`=触发人）；`Approve` 改为状态机 + **防自审**（`requested_by == approver` 直接拒绝）+ 审计字段；runner 经 `ApproveTaskPayload` 解除 DAG 挂起。见 `internal/run/{repository/approval.go,service/pipeline_run.go}`、`internal/run/models/pipeline_approval.go`。
> - **P3（已落地，Enforcement 切 §7 + console）**：
>   - **P3a**：§7 action 枚举成为权威（`internal/permission/models/role.go`），`BindingService` 重写——`ResolveComponentActions` / `HasPermission` / `HasPlatformPermission` 合并 §7 绑定 + owner override + V1 回退；中间件 `rbac.go` 路由判定改用 §7 action（`ActionPipelineTrigger` / `ActionComponentRead` / `ActionApprovalApprove`）；Keycloak `groups` claim 经 `UserContext` 注入（`CurrentGroups`）。
>   - **P3b**：组件创建自动把 owner 绑 `component-admin`（非致命失败），`Create` 写入 `owner_sub`（= 当前请求的 token `sub`，§5.3）；handler 手写路由、owner 未填时从会话补。见 `internal/component/{service,handler}/component.go`、`internal/permission/handler/binding.go`。
>   - **P3c**：console `permissions.ts` 切换 §7 `ComponentRoleBinding`（`subjectType` / `subjectId` / `componentRoleId`）+ 新增 hub `GET /component-roles`（`internal/permission/handler/component_role.go`）；`PermissionsTab.vue` 支持 user/group 主体、§7 角色选择器、自审拦截提示。V1 旧行（`userId` / `roleId`）回显兼容。
> - **遗留（非阻塞）**：V1 `roles` / `approvals` 表与代码路径保留为迁移窗口兼容，**经双向钢人裁定保留不删**（全仓仍有活引用 + DROP 不可逆，真删需用户显式确认）；Keycloak 组目录未由 hub 暴露（console 组名手填，待 `/groups` 接口）。**平台级权限 UI 已落地**（console `PlatformAdminView`，C-10 / T-U7）。

### 7.1 分层授权模型（总览）

| 层 | 负责什么 | 落点 | 理由（钢人论证） |
| --- | --- | --- | --- |
| 0 身份 | 你是谁、属于哪个组 | **Keycloak / OIDC（已用）** | 仅认证 + 返回 `sub`/`groups`，不当授权引擎 |
| 1 平台级 | console 各页面可见/可操作 | **Keycloak 组 → hub 解析 `platform_role`**（§7.2） | 页面权限粗粒度、角色少，组映射最省事 |
| 2 组件级 | 某组件的 CRUD / 触发流水线 | **hub DB：`ComponentRole` + `ComponentRoleBinding`**（§7.3，参考 ArgoCD Project-scoped RBAC） | 所有权在 app、无运行时自助 → UMA 卖点用不上；app 内一张绑定表最一致 |
| 3 审批 | 选谁审 / 默认谁审 / 通过拒绝 | **hub 内审批子系统（表 + 状态机，§7.4）** | 审批是工作流+审计，KC/k8s 均无；默认审批人=owner/admin 是 app 域数据 |
| 4 部署边界 | runner 能碰哪些集群/namespace | **k8s RBAC（已用）** | hub 为每个"组件×环境"签发 `RoleBinding`，runner SA 只碰该组件命名空间 |

### 7.2 平台级角色（platform-level）

- **`platform_roles`**：`(id, name, description, actions[])`，`actions` 为平台级 action 枚举，如 `page:overview:view`、`page:servicetree:view`、`page:settings:view`、`org:manage`、`user:manage`、`component:create`（全局建组件）、`environment:create`。
- **`platform_role_bindings`**：`(id, subject_type[user|group], subject_id, platform_role_id)`。`subject_type=group` 由 Keycloak `groups` claim 登录时自动解析（hub 把 KC group → platform_role 映射灌入会话/ token）。
- **映射机制**：hub 配置 `keycloak_group → platform_role`（如 `sdp-admin` → 全部 actions；`sdp-viewer` → 仅 `*:view`）。Enforcement 见 §7.5。
- **颗粒度**：平台级只到"页面/全局动作"粒度，不细分单个组件。

### 7.3 组件级角色（component-level；参考 ArgoCD Project-scoped RBAC）

> 直接对应 ArgoCD 两层模型：`ArgoCDRole`（全局角色定义）+ `ArgoCDProjectRoleBinding`（绑定到具体 AppProject）。我们换成 `ComponentRole`（全局定义）+ `ComponentRoleBinding`（绑定到具体 Component）。

- **`component_roles`**：`(id, org_id, name, description, actions[])`，`org_id` 为 NULL 表示内置角色（`component-viewer`/`component-editor`/`component-approver`/`component-admin`），非 NULL 表示某 org 自定义角色。action 枚举（Casbin 风格 `resource:action`）：
  - `component:read` / `component:update` / `component:delete`
  - `pipeline:read` / `pipeline:create` / `pipeline:update` / `pipeline:delete` / `pipeline:trigger`
  - `config:read` / `config:update`
  - `artifact:read` / `artifact:download` / `artifact:delete`
  - `approval:approve`（仅 approver 持有）
  - 预置四种角色（built-in，`org_id IS NULL`，见 `cmd/hub/conf/09_rbac_multiorg.sql`）：`component-viewer`(read 类)、`component-editor`(read+update+trigger+create/delete pipeline+config)、`component-approver`(+`approval:approve`)、`component-admin`(+ **全部组件动作**，含 `approval:approve` 与 `component:manage`；创建组件的 owner 自动绑定此角色，见 §7.4)。
- **`component_role_bindings`**：`(id, component_id, subject_type[user|group], subject_id, component_role_id)`。同一组件可多绑定；`subject_type=group` 复用 KC 组。
- **默认绑定（满足"默认审批人=组件 owner/admin"）**：创建组件时（P3b）**自动把组件 owner（user 或 group）绑 `component-admin`**——owner 即拥有全部组件动作（含 `approval:approve` 与 `component:manage`），无需再显式授予。该自动绑定非致命（失败不影响组件创建，仅记日志告警）。owner 来源见 §7.4 所有权。
- **增删改查颗粒度**：逐 action 授权，支持"能看不能改""能触发不能删"等组合；前端权限页见 [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md)。

### 7.4 审批子系统（pipeline approvals）

> 开源参考：GitHub Environments（required reviewers + prevent self-review + wait timer）、GitLab Protected Environments（manual job + required approvers）、Spinnaker Manual Judgment（审批=独立 stage）、Backstage Permission Framework（ownership 驱动默认权限）。

- **`pipeline_approvals`**：`(id, run_id, task_run_id, component_id, status[Pending|Approved|Rejected|Cancelled], requested_by, approver, decision_comment, created_at, decided_at)`。`task_run_id` 关联处于 `WaitingApproval` 的 Approval 子任务（§6.2）。
- **选谁审批**：编排流水线时可在 Approval 任务上指定 `approver`（用户/组）；**未指定则默认 = 组件 owner / 组件 admin 组**（取自 §7.3 默认绑定 / 组件所有权）。
- **默认审批人来源**：组件所有权模型（app 数据）——组件表 `owner_sub` / `owner_group`；创建组件时写入，并同步**把 owner 自动绑 `component-admin`**（见 §7.3），因此 owner 天然持有 `approval:approve`，即默认审批人。
- **通过 / 拒绝语义**：
  - `Approve`：写 `status=Approved` + `decided_at`，经 `approve_task` 帧（见 runner §4.1）通知 runner 解除 Approval 挂起 → 流程继续。
  - `Reject`：写 `status=Rejected`，整条 `PipelineRun` 标 `Failed`（或按策略 `Cancelled`），终止后续阶段（§6.2 审批拒绝分支）。
  - **防自审（prevent self-review）**：若 `requested_by == approver`（或申请人在 approver 组内），强制要求另一名 approver 决策；UI 在 console §7.9 提示。
  - **审计**：`pipeline_approvals` 全量留痕（谁、何时、何种决策、意见），独立于运行记录，供合规查询。
- **状态机**：`Pending → {Approved → 继续} | {Rejected → 运行终止} | {Cancelled → 运行取消}`。

### 7.5 Enforcement 点（鉴权中间件）

hub 在 API 网关/中间件层统一鉴权：

1. 解析请求 JWT（Keycloak 签发）→ 取 `sub` + `groups`。
2. `groups` + `subject=user` → 查 `platform_role_bindings` + `component_role_bindings` → 展开该用户**有效 action 集**（含组继承）。
3. 按路由判定所需 action（如 `POST /components/:id/pipelines` → `pipeline:create@component_id`），校验是否在有效 action 集内；否 → `403`。
4. Approval 类端点额外校验 `approval:approve` 且申请人 ≠ 审批人（防自审）。

- **已实现（P3a）**：上述校验在 hub 路由/中间件层落地——`BindingService.HasPermission` 合并 §7 绑定 + owner override + V1 回退；路由判定改用 §7 action（`ActionPipelineTrigger` / `ActionComponentRead` / `ActionApprovalApprove`）；Keycloak `groups` claim 经 `UserContext` 注入并参与绑定解析（见 §7 实现相位状态 P3a）。

### 7.6 开源参考映射

| 子问题 | 参考 | 借鉴点 |
| --- | --- | --- |
| 平台级 / 组件级 两层颗粒度 | **ArgoCD** Global vs Project-scoped RBAC（`ArgoCDRole`/`ArgoCDRoleBinding`） | 全局角色定义 + 组件级绑定两张表 |
| 组件级细粒度 + 组映射 | **Keycloak** group/role（仅作身份+组，不做 UMA 资源授权） | KC 组 → hub 角色映射 |
| 默认审批人 = owner | **Backstage** ownership 驱动权限 | 所有权是 app 数据，驱动默认审批 |
| 选谁审 / 通过拒绝 / 防自审 | **GitHub Environments / GitLab Protected Environments / Spinnaker Manual Judgment** | 审批=独立门禁节点；required reviewers + 防自审 + wait timer |
| 动态策略（可选） | **OPA / Casbin** | 未来"仅工作时间可发布生产"等用策略引擎，**不在本期**（D4 判定 = 「延后 + 登记」；触发条件与引入时的硬约束见 [hub/STORY-BACKLOG.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md) **B-19**，边界见 [hub/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ACCOUNT-PERMISSION-MODEL.md) §5.2） |

### 7.7 表结构（DDL，与 AutoMigrate 同步已实现）

```sql
-- 平台级
CREATE TABLE platform_roles (
  id UUID PRIMARY KEY, org_id UUID,            -- NULL = 全局内置角色
  name TEXT NOT NULL, description TEXT,
  actions TEXT[] NOT NULL DEFAULT '{}', is_system BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE platform_role_bindings (
  id UUID PRIMARY KEY, org_id UUID,            -- 冗余，按 org 隔离
  subject_type TEXT NOT NULL CHECK (subject_type IN ('user','group')),
  subject_id TEXT NOT NULL, platform_role_id UUID NOT NULL REFERENCES platform_roles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (org_id, subject_type, subject_id, platform_role_id)
);

-- 组件级
CREATE TABLE component_roles (
  id UUID PRIMARY KEY, org_id UUID,            -- NULL = 内置角色
  name TEXT NOT NULL, description TEXT,
  actions TEXT[] NOT NULL DEFAULT '{}', is_system BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE component_role_bindings (
  id UUID PRIMARY KEY, component_id UUID NOT NULL REFERENCES components(id),
  org_id UUID,                                -- 冗余，由组件→服务→服务树→org 解析
  -- §7 主体模型（P3）：subject_type/subject_id + component_role_id
  subject_type TEXT CHECK (subject_type IN ('user','group')),
  subject_id TEXT, component_role_id UUID REFERENCES component_roles(id),
  -- D3（2026-09-23，迁移 0015）已删除 V1 兼容列 user_id / role_id，
  -- 以及它们指向的本地 `users` 表：hub 不存用户身份（§2.2），主体只有 `sub` 一条路。
  granted_by TEXT, granted_at TIMESTAMPTZ NOT NULL DEFAULT now(), expires_at TIMESTAMPTZ,
  UNIQUE (component_id, org_id, subject_type, subject_id, component_role_id)
);

-- 审批（§7.4）
CREATE TABLE pipeline_approvals (
  id UUID PRIMARY KEY, org_id UUID NOT NULL,   -- 按 org 隔离
  run_id UUID NOT NULL REFERENCES pipeline_runs(id),
  task_run_id UUID REFERENCES task_runs(id),
  component_id UUID NOT NULL REFERENCES components(id),
  status TEXT NOT NULL CHECK (status IN ('Pending','Approved','Rejected','Cancelled')),
  requested_by TEXT NOT NULL, approver TEXT, decision_comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), decided_at TIMESTAMPTZ
);
```

---

## 8. 环境分组（`environment_groups`，新增；2026-09-16 用户拍板"需要落库"）

> 背景：console 环境页 / 配置页左侧的"分组（类生产 / 生产）"此前只存在于原型内存（`ENV[comp].groups`），hub 无落库位置。用户于 2026-09-16 明确要求落库。本节为设计（DDL 尚未落地）。

### 8.1 方案选择
| 方案 | 评估 |
| --- | --- |
| A. 给 `environments` 加 `group_name varchar` | ✗ 无法表达**空分组**（原型允许先建组、后建环境）；改名需批量 UPDATE；组内顺序无处表达 |
| B. 新表 `environment_groups` + `environments.group_id`（可空） | ✓ 支持空分组、可排序、改名不动环境、可稳定引用 |

**采纳 B。**

### 8.2 DDL（建议 `migrations/0003_environment_groups.sql`）
```sql
create table environment_groups (
    id            uuid primary key default gen_random_uuid(),
    component_id  uuid not null references components(id) on delete cascade,
    key           varchar(64)  not null,   -- 稳定标识，如 prod-like / prod
    name          varchar(128) not null,   -- 展示名，如「类生产」「生产」
    display_order integer      not null default 0,
    created_at    timestamptz  not null default now(),
    updated_at    timestamptz  not null default now(),
    unique (component_id, key)
);
create index idx_env_groups_component on environment_groups(component_id);

alter table environments add column group_id uuid references environment_groups(id);
create index idx_environments_group on environments(group_id);
```

### 8.3 关系与不变式
```
Component ──1:N──▶ environment_groups     (component_id NOT NULL)
Component ──1:N──▶ environments           (component_id NOT NULL)
environment_groups ──1:N──▶ environments  (environments.group_id，可空)
```
- **锚定 Component**（与 §3 不变式一致）：分组是**组件内**概念，不跨组件。
- `environments.group_id` **可空** → 兼容既有数据（0001 建的环境无分组），并表达"未分组"这一合法状态。
- **不加 `(component_id, group_id)` 复合外键**：与 `component_configs.environment_id` 的既有缺口同构（见 DELETE-CONTRACT §6.2 机制②）。建议**统一靠服务层校验**，避免 DB 层约束与软删语义打架。

### 8.4 删除语义（与 DELETE-CONTRACT §6 同源）
| 操作 | 行为 | 理由 |
| --- | --- | --- |
| 删分组（组内**有**环境） | **`409 + {reasons}`** 拒绝，列出未清理环境 | 分组是用户显式建立的组织结构；静默降级为"未分组"会丢失归类信息（语义清晰优先，非残留考虑） |
| 删分组（组内**空**） | 允许（硬删；本表与 `environments` 同为无 `deleted_at` 表） | 空壳无引用 |
| 删环境 | 允许，但**删除前须告知**该环境上的配置覆盖行数 | `component_configs.environment_id` 现为 `ON DELETE CASCADE`，**会静默删**（见 DELETE-CONTRACT §6.3 ⑧） |
| 删组件 | 分组应随之消失 | ⚠️ 组件是**软删**，`ON DELETE CASCADE` **不触发**（见 DELETE-CONTRACT §6.2 机制①）→ 须服务层显式级联软删 |

### 8.5 与 `env_type` 的区别（勿混淆）
| | `environments.env_type` | `environment_groups` |
| --- | --- | --- |
| 语义 | **平台级策略标记**（`test` / `production`） | **用户自定义归类**（"类生产""预发"） |
| 谁定义 | 平台（0002 追加，`check in ('test','production')`） | 用户 |
| 影响执行行为 | 是（如生产环境强审批） | 否（纯组织语义） |

两者**正交**。原型里的"类生产 / 生产"是**分组**，不要与 `env_type` 合并；UI 文案应避免同名造成误读。

### 8.6 折叠状态不落库
分组的折叠/展开（原型 `S.collapsedGroups`）是**用户级 UI 偏好**，非组件级数据 → 不进入 `environment_groups`。落点：前端 localStorage（或未来的 per-user preference 表），避免组件数据被个人偏好污染。

### 8.7 落地 gate
- 迁移 `0003` 在既有库上幂等（仅新表 + 可空列，无回填需求）。
- `GET /components/:id/environments` 响应带 `groupId`；或新增 `GET /components/:id/environment-groups`。
- 单测：空分组可删 / 非空分组 `409` / 删环境前可统计到配置覆盖行数。

### 8.8 落地决策（2026-09-16 用户拍板）

> 与 `DELETE-CONTRACT.md` §6.5 / §6.6 同源（含双向钢人论证）。本节只记录**对本章的影响**。

| 决策 | 结论 | 对本章的影响 |
| --- | --- | --- |
| 删环境 / 删组件时，**集群侧**已部署资源是否回收 | **不回收**（**平台侧与目标侧生命周期解耦**：无论走哪条接入通道，删除平台记录都**不回收目标侧资源**，避免误伤生产） | §8.4「删环境」行**不再涉及集群侧**；删环境只处理**平台侧**（DB 行 + 审计） |
| 「残留」的定义 | **只指平台侧**遗留（DB 行 / 对象存储对象 / 配置与审计） | §8.4「删组件」行的"分组应随之消失"须**服务层显式级联**（组件软删，DB `ON DELETE CASCADE` 不触发）；集群侧不计入残留 |
| `component_config_history.environment_id` | **去 FK + 加 `environment_key` 快照列**（优于单纯 `ON DELETE SET NULL`） | §8.4「删环境」的"删除前须告知配置覆盖行数"**仍然成立**；同时消除"删环境随机 500"（现状：`component_configs` 是 cascade、`config_history` 是 `NO ACTION`，同一操作两种结果） |
| `pipeline_stages` / `pipeline_task_templates` | **补 `deleted_at`** + **封父存在性校验** + **修 `pipelines` 唯一约束** | 与本章无直接耦合，记录于 `DELETE-CONTRACT.md` §6.6-3（B-15）。**(a)(b)(c) 已于 2026-09-16 落地；(d) `deleted_at` + 活行唯一 + stage 级联软删已于 2026-09-22 落地**（见 §8.9） |
| Artifact 孤儿对象 | **先堵源头 → 后做对账（仅报告，不自动删）** | 同 `DELETE-CONTRACT.md` §6.6-4（B-16） |
| Artifact 保留期回收 | 过期行**先删对象、后删行**；对象删失败 ⇒ 行保留 + `cleanup_state='pending_deletion'`，下轮自动重试 | `artifact/service/gc.go` = `expires_at` 的**唯一读取点**（2026-09-23，`migrations/0016`） |
| Artifact 域内级联软删 | **仍未做** —— 删 org→service→component→pipeline 时的制品/对象处理 | `DELETE-CONTRACT.md` §6.4（B-16 最后一项） |

**未变（仍然有效）**：
- §8.2 的 DDL 方案（新表 `environment_groups` + `environments.group_id` **可空**）；
- §8.4 的"组内有环境则 `409 + {reasons}` 拒绝 / 组内空则允许硬删"；
- §8.5 的 `env_type`（平台策略标记）与分组**正交，不合并**；
- §8.6 的折叠状态**不落库**（用户级 UI 偏好）。

**关联 backlog**：`STORY-BACKLOG.md` B-13（环境分组落库）、B-14（config_history 快照列）、B-15（stages/templates 标记与入口校验）、B-16（artifacts 治理）。

### 8.9 落地记录（2026-09-22）

本章相关的 B-13 / B-14 / B-15 项在本轮全部落地：

| 项 | 落地内容 | 代码 / 迁移锚点 |
| --- | --- | --- |
| 分组落库（§8.2 / B-13） | 表 `environment_groups` + `environments.group_id`（可空）由启动时 GORM `AutoMigrate` 建出。**未走 §8.2 建议的 `0003` 迁移号** —— `0003` 已是 Keycloak 认证；本机无"从 0001 建库"的存量，故只靠 AutoMigrate，不另写迁移 | `internal/environmentgroup/{models,repository,service,handler}`、`internal/environment/models/environment.go` |
| 删分组语义（§8.4 第 1/2 行） | ✅ `409 + {reasons}`（reasons 带组内环境条数）；空组硬删。**修正了一处与契约不符**：原实现返回 `400` 且不带 `reasons` | `internal/environmentgroup/service/environment_group.go`；单测 `delete_test.go` |
| 删环境告知（§8.4 第 3 行） | ✅ 删前统计该环境的 `component_configs` 覆盖行数并写审计告警，**不拒绝**（§6.4 #8 判定为"提示、不拒绝"） | `internal/environment/service/environment.go`；`internal/component/repository/config.go` 的 `CountByEnvironment` |
| 配置历史去 FK（第 8.8 决策 2 / B-14） | ✅ `component_config_history` 摘 `environment_id` FK + 加 `environment_key` 快照列（写入时冗余当时 key，环境删掉后历史仍可读） | `migrations/0008_config_history_env_key.sql`、`internal/component/{models,service}/config.go` |
| stages/templates 补 `deleted_at`（第 8.8 决策 3 / B-15） | ✅ 两模型 `BaseNoSoftDelete` → `common.Base`；旧唯一约束改 partial unique index（`where deleted_at is null`）；`StageService.Delete` 服务层级联软删模板 | `migrations/0009_stage_template_soft_delete.sql`、`internal/pipeline/models/{stage,task_template}.go`、`internal/pipeline/service/stage.go` |
| §8.4 第 4 行"删组件 → 分组应随之消失" | ❌ **仍未做**（组件软删不触发 DB cascade，需服务层显式级联 + 跨 repo 事务设计），登记于 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §3.3 | — |

**§8.7 gate 对照**
- ✅ 单测：空分组可删 / 非空分组 `409 + {reasons}`（`internal/environmentgroup/service/delete_test.go`）。
- ✅ 端点：`GET /components/:id/environment-groups` 已注册（`EnvironmentGroupHandler.RegisterRoutes`）。
- ⚠️ **未覆盖**："删环境前统计到配置覆盖行数"目前**没有单测** —— 该行为由 `EnvironmentService.Delete` 内的一次计数 + 审计日志承担，要构造 `component_configs` 行需要真实 DB（本轮 gate 为 build/vet/test，不含 PG）。属已知缺口，未假装通过。
- **迁移 `0003` 幂等性**：不适用（未生成该迁移文件，见上表第 1 行）。

**未跑**：真实库上的 `migrations/0008` / `0009`（本地无 Postgres / Docker）。前置检查见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §3.4。

---

## 9. 接入目标注册表与部署拓扑（含「单机版」；2026-09-21 裁定）

> **起因**：console §7.12 补环境对接（`kubeconfig` / `ssh`）时暴露出「集群」一词被三种语境混用。本节钉死 `targets` 的语义、它与 `environments` 的关系、以及"平台自身所在的集群"这一特殊情形。

### 9.0 三层边界与术语消歧速查（2026-09-23 自 docs/README §5.4/§5.5 迁入，本节为唯一权威落点）

**三层边界**：「集群 / 目标 / 环境 / 组件」在多种语境下被混用——先钉死三层的边界与归属：

| 层 | 内容 | 归属 | 权威落点 |
| --- | --- | --- | --- |
| ① 能力 | 平台对目标做：构建 / 测试 / 发布 | 产品语义 | console §7 · hub API-REFERENCE · runner STORY |
| ② 接入 | 平台怎么够到目标：`agent` 回连 / `kubeconfig` / `ssh` | 产品语义 | 本节 §9.5 / §9.7 · console §7.12 |
| ③ 自身 | 平台自己（**hub / console + 数据库；不含 runner**）装在哪、谁装、怎么升级 | **运维实践，不进产品模型** | 本文件 §9.11（P6 原文已迁入） |

**已裁定事实**（一行结论；完整论证见 §9.1–§9.10 与 P6）：

- **③ 的起点是手工 helm**，Gen0 基线**长期保留** → [E2E-VERIFY-PLAN.md P6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)。
- **runner 不属「平台自身」**：接入侧代理组件，组件身份与部署形态无关（勿与安装批次混淆）→ §9.3 / §9.4。
- **② 主路径 = `agent` 回连**：runner 出站回连 hub，`targets` 故意不存 kubeconfig → §9.1。
- **直连通道（`kubeconfig` / `ssh`）已立项**：由 hub 侧发起、凭据归 hub，覆盖非容器目标 → §9.5 / §9.7。
- **单机版 = 目标恰好是平台自身所在集群**（部署位置巧合，非组件身份变化；勿为平台自身另建集群行 / 组件 / 环境）→ §9.3。
- **平台自身不进服务树 / 组件 / 环境模型**（避免自指契约漏洞）→ §9.4。
- **平台自身的部署与升级留在平台之外**（构建可吃狗粮；`Release` 不发布平台自身；六条理由全文）→ P6。
- **发布动作 = 推三组件镜像 + 版本矩阵 CM**（唯一版本事实源，人工维护）→ §9.10。

**术语消歧**（同一词的不同含义，引用前先确认；每个词的权威定义仍在其所属章节）：

| 词 | 含义 A | 含义 B | 消歧做法 |
| --- | --- | --- | --- |
| **自举** | ⛔ **已停用**：曾指"平台发布平台自己"（随方案一并撤销） | ✅ **读时播种默认数据**（seed-on-read） | 含义 A 一律写「平台发布平台自己（已撤销）」；含义 B 写「seed-on-read」。**不再单用「自举」二字** |
| **集群** | ⛔ **已改称「目标（Target）」**：`clusters` / `Cluster` 作为领域对象名已废弃 | ③ **平台底座所在**的 K8s 集群；K8s 技术词（`ClusterRole` / `ClusterIP` 等）仍用「集群」 | 指"被纳管的对象"一律写「**目标（Target）**」 |
| **环境** | ✅ 领域对象：`environments`（挂组件下，绑 `target_id` + `namespace`） | ⛔ 平台的运行环境（dev / staging / prod）——**不是领域对象** | 后者一律写「平台的运行环境（运维概念）」 |
| **组件** | ✅ 领域对象：`components`（叶子 = 服务组件，绑一个 git 仓库） | 平台自身的组件（**hub / console**，不进服务模型） | 后者一律写「**平台组件（hub / console）**」。**runner 例外**：接入侧代理组件，**不属平台自身** |
| **目标** | ✅ 被纳管对象 / `targets` 一行：`targetKind` = `k8s` **或** `host`（不预设类型），承载 `access`；console 菜单名 =「**接入管理**」 | ⛔ 平台的运行环境 | 必带 `targetKind`；非 K8s 目标一律写「**非容器目标（`host`）**」 |
| **通道（接入方式）** | ✅ `access`：平台**怎么够到**目标 —— `agent` / `kubeconfig` / `ssh` | ⛔「网络通道」等泛称 | 一律写 `access=<值>`，并**同时注明凭据归属**（`agent` → 目标侧；直连 → hub 侧） |

### 9.1 `targets` 是「目标侧」注册表，不是「平台自身」注册表

`targets` 一行 = **一个部署在被管集群里、出站回连 hub 的 Runner Agent**（`internal/target/models/target.go` 注释：*"a matching runner Agent connects back to the hub for each row here"*；DDL 见 `migrations/0001_init_schema.sql` §5）。

| 列 | 类型 | 说明 |
| --- | --- | --- |
| `name` | varchar(128) unique | 目标名。Runner 连网关注自报（`X-Target-Name` header），hub 据此 `GetByName` 定位；查不到 → `404 unknown target` |
| `vendor` / `region` | varchar | `aliyun` / `tencent` / `aws` / `self-hosted` …；**多厂商、多 region 是设计前提** |
| `status` | varchar(32) | `online` / `offline`，由网关连接 / 断开触发 `Heartbeat` 翻转 |
| `agent_version` / `last_heartbeat_at` | | Runner 版本与心跳 |
| （无其他列） | | **本表刻意不含任何凭据列**：无 kubeconfig、无 kube-apiserver 地址、无 SSH |

**为什么没有凭据列——执行方向决定的**：在 `agent` 通道下，平台**从不入站访问目标**（⚠️ **直连通道 `kubeconfig` / `ssh` 例外** —— hub 侧发起连接并持有目标凭据，见 §9.5）。

- **下发**：hub 经 Runner 的**出站长连接**（WS）推 `ApplyPipelineRunPayload`（§6.1）；
- **回流**：状态 / 日志由 Runner 出站推回（`status_update` / `MessageLogChunk`），hub 落 `task_runs` 后 `GET /runs/:id/log` **只读 hub 自己持久化的日志分片**，不连集群；
- **制品**：落在 hub 自己的对象存储（`local` driver 的 HMAC 签名 URL，或 S3 / MinIO presigned URL），不经目标集群。

因此**唯一存在的凭据是反向的**：Runner 持 `GATEWAY_TOKEN`（bearer）连 hub 网关。⚠️ 两点须知道：

1. 该 token 是**全局共享**的（`internal/config/config.go`：*"shared secret Runners present as a Bearer token"*），**不是 per-target**；目标身份由 Runner **自报的 `name`** 决定（`internal/gateway/gateway.go`）。
2. 故"身份认证"在这一层**偏弱，不是安全性的来源**。现有安全性来自两处：① **平台无入站路径**（对目标零攻击面）；② **集群侧 k8s RBAC 最小权限**（[runner 实现 Story §4.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md)：hub 为每个"组件 × 环境"签发 `RoleBinding`，Runner SA 只碰该组件命名空间）。

### 9.2 关系与不变式

```
targets ──1:N──▶ environments   (environments.target_id，NOT NULL)
```

- `environments.target_id` 是 **NOT NULL FK**（0001 §6）→ **没有目标行就建不了环境**；"注册目标"是纳管目标的前置步骤，不是可选装饰。
- **目标删除**：本表 `BaseNoSoftDelete`（硬删）+ `references targets(id)` **无 `ON DELETE`** → 删被环境引用的目标会 **FK 报错（500）**，而不是优雅 `409`。这是 [DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DELETE-CONTRACT.md) §6 已登记的缺口（"硬删撞 NO CASCADE 外键 → 500"），**未修**。
- `targets` 与 `environments` **同属硬删表**（均无 `deleted_at`）→ 级联须服务层显式处理，不能指望 DB。

### 9.3 「单机版」：目标恰好是平台自身所在集群（**runner 身份不随之改变**）

平台**允许与环境部署在同一个集群**——console / hub / runner 装进同一 K8s 集群（如 [plans/E2E-VERIFY-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 的 P0 拓扑：kind `sdp-dev` + ns `sdp-workflow`），此时：

- Runner 对接的就是**本地集群**，流水线任务在本地集群内执行生效；
- `targets` 里那一行目标指向的集群**恰好也是平台自身所在集群**——这只是**部署位置**上的巧合。

> **不变式（2026-09-21 二次裁定）**：**runner 是独立的接入代理组件，其组件身份与部署形态无关。**
> 无论装在异集群还是与 hub 同集群，runner 都只是"被部署到目标侧、出站回连 hub 的 Agent"，**不属于「平台自身」**。
> ⛔ 此前"单机版下那一行**同时**承担「① 平台底座所在集群」与「② 被发布目标」两个角色"的表述**作废**——它把**部署位置**误当成了**组件身份**。
> **仍然成立、且必须坚持的是**：不要为"平台自身"另建集群行 / 另建组件 / 另建环境——那会造出两个指向同一集群的行。
> 凡文档 / 代码 / UI 出现「目标」或「集群」，仍须能回答：**这里说的是哪个角色（被发布目标 / 平台底座）？**

> **安装批次 ≠ 组件身份（2026-09-21 补记）**：Gen0 安装平台时，**console / hub / runner（+ 数据库）由同一份 helm 一次装齐**。因此平台自身集群那一行目标**天然是"已装 runner"**——接入管理里显示"已装"、动作是**升级**，**不存在"点一下装出第二个 runner"**。这只是**安装批次**一致，**不改变 runner 的组件身份**（§9.4）。

### 9.4 平台自身不进产品模型（**范围 = hub / console + 数据库，不含 runner**）

平台自身 = **hub / console（+ 其数据库）**，**不含 runner**——runner 是接入侧代理组件（§9.3、§9.9）。平台自身**不进服务树 / 组件 / 环境**模型：

- 它不是 `components` 锚定的资源，故不受 `DELETE /components/:id` 级联约束——避免"删掉平台自己的组件"这类自指契约漏洞；
- 它的部署与升级**留在平台之外**：各仓 `make package` / `pnpm image` 产出的镜像 + chart 交付包 → **外部 helm / CI** 发布。裁决与六条理由见 本文件 §9.11（P6 原文已迁入）（2026-09-23 起为唯一权威落点）。
- **runner 是例外，且不触红线**：runner 的安装 / 升级由 **hub 承担编排、console 只调 API**（§9.9），属"平台对目标做"（① 能力），**不是"平台升级自己"（③）**，故**不受 §5.4 自升级禁令约束**。平台自身的升级仍以 hub / console 的 helm 升级为准，走 §5.4 的"平台之外"通道。

### 9.5 与「接入方式」扩展的关系（**2026-09-21 已裁决**）

② 接入层**不止 `agent` 一条路**。目标类型分 `k8s` / `host`，通道分三条：

| 通道 `access` | 目标类型 | 发起方 | 凭据归属 | 今天是否存在 |
| --- | --- | --- | --- | --- |
| `agent` | `k8s` | 目标集群内 Runner **出站回连** | 目标侧（Runner 持 `GATEWAY_TOKEN`）；**hub 零凭据** | ✅ 已实现（§9.1） |
| `kubeconfig` | `k8s` | **hub 出站**直连 apiserver | **hub 侧** | ❌ hub 零 `client-go`、零出站代码 |
| `ssh` | `host` | **hub 出站**直连主机 | **hub 侧** | ❌ 全仓零 SSH 代码 |

> **裁决要点**（2026-09-21 用户澄清）：`kubeconfig` / `ssh` 都是 **hub 侧发起连接**，**不是给 Runner 用**；发布目标与归档机器**都可能是非 K8s 的**，平台须覆盖非容器环境的「连接 / 测试 / 发布 / 执行命令」全链路。前端形态见 console §7.12。

**能力矩阵：谁执行由通道决定**（2026-09-23 自 docs/README §5.6 迁入，本节为唯一权威落点）

| 用户能力 | `agent`（现状） | `kubeconfig`（新增） | `ssh`（新增） |
| --- | --- | --- | --- |
| 连接 | Runner 回连，hub 不入站 | hub → 目标 apiserver | hub → 目标 sshd |
| 测试 | 建 Job 跑 test 脚本 | hub 建 Job 跑 test 脚本 | hub 远程跑 test 脚本 |
| 发布 | Job：`helm` / `kubectl` | hub 建 Job：`helm` / `kubectl` | **制品分发到主机 + 启停服务**（脚本） |
| 执行命令 | Job 容器内 | hub 建 Job 容器内 | **远程命令 / 脚本** |
| 工作区 | EmptyDir 卷 | EmptyDir 卷 | **目标主机上的临时目录** |
| 隔离边界 | ns + SA + RoleBinding | ns + SA + RoleBinding | **无**（SSH 用户身份即边界） |
| 凭据方向 | 目标 → 平台（`GATEWAY_TOKEN`） | **平台 → 目标** | **平台 → 目标** |

**三通道互补，不互相替代**：

| 通道 | 需要 hub 主动网络可达目标吗 | 凭据风险 |
| --- | --- | --- |
| `agent` | **不要求**（目标可在 NAT / 内网后，或禁止入站） | **低**：hub 无目标凭据，hub 失守不波及该目标 |
| `kubeconfig` / `ssh` | **必须**可达 | **中**：凭据与条目**一一对应**（不存在共享的万能凭据），单条失守影响面限于该条目标、不横向扩散；暴露量随直连条目数**线性叠加**（措辞按 2026-09-21 二次裁定更正，非"爆炸半径反转"）。凭据物理存放已定：**AES-GCM 信封加密落 hub DB**（§9.7 第 2 条，2026-09-23 Task #7） |

→ 因此 **`agent` 通道的安全价值必须保留**：最敏感的目标继续走 `agent`，hub 永远不需要它的凭据。

**agent_ops 台账 + agent_op_logs 流式输出**（2026-09-23 第十八批 §16.5 全链路落地，形状权威 = Go struct + `API-REFERENCE.md`）

| 表 | 语义 |
| --- | --- |
| `agent_ops` | hub 发给 runner 的操作台账（`exec` / `install` / `upgrade`）。状态机 **`queued → running → succeeded\|failed`**，只前进、终态不可变（runner 非法流转 hub 拒 409，`IsValidAgentOpTransition`）。`detail` 为 **text**（migration 0018 拓宽，exec 脚本可超 1KiB，派发 payload 逐字携带）。仅 **exec 创建即派发**（离线留守、重连排水补派）；install/upgrade **留守 queued**——执行器依赖 §9.9 bootstrap 流程（install 引导鸡生蛋：目标无 runner 连接则 op 无处投递；upgrade 需图表来源 + 自升级 SA 权限），属接入引导特性（§16.5 裁定） |
| `agent_op_logs` | runner 流式回传的输出分片（`op_id` / `seq` / `stream` / `chunk`），seq 由 hub 按到达顺序分配。落库使晚连接 / 断线重连的 SSE 订阅者可完整重放——与 run 侧 `TaskRunLog` 同一契约（migration 0018） |

exec 的两条执行路径（runner `internal/agentops`）：`agent` access 用 runner 自身 in-cluster 凭据；`kubeconfig` access 由 hub 在派发时解密 `KubeCredRef` 凭据随 payload 下发——**runner 是直连执行器、合法需要该访问**，信任边界 = 已认证 gateway WS（记录在案；hub 自身仍零 client-go）。执行形态一律为目标集群内 **Job（`sh -c`）**：K8s 原生留痕 + batchv1 超时语义；Job 完成后 TTL 1h 自动回收（持久审计在 hub 侧）。

> **协议裁定（为什么是专用消息）**：`agent_op` / `agent_op_status` / `agent_op_log` 三类消息**不复用** run 侧 `status_update` / `log_chunk`——hub 的两个既有 handler 分别直写 `pipeline_runs` 表、按 `PipelineRunName` 索引落日志，混入 op 语义会污染两条既有管道的状态与索引路径。三类回传与 run 侧**表形状**同构（见上表），但**管道隔离**。

**三处既有结论因此作废**

1. §9.1 的「平台**从不入站访问目标**」**须限定为"`agent` 通道如此"**——直连通道下 hub 反向持有目标凭据。
2. §9.1 的安全归因「现有安全性来自 ① 平台无入站路径」**只对 `agent` 通道成立**；直连通道下 hub 反向持有目标凭据。⚠️ **但风险是"按条线性叠加"，不是"爆炸半径反转"**（**2026-09-21 二次裁定更正**）：凭据与环境记录**一一对应**——一条记录一份凭据，**即使指向同一环境、只要条目名称不同就是两份彼此独立的凭据**；**不存在共享的万能凭据**，故单条凭据被攻破的**影响面限于该条对应的目标，不横向扩散到其他目标**。暴露总量随直连条目数**线性增长**，但不产生"一点全破"。
   > 该结论的**前提**（须同时成立）：凭据**只存 ref、明文不落 DB**（§9.7 第 2 条），且 ref 指向的存储**位于 hub 的信任边界之外**——若 ref 只是指向 hub 同集群内的 Secret，则 hub 被攻破时攻击者可顺 ref 取明文，此时隔离性会退化为“全部直连目标同时暴露”。
3. §9.1 的「`targets` 刻意不含凭据列」**结论仍成立，但理由要限定**：那不是"平台永不持凭据"，而是"**`targets` 只描述 `agent` 通道的目标**"。直连目标不落本表（见 §9.7）。

### 9.6 落地 gate（若后续为 §9 加代码）

- `GET /targets` 返回需明确区分角色字段（或由前端按"是否等于平台底座集群"标注），否则单机版下 UI 无法表达"这一行有两个角色"。
- 删目标前置校验：存在引用它的 `environments` → `409 + {reasons}`（现状 500，属缺口修复）。
- 单测：单机版拓扑下建环境（`target_id` 指向自身所在集群）可正常创建与触发运行。

### 9.7 非容器目标与直连通道的承载（**形状已定，表结构待补**）

> 本节是**问题登记 + 形状约定**，不是已实现的表设计。真正的表须在立项后按 §5 维护约定走迁移。

**为什么需要扩表**：`environments.target_id` 是 **NOT NULL FK**（§9.2），而 `host` 目标**根本没有目标行**——现有模型**表达不出**非容器环境。且同时还要装直连凭据，不是"加个可空列"能了事的。

**形状约定**（三条，后续立项须遵守）

1. **`targets` 的语义仍是窄的**：现表只覆盖 `k8s` + `agent` 目标（§9.1），保持窄语义**不变**；`kubeconfig` 目标与 `host` 目标需要**扩表**——加 `targetKind` 判别列并承载 `credentialRef`。
2. **凭据加密落库（2026-09-23 已定，Task #7）**：`credentials` 表直接存凭据值，但经 **AES-GCM 信封加密**（`internal/credentials/codec`，`CREDENTIAL_ENCRYPTION_KEY` 缺失时 dev 明文兼容 legacy），**明文不进 DB、API 只回显 `xxxSet: bool`**。⚠️ 与原「只存 `credentialRef`、物理位置指向 hub K8s Secret / 外部 Vault」铁律**已偏离**——因本库 P0 拓扑无独立 secret manager，引用名方案无法落地，双向钢人裁定改为加密落库（见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §16.4）。
3. **`environments` 的引用要放宽**：`target_id` NOT NULL 须改为**多态引用**（`target_kind` + `target_id`）或"新增可空列 + 恰有其一"约束。**这是破坏性 schema 变更**（现存行都走 `k8s` + `agent` 分支），迁移前须备份。

**已明确、不再讨论的边界**

- 直连通道**必须支持进流水线执行路径**（发布 / 执行命令），不是仅手动诊断——用户明确要求。
- **`agent` 通道保留且优先**：最敏感目标继续走它，hub 永不持其凭据。

**未定（需另开决策）**

- 凭据物理存放位置（见上 2）。
- 直连执行的**权限主体**：✅ 平台级 RBAC 已有 HTTP 端点（§7；`STORY-BACKLOG.md` C-10 已于 2026-09-22 关闭），"谁有权用直连通道执行"**已可**在平台内表达 —— 仍缺的是**执行侧强制点**（runner 侧校验，见下条审计落点）。
- 直连执行的**审计落点**：`agent` 通道有 `task_runs` 状态回流可依；SSH 直连的逐条命令证据链**无现成表**。
- 是否引入 `executor backend` 抽象（runner 侧现仅"K8s Job"一种实现）。

### 9.8 归档目标也可能是非容器机器

制品归档的落点（对象存储桶 / NFS 机 / 文件服务器）同样可能不是 K8s 资源。它与"发布目标"共享同一套 `targetKind` / `access` 语义，但**生命周期不同**——归档是长期存储 + 保留策略，不是发布槽位（保留策略见 console §7.10）。console §7.10 归档说明条（MinIO + NFS 镜像）描述的是**参考形态**，其"归档机怎么连"取决于 §9.7 的落地。

### 9.9 接入编排：runner 的安装与升级（**2026-09-21 二次裁定**）

**定调**：runner 的**安装 / 升级逻辑全部落在 hub**，console 只需调用 API。这是 ① 能力层（"平台对目标做"），**不属 ③ 自身**（§9.3 / §9.4）。

**为什么必须做**（两条实测缺口）

| 缺口 | 依据 |
| --- | --- |
| `targets` 行必须**预先存在**，runner 回连**不自举建行** | `internal/gateway/gateway.go`：`GetByName(X-Target-Name)` 查不到即 `404 unknown target` |
| **版本不可见**，升级无从判断 | `Target.AgentVersion` 字段存在但**全仓零写入点**；runner 侧也不上报版本 |

**数据流（全部在 hub 侧）**

1. console 提交"接入一个目标" → `POST /targets` 预注册 + 提交 kubeconfig（`POST /credentials`，**只存 ref**）。
2. hub 从**版本矩阵 CM**（§9.10）取 runner 版本 → 向目标集群下发安装（helm chart + 镜像）。
3. runner 起来后**出站回连** hub 网关，`Heartbeat` 置 `online`；**kubeconfig 使命就此结束**。
4. 升级：比对 CM 里的 runner 版本 vs `targets.agent_version`，有差异则执行升级。

**已装 / 未装的判据（统一，无特例）**：**已装** = 该 `targets` 行存在且**有 runner 回连**（心跳 `online`，或 `agent_version` 非空）；**未装** = 无回连记录。UI 据此决定动作：**已装 → 升级**，**未装 → 安装**。平台自身集群那一行在平台安装后即**已装**（§9.3），故天然走**升级**分支。

**凭据生命周期（关键约束）**

- kubeconfig 在本链路里是 **bootstrap 凭据**，只服务"把 runner 装进去"这一次；装完即应可作废 / 回收，**不得升格为 hub 的常驻执行凭据**（常驻直连执行是 §9.7 的另一个决策）。
- 凭据**逐条对应、互不共享**（§9.5 第 2 条）：一条目标的凭据泄露**不影响其他目标**。

**落地前置（三个，缺一不可）**

1. `Target.AgentVersion` 要有**写入点**（runner 在握手 / 心跳里上报版本）。
2. **per-target 凭据 / 身份**：现网关 `GATEWAY_TOKEN` 是**全局共享**（§9.1），无法给新装 runner 单独发身份；`POST /targets/:id/enroll-token` 目前**只存在于原型**。
3. hub 需引入 **k8s 客户端能力**（现 `go.mod` 里 `k8s.io/*` 全是 `// indirect`、代码内零 `clientcmd` / `rest.Config`）——这是**控制面边界扩张**，已随本裁定一并批准。

### 9.10 版本矩阵（`package-versions` ConfigMap，**2026-09-21 二次裁定**）

**机制**：部署平台时把**指定版本**的 console / hub / runner 镜像**一并推入镜像仓库**；三者的版本对应关系由一份 **ConfigMap** 维护，**集成在 hub 的 chart 内**随 hub 一起分发。接入管理的安装 / 升级**按该 CM 取值**。

| 要点 | 约定 |
| --- | --- |
| 内容 | `console` / `hub` / `runner` 三个版本号（镜像 tag）的对应关系 |
| 载体 | ConfigMap 名 **`package-versions`**（2026-09-21 用户定名），**集成在 hub chart 内**（随 hub 部署、随 hub 升级） |
| 部署形态 | 平台安装 = **一体化**：console / hub / runner + 数据库**同批装齐**，三者版本号由本 CM 对齐 —— 故平台自身集群天然呈"已装 runner"（§9.3 / §9.9） |
| 事实源 | **hub 仓 `build/hub/versions.yaml`**（**人工填写并维护**的配套清单，构建时渲染进 chart）；它是"当前官方发布版本"的**唯一事实源**。**仓库不参与推断**——三仓各自独立 release、tag 互不知情，"哪个 runner 配哪个 hub"是**人的发布决定**，无法从任何仓的 tag 推导（2026-09-21 用户裁定） |
| 消费方 | hub 的接入编排（§9.9 取 runner 版本）；console 可经 API 只读展示 |

### 9.11 平台自身的部署与升级（**2026-09-21 裁决**，自 E2E 计划 P6 迁入，唯一权威落点）

> 背景：old/go-devops 是 hub 前身、old/go-devops-ui 是 console 前身，曾由此设想"平台发布平台自己"（当时简称「自举」——**该词随方案撤销一并停用**，全库不再单用「自举」二字，见 §9.0 术语消歧）。
>
> **裁决**：平台自身的部署与升级**永远在平台之外**——官方通道 = 各仓 `make package` / `pnpm image` 产出的镜像 + chart 交付包，由**外部 helm / CI** 发布。

**不采纳「自升级」的六条理由**：

1. **hub 是四重自指**：控制面 + 编排存储 + 制品来源 + 制品消费。升级 hub 的编排存在 hub DB 里、chart 由 hub 的制品库供、签名 URL 指向 hub Service——hub 起不来则**升级通道与回滚通道同时消失**，无法自救。
2. **必须放宽安全边界**：runner 的集群侧权限被刻意限定为"只碰某组件命名空间"；让它 helm-upgrade `sdp-workflow` 是**实质扩权**，且 `pipeline.sdp.io` 的 CRD 是 **cluster-scoped**，schema 变更绕不过集群级权限。
3. **不可灰度、不可回滚**：CRD 是集群级原子生效；helm rollback **不还原 CRD**（helm 不追踪 CRD 版本）；hub 建表靠启动时 AutoMigrate（只加不删）。新版本一旦把控制面锁死，唯一救生索是手工 `kubectl`。
4. **观测真空恰好覆盖最关键的那次运行**：hub 重启期间，这次升级的记录 / 日志 / DAG 全在重启中的 hub 里——**最需要看清的运行恰好看不见**。
5. ~~权限主体在 API 层不存在~~ ✅ **已补（2026-09-22，C-10）**：平台级 RBAC 已有 HTTP 端点，"谁有权批准平台自升级"已可在平台内表达；但「自升级」审批流与到期回收仍未落地（STATUS §2 #3）。
6. **收益错配**：平台组件数量固定（hub / console；runner 是接入侧代理不计入）、升级者就是平台运维本人；通用流水线（版本历史 / 参数管理 / 一键回滚 / 审批）在自升级上边际收益低，而这些恰是外部 CI + helm 的强项。

**允许与不允许的分界**

| | 内容 | 理由 |
|---|---|---|
| ✅ 允许 | **hub / console 与 runner** 的**构建**走平台流水线（编译 hub / runner / console、打镜像、打 chart tgz 并归档进制品库） | 吃狗粮验证 Build 链路；失败可重跑，无自指风险（runner 不属平台自身，但构建同源） |
| ❌ 不允许 | 平台组件的**发布 / 升级**走平台（`Release` 不发布平台自身） | 见上述六条理由；升级失败时平台无法自救 |
| ✅ 保留 | **Gen0 手工 helm 基线长期保留**，不是一次性过渡；每次破坏性变更（CRD / DB schema）都回到手工通道 | — |

**"独立升级页面上传组件包升级平台"**：**本期不做**。它不能挂在 console 下（console 本身是被升级对象，它挂了正是最需要该页的时候）；唯一可行形态是**平台之外常驻的 upgrade-controller**（Gen0 手工安装、**永不自升级**，自己服务静态页 + 执行其余三者的 helm 升级）——那是把"平台之外"这条通道产品化，不是把自升级做进平台。若将来要做，作为独立提案重开。

**保留的历史分析**（自升级方向已撤销，但下列机制性结论在将来重开时仍然成立）

- 代际阶梯（解决鸡生蛋）：Gen0 手工（postgres + hub + runner）→ Gen1 平台发布 demo-app（P3/P5）→ ~~Gen2 平台发布自己~~（**2026-09-21 撤销**）。
- `Build → Approval → Release`：升级自己挂了没人救，人工卡点不可省。
- hub / runner 必须分两个 Release 任务、按阶段顺序先 hub 后 runner：hub 升级时 runner 断连只重连不退出（存量任务照跑）；runner 自升级时，执行升级的 releaseContainer Job 独立于 runner Pod 存活，旧 runner 把 reconcile 跑完。
- 上一版 chart / 镜像必须留在制品库：helm 原生 rollback / P4 回滚随时可用。
- **CRD schema 分级处理**（不是一刀切禁止）：
  - **兼容变更**（新增可选字段、放宽校验、加枚举值）可自动——但必须是显式前置步骤（pre-upgrade hook Job 或独立的 kubectl apply 任务）。注意 Helm 3 的 `crds/` 目录是 install-only，`helm upgrade` **不会**更新它——靠 chart 直升 CRD 需要放 `templates/`（helm 会接管其生命周期，uninstall 连删，不推荐）或走 hook
  - **破坏性变更**（加 required、删字段、改类型、引新版本+conversion）必须手工：先备份存量对象（`kubectl get -o yaml`）再 apply
  - 破坏性变更手工的三个硬理由：① CRD 变更是**集群级原子生效，无法灰度**——Deployment 能金丝雀，schema 不能；② helm rollback **不还原 CRD**（helm 不追踪 CRD 版本），"回滚是安全网"的前提对 schema 失效；③ runner 既是升级执行者又是被升级者——破坏性变更会让旧 runner 写出的对象过不了新校验，**锁死自升级通道本身**，唯一救生索就是手工 kubectl
  - 判断口诀：**改完后，旧版本 runner 创建的对象还能通过新 schema 校验吗？** 能→兼容可自动；不能→破坏必须手工
- **前置改造（若将来重开必做）**：制品存储须先从 hub 自带的 `local` driver 解耦为外部对象存储——否则 hub 挂了拉不到 chart（现 P0 拓扑下 `ARTIFACT_STORE_PUBLIC_URL` 指向 hub Service）。
| 与 ③ 的关系 | CM 的**更新**属平台发布动作，走 §5.4 的"平台之外"通道——**平台不自己改自己** |

**写入点（2026-09-21 落地）** —— 回答"发 release 时，版本写在哪里、由谁检查"

| 环节 | 落点 | 说明 |
| --- | --- | --- |
| ① 事实源（人工） | hub 仓 `build/hub/versions.yaml` | 三组件配套版本的**唯一人工填写点**。三仓各自独立 release（tag 互不知情），配套关系必须显式写下来 |
| ② 版本检查 | `build/hub/build.sh` → `resolve_versions()` | 清单缺失 / **任一键为空或非法 SemVer** → **构建失败**（带人话提示）；带 `-r1` 这类后缀 → 构建日志给 **NOTE**（非致命，提示其 SemVer 语义，见下）；`hub` 键 ≠ 本次 tag → **告警**（以 tag 为准）。console / runner 键按清单取值 |
| ③ 渲染 | `build/hub/build.sh` → `render_chart_version()` + `render_package_versions()` | 把 tag 与清单值写进**交付包内的 chart 副本**（`output/charts/...`）；**不动仓内源文件**（源文件仍是模板基线 `v0.0.1`） |
| ④ 载体 | chart `templates/configmap-package-versions.yaml` + `values.yaml` 的 `packageVersions:` 段 | 渲染出 CM `package-versions`。**不写 `metadata.namespace`**——命名空间内资源一律由 helm 的 release namespace 决定（与本仓 Deployment / Service / PVC 及 console 两个 CM 同约定；全仓仅 runner `rbac.yaml` 显式写，因其为集群级资源 / 跨命名空间引用）。写死 `{{ .Release.Namespace }}` 会让 `helm template`（未带 `-n`）把 CM 渲染进 `default`，而 Deployment 无 namespace → `kubectl apply -n <ns>` 时两者分离，`configMapKeyRef` 解析失败 |
| ⑤ 消费 | `templates/deployment-hub.yaml` → env `PACKAGE_VERSION_{CONSOLE,HUB,RUNNER}` | hub 端点 `GET /package-versions` ✅ **已落地（2026-09-23，`internal/packageversion`）**，env 已就位 |
| ⑥ 触发 | `.github/workflows/release.yml`（GitHub Release published → `build.sh <tag>`） | **钩子已存在**，本次未新增流程 |

**版本号规范（SemVer 2.0.0，2026-09-21 用户确认）** —— 三组件版本号统一遵循 <https://semver.org/lang/zh-CN/>

| 规则 | 说明 |
| --- | --- |
| 形态 | `vMAJOR.MINOR.PATCH`，可带后缀 `-PRERELEASE` / `+BUILD`。`v` 前缀是 **git tag 约定、不属于 SemVer 本体**，写进 `Chart.yaml` 的 `version` 时去掉（`render_chart_version()` 已如此处理） |
| 谁维护 | **人工填写并维护**（`build/hub/versions.yaml`）。仓库**不知道**版本对应关系——三仓独立 release，配套关系是发布决定、不是可推导的事实 |
| 三组件不必同号 | 各自独立演进。**一套版本 = 三者的某一条组合**。例：`console v0.1.1 + hub v0.1.1 + runner v0.1.2-r1` 即一套完整发布 |
| ⚠️ `-r1` 的语义陷阱 | `-r1` 是 **pre-release**，SemVer 规定其优先级**低于**同号正式版（`0.1.2-r1 < 0.1.2`）。若本意是"正式版之后的重制"，语义上更贴切的是升 patch（`0.1.3`）；`build metadata`（`+r1`）不参与优先级比较，**但 Docker/OCI 镜像 tag 不允许 `+`**，故镜像 tag 上只能用 `-` 形式 |
| 校验落点 | 见上表 ②：非法/空值 → 构建失败；带后缀 → NOTE。已实测 `helm lint` 接受 `Chart.yaml version: 0.1.2-r1`（0 failed） |

**同批修掉的既有缺口**：三仓 `build.sh` 此前只把 `version` 用在 `-ldflags` / 镜像 tag / 交付包文件名三处，**chart 内 `values.yaml` 的 `imageAddr` 与 `Chart.yaml` 的 `version` 是硬编码 `v0.0.1`** —— 发 `v0.0.2` 的包，`helm install` 仍指向 `v0.0.1` 镜像（拉不到 / 装错版本）。现三仓 `build.sh` 均加 `render_chart_version()` 一并修正，已用 `helm template` 验证渲染出的 `image:` 随 tag 走。

**后续可选**（未做）：CI 侧增加"被引用的 runner / console tag 是否真实存在"的**一致性校验**（需 GitHub API 查询）。**边界**：这只能是**校验**，**不得**演化为"自动取各仓最新 tag 填进 CM"——配套关系是人工发布决定（见上表"谁维护"）。
