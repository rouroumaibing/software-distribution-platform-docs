# 数据模型关系说明（Data Model Relationship）

> 本文档钉死软件分发平台 hub 的核心关系链，作为后续建模与代码审查的权威参考。
> 来源：`internal/org`、`internal/catalog`、`internal/component`、`internal/pipeline`、`internal/run` 各 `models` 包（已读源码核实，非推测）。
>
> **项目目标（对齐 console / runner）**：hub 是 SDP 的控制平面，为"通过界面交互把软件构建、测试、发布到多套环境"提供数据模型与 REST API 支撑。核心能力 = 组织 / 服务树 / 组件 / 环境 / 配置 / 流水线 / 运行 的 CRUD 与编排下发，以及运行态状态回收。标准流水线模式（日常 / 版本归档 / 转测 / 生产，见 console `CONSOLE-UI设计文档.md` §1.1）由 Pipeline（锚定单 Component）+ 阶段 + 三态任务（Build/Release/Approval）表达。落地顺序：先贯通基本功能（G1–G6 已完成），**权限管控（G7）已落实（P1 建表 / P2 审批子系统 / P3 Enforcement，见 §7）**。

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
- **阶段内子任务按 `ExecutionMode` 执行**（`PipelineStage.ExecutionMode`，**⚠️ 待实现，见 §6.4**）：`Parallel`（**当前唯一已实现**值，同阶段子任务同时可运行、无相互依赖）/ `Serial`（**待实现**，同阶段子任务按序执行）。设计上 `Serial` 由 hub `buildSpec` 按序推导阶段内 `DependsOn` 链实现；runner 消费的是已解析 DAG，无需感知"串行/并行"——它只看 `DependsOn`。阶段间恒串行（跨阶段 `DependsOn`，**已实现**）。注：`ExecutionMode` 字段与阶段内 `DisplayOrder` 排序均**尚未落地**（`PipelineStage` 现仅 `pipeline_id/name/sequence`）。
- **子任务交互**：`Produces`/`Consumes`（JSON 键）描述产物产出与消费；触发时 run service 直接 copy 进 `runnerapi.PipelineTaskSpec`，并跨 stage 推导 `DependsOn`。
- **类型分工**：`Build`=内联命令执行（如 `pytest`/`go build`，跑在 `Image` 工具镜像里；也支持 `ScriptPath` 脚本逃生通道）；`Release`=施加一个软件单元（`ReleaseConfig` 里的 chart/manifest 源 + 从参数管理注入的 `values`），可选 `RolloutConfig` 做金丝雀；`Approval`=人工卡点（结果写 runner CR 的 `ApprovedBy/RejectedBy`）。

---

## 2. 运行链（执行态，快照）

```
Pipeline  ──1:N──▶  PipelineRun    (pipeline_runs.pipeline_id + cluster_id + CRName + CRNamespace + pipeline_version)
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
| `pipeline_runs` | `pipeline_id` | `pipelines` | 1:N，加 `cluster_id` + `version` 快照 |
| `task_runs` | `pipeline_run_id` | `pipeline_runs` | 1:N |
| `task_runs` | `task_template_id` | `pipeline_task_templates` | 可空，反查权威 `stage_id`（**不是** stage FK） |

---

## 5. 维护约定（给后续开发）

- 新增"资源"时，默认以 `Component` 为锚，保持组件页是唯一管理入口。
- 任何让 `Pipeline` 脱离单 `Component` 的改动的都违反不变式 #3，需先回到设计评审。
- 改动 `TaskRun.StageName` 语义前，先读 `internal/run/models/task_run.go` 的字段注释（快照、非 FK）。
- 运行态与定义态的关联一律走 `TaskTemplateID` 反查，不要在运行表新建对定义表的外键。

---

## 6. 流水线下发与进展回收（含双向钢人论证）

> 本章是 console `CONSOLE-UI设计文档.md` §6.0、runner `STORY-runner-implementation.md` §4.3 的落地依据。聚焦三个你点名的开放问题：① runner 怎么取任务；② 进展记在哪；③ 命令怎么跑。每个都做双向钢人论证后给推荐。

### 6.1 任务落地与下发机制（现状，推送模型）

触发 `POST /pipelines/:id/runs` → `PipelineRunService.Trigger`：
1. 落 `pipeline_runs` 一行（Pending）+ 按 spec 种子 `task_runs`（每 DAG 节点一行，Pending）—— **"任务先落实到数据库"在 hub 侧成立**；
2. 入队 `dispatch_jobs`（Pending）携带完整 `ApplyPipelineRunPayload`；
3. 立即尝试下发；Runner 离线则 job 保持 Pending，重连（`DrainCluster`）/ 周期扫（`SweepPending`）重投，运行不失败（状态机见 `dispatch_job.go`）；
4. Runner 经出站长连接收 `apply_pipeline_run` → 建 `PipelineRun` CR → 调度执行 → 每状态变更经 `status_update` 流回 → hub `ApplyStatus` 写回 `task_runs` / `pipeline_runs`。

> 结论前置：你设想的"任务先落 DB、runner 按 DB 任务执行"在 **hub 侧完全满足**；差异仅在"runner 怎么拿到任务"——是 DB 直连拉取，还是 hub 推送 spec 快照。见 §6.2。

### 6.2 双向钢人论证①：runner 拉 DB vs hub 推 spec

**正方（runner 直接读 hub DB 拉任务）**
- 极简心智：runner 是无状态 worker，定时 `SELECT * FROM task_runs WHERE cluster=? AND phase=Pending`，天然幂等，断线重连零成本；
- 单一真相源在 Postgres，排查只查一处；无需 WS 长连接与帧协议；
- 与你最初设想"任务先落 DB、runner 按 DB 执行"一字不差。

**反方（保留 hub 推送 spec + runner CRD 执行）** —— 现状采用
- **安全边界**：runner 是部署在各业务集群的 agent，不应持有 hub Postgres 凭据；推送模型 runner 只持 `CLUSTER_AUTH_TOKEN` 连 hub 网关，凭证/权限留在 hub（G7 在 hub 侧统一落实）；
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
- 阶段进展 API：`GET /runs/:id/stage-progress`（见 §6.5，**确认新增、待实现**）；**当前 hub 仅实现 `GET /runs/:id/progress`**（返回 `phase + per-task`，未做 Stage 级 rollup）。

### 6.4 DB 表设计变更（本次新增/推荐）

**① `pipeline_stages` 加 `execution_mode`**（实现阶段内串行/并行；**已确认方向为放 Stage 级；⚠️ 当前未实现**——`PipelineStage` 结构体现仅 `(pipeline_id, name, sequence)`，无该字段）
```sql
ALTER TABLE pipeline_stages ADD COLUMN execution_mode varchar(16) NOT NULL DEFAULT 'Parallel';
-- 枚举: 'Parallel' | 'Serial'
```
- （**待实现**）`Serial` 时 hub `buildSpec` 应在同阶段任务间推导 `DependsOn` 链；**当前 `buildSpec` 无此分支**，同阶段任务一律并行。runner 无新字段，纯消费 DAG（CRD 类型无需改）。
- store 层 `ListByPipelineID` 已按 `sequence` 返回；UI 并行/串行开关写入此列后由 `buildSpec` 消费（待接线）。

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
| `GET /runs/:id/stage-progress` | `{ run, stages: [{name, sequence, executionMode, status, done, total}] }` | **确认新增**（derive-on-read 实现）；后端按 `StageName` 聚合，供 console §7.6 顶部阶段卡 |

---

## 7. 授权模型（权限管控 G7；目标态 = 多 org；P1 建表 / P2 审批 / P3 Enforcement 均已落地；**平台级 HTTP 端点待补**）

> ⚠️ **状态勘误（2026-09-15）**：本节 §7 表 + Enforcement 中间件已落地，但 `platform_roles` / `platform_role_bindings` **尚无 HTTP 端点**（`internal/permission/handler/` 下仅有 `role` / `component_role` / `binding` 组件级 handler，`main.go` 未注册 platform 级路由）。平台管理员绑定须经 API 配置的能力未暴露（backlog P1-1）。详细对账见 `DOC-CODE-CALIBRATION-2026-09-15.html`。

> 双向钢人论证结论（见 [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI设计文档.md) / 对话记录）：Keycloak 与 k8s RBAC 均**退到边界**——KC 只做身份+组，k8s RBAC 只管 runner 集群操作；承载"用户对组件能做什么 + 谁能审批"的是 **hub 内的两层 RBAC + 审批表**。这同时满足：① 组件级权限以"管理员/组映射为主"（无运行时自助需求 → 不引入 Keycloak UMA）；② 默认审批人 = 组件 owner/管理员（所有权在 app，见 §7.4）。

> ⚠️ **实现现状（V1，已在代码）≠ 本章设计（目标态，迁移中）**——V1 与 §7 表并存是**有意为之的增量迁移**，不是两套对立设计：
>
> | 维度 | V1（已实现，M1） | 本章设计（目标态，M2，**多 org**） | 迁移相位 |
> | --- | --- | --- | --- |
> | 角色表 | 单张 `roles`（`permissions jsonb`，`org_id` 归属） | `platform_roles` + `component_roles`（`actions[]` 枚举，**均带 `org_id`**） | P1 建表；P3a §7 action 权威 |
> | 绑定主体 | `component_role_bindings.user_id uuid NOT NULL`（无组） | `subject_type[user\|group] + subject_id` + **`org_id`**（冗余隔离） | P1 加列+回填；P3a/c Enforcement+console 切换 |
> | 平台级 | **无** | `platform_roles` / `platform_role_bindings` | P1 建表；P3a Enforcement 就绪（console UI 待落地） |
> | 组件所有权 | **无** `owner_user`/`owner_group` 列 | `components.owner_user`/`owner_group` | P1 加列；P3b owner 自动绑 component-admin |
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
>   - **P3b**：组件创建自动把 owner 绑 `component-admin`（非致命失败），`Create` 写入 `owner_user`；handler 手写路由、owner 未填时从会话补。见 `internal/component/{service,handler}/component.go`、`internal/permission/handler/binding.go`。
>   - **P3c**：console `permissions.ts` 切换 §7 `ComponentRoleBinding`（`subjectType` / `subjectId` / `componentRoleId`）+ 新增 hub `GET /component-roles`（`internal/permission/handler/component_role.go`）；`PermissionsTab.vue` 支持 user/group 主体、§7 角色选择器、自审拦截提示。V1 旧行（`userId` / `roleId`）回显兼容。
> - **遗留（非阻塞）**：V1 `roles` / `approvals` 表与代码路径保留为迁移窗口兼容，未删除；Keycloak 组目录未由 hub 暴露（console 组名手填，待 `/groups` 接口）；平台级权限 UI（`platform_role_bindings` 管理）尚未在 console 落地。

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
- **增删改查颗粒度**：逐 action 授权，支持"能看不能改""能触发不能删"等组合；前端权限页见 [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI设计文档.md)。

### 7.4 审批子系统（pipeline approvals）

> 开源参考：GitHub Environments（required reviewers + prevent self-review + wait timer）、GitLab Protected Environments（manual job + required approvers）、Spinnaker Manual Judgment（审批=独立 stage）、Backstage Permission Framework（ownership 驱动默认权限）。

- **`pipeline_approvals`**：`(id, run_id, task_run_id, component_id, status[Pending|Approved|Rejected|Cancelled], requested_by, approver, decision_comment, created_at, decided_at)`。`task_run_id` 关联处于 `WaitingApproval` 的 Approval 子任务（§6.2）。
- **选谁审批**：编排流水线时可在 Approval 任务上指定 `approver`（用户/组）；**未指定则默认 = 组件 owner / 组件 admin 组**（取自 §7.3 默认绑定 / 组件所有权）。
- **默认审批人来源**：组件所有权模型（app 数据）——组件表 `owner_user` / `owner_group`；创建组件时写入，并同步**把 owner 自动绑 `component-admin`**（见 §7.3），因此 owner 天然持有 `approval:approve`，即默认审批人。
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
| 动态策略（可选） | **OPA / Casbin** | 未来"仅工作时间可发布生产"等用策略引擎，不在本期 |

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
  -- V1 兼容列（迁移窗口保留，可空）：旧 per-user 绑定（roles 表）仍可按 user_id 解析
  user_id UUID REFERENCES users(id),
  role_id UUID REFERENCES roles(id),
  granted_by UUID, granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
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
| 删环境 / 删组件时，**集群侧**已部署资源是否回收 | **不回收**（平台与目标环境隔离，避免平台误伤生产） | §8.4「删环境」行**不再涉及集群侧**；删环境只处理**平台侧**（DB 行 + 审计） |
| 「残留」的定义 | **只指平台侧**遗留（DB 行 / 对象存储对象 / 配置与审计） | §8.4「删组件」行的"分组应随之消失"须**服务层显式级联**（组件软删，DB `ON DELETE CASCADE` 不触发）；集群侧不计入残留 |
| `component_config_history.environment_id` | **去 FK + 加 `environment_key` 快照列**（优于单纯 `ON DELETE SET NULL`） | §8.4「删环境」的"删除前须告知配置覆盖行数"**仍然成立**；同时消除"删环境随机 500"（现状：`component_configs` 是 cascade、`config_history` 是 `NO ACTION`，同一操作两种结果） |
| `pipeline_stages` / `pipeline_task_templates` | **补 `deleted_at`** + **封父存在性校验** + **修 `pipelines` 唯一约束** | 与本章无直接耦合，记录于 `DELETE-CONTRACT.md` §6.6-3（B-15）。**(a) 父存在性校验 + (b) `pipelines` 改 partial unique index + (c) 模型时间列映射已于 2026-09-16 落地**；`deleted_at` 待拍板 |
| Artifact 孤儿对象 | **先堵源头 → 后做对账（仅报告，不自动删）** | 同 `DELETE-CONTRACT.md` §6.6-4（B-16） |

**未变（仍然有效）**：
- §8.2 的 DDL 方案（新表 `environment_groups` + `environments.group_id` **可空**）；
- §8.4 的"组内有环境则 `409 + {reasons}` 拒绝 / 组内空则允许硬删"；
- §8.5 的 `env_type`（平台策略标记）与分组**正交，不合并**；
- §8.6 的折叠状态**不落库**（用户级 UI 偏好）。

**关联 backlog**：`STORY-BACKLOG.md` B-13（环境分组落库）、B-14（config_history 快照列）、B-15（stages/templates 标记与入口校验）、B-16（artifacts 治理）。
