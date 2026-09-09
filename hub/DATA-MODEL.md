# 数据模型关系说明（Data Model Relationship）

> 本文档钉死软件分发平台 hub 的核心关系链，作为后续建模与代码审查的权威参考。
> 来源：`internal/org`、`internal/catalog`、`internal/component`、`internal/pipeline`、`internal/run` 各 `models` 包（已读源码核实，非推测）。
>
> **项目目标（对齐 console / runner）**：hub 是 SDP 的控制平面，为"通过界面交互把软件构建、测试、发布到多套环境"提供数据模型与 REST API 支撑。核心能力 = 组织 / 服务树 / 组件 / 环境 / 配置 / 流水线 / 运行 的 CRUD 与编排下发，以及运行态状态回收。标准流水线模式（日常 / 版本归档 / 转测 / 生产，见 console `CONSOLE-UI设计文档.md` §1.1）由 Pipeline（锚定单 Component）+ 阶段 + 三态任务（Build/Release/Approval）表达。落地顺序：先贯通基本功能（G1–G6 已完成），**权限管控（G7）紧接着落实**。

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
- **阶段内子任务按 `ExecutionMode` 执行**（`PipelineStage.ExecutionMode`，见 §6.4）：`Parallel`（默认，同阶段子任务同时可运行，无相互依赖）/ `Serial`（同阶段子任务按 `DisplayOrder` 顺序执行）。`Serial` 由 hub `buildSpec` 按序推导阶段内 `DependsOn` 链实现，runner 消费的是已解析 DAG，无需感知"串行/并行"——它只看 `DependsOn`。阶段间恒串行（跨阶段 `DependsOn`）。`DisplayOrder` 在 `Serial` 时即执行顺序，在 `Parallel` 时仅展示排序。
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

触发 `POST /runs` → `PipelineRunService.Trigger`：
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
- 阶段进展 API：`GET /runs/:id/stage-progress`（见 §6.5，当前即派生实现）。

### 6.4 DB 表设计变更（本次新增/推荐）

**① `pipeline_stages` 加 `execution_mode`**（实现阶段内串行/并行；**已确认 `ExecutionMode` 放在 Stage 级**）
```sql
ALTER TABLE pipeline_stages ADD COLUMN execution_mode varchar(16) NOT NULL DEFAULT 'Parallel';
-- 枚举: 'Parallel' | 'Serial'
```
- `Serial` 时 hub `buildSpec` 按 `DisplayOrder` 在同阶段任务间推导 `DependsOn` 链；runner 无新字段，纯消费 DAG（CRD 类型无需改）。
- store 层 `ListByPipelineID` 已按 `sequence` 返回，UI 并行/串行开关即写此列。

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

## 7. 授权模型（权限管控 G7；设计已落，待实现）

> 双向钢人论证结论（见 [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI设计文档.md) / 对话记录）：Keycloak 与 k8s RBAC 均**退到边界**——KC 只做身份+组，k8s RBAC 只管 runner 集群操作；承载"用户对组件能做什么 + 谁能审批"的是 **hub 内的两层 RBAC + 审批表**。这同时满足：① 组件级权限以"管理员/组映射为主"（无运行时自助需求 → 不引入 Keycloak UMA）；② 默认审批人 = 组件 owner/管理员（所有权在 app，见 §7.4）。

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

- **`component_roles`**：`(id, name, description, actions[])`，action 枚举（Casbin 风格 `resource:action`）：
  - `component:read` / `component:update` / `component:delete`
  - `pipeline:read` / `pipeline:create` / `pipeline:update` / `pipeline:delete` / `pipeline:trigger`
  - `config:read` / `config:update`
  - `artifact:read` / `artifact:download` / `artifact:delete`
  - `approval:approve`（仅 approver 持有）
  - 预置三种角色：`component-viewer`(read 类)、`component-editor`(read+update+trigger+create/delete pipeline+config)、`component-approver`(+`approval:approve`)。
- **`component_role_bindings`**：`(id, component_id, subject_type[user|group], subject_id, component_role_id)`。同一组件可多绑定；`subject_type=group` 复用 KC 组。
- **默认绑定（满足"默认审批人=组件 owner/admin"）**：创建组件时自动生成两条——`component-approver` 绑到组件 owner（或 owner 组）、`component-editor` 绑到组件 admin 组；owner/admin 来源见 §7.4 所有权。
- **增删改查颗粒度**：逐 action 授权，支持"能看不能改""能触发不能删"等组合；前端权限页见 [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI设计文档.md)。

### 7.4 审批子系统（pipeline approvals）

> 开源参考：GitHub Environments（required reviewers + prevent self-review + wait timer）、GitLab Protected Environments（manual job + required approvers）、Spinnaker Manual Judgment（审批=独立 stage）、Backstage Permission Framework（ownership 驱动默认权限）。

- **`pipeline_approvals`**：`(id, run_id, task_run_id, component_id, status[Pending|Approved|Rejected|Cancelled], requested_by, approver, decision_comment, created_at, decided_at)`。`task_run_id` 关联处于 `WaitingApproval` 的 Approval 子任务（§6.2）。
- **选谁审批**：编排流水线时可在 Approval 任务上指定 `approver`（用户/组）；**未指定则默认 = 组件 owner / 组件 admin 组**（取自 §7.3 默认绑定 / 组件所有权）。
- **默认审批人来源**：组件所有权模型（app 数据）——组件表 `owner_user` / `owner_group`；创建组件时写入，并同步生成 `component-approver` 绑定。
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

- **与现有 G7 TODO 对接**：在 `component.go`/`org.go`/`environment.go`/`catalog/service.go` 的 service 层入口注入上述校验（见 附 B G7 项）。

### 7.6 开源参考映射

| 子问题 | 参考 | 借鉴点 |
| --- | --- | --- |
| 平台级 / 组件级 两层颗粒度 | **ArgoCD** Global vs Project-scoped RBAC（`ArgoCDRole`/`ArgoCDRoleBinding`） | 全局角色定义 + 组件级绑定两张表 |
| 组件级细粒度 + 组映射 | **Keycloak** group/role（仅作身份+组，不做 UMA 资源授权） | KC 组 → hub 角色映射 |
| 默认审批人 = owner | **Backstage** ownership 驱动权限 | 所有权是 app 数据，驱动默认审批 |
| 选谁审 / 通过拒绝 / 防自审 | **GitHub Environments / GitLab Protected Environments / Spinnaker Manual Judgment** | 审批=独立门禁节点；required reviewers + 防自审 + wait timer |
| 动态策略（可选） | **OPA / Casbin** | 未来"仅工作时间可发布生产"等用策略引擎，不在本期 |

### 7.7 表结构（DDL 草稿，待实现）

```sql
-- 平台级
CREATE TABLE platform_roles (
  id UUID PRIMARY KEY, name TEXT UNIQUE NOT NULL, description TEXT,
  actions TEXT[] NOT NULL DEFAULT '{}'
);
CREATE TABLE platform_role_bindings (
  id UUID PRIMARY KEY, subject_type TEXT NOT NULL CHECK (subject_type IN ('user','group')),
  subject_id TEXT NOT NULL, platform_role_id UUID NOT NULL REFERENCES platform_roles(id),
  UNIQUE (subject_type, subject_id, platform_role_id)
);

-- 组件级
CREATE TABLE component_roles (
  id UUID PRIMARY KEY, name TEXT UNIQUE NOT NULL, description TEXT,
  actions TEXT[] NOT NULL DEFAULT '{}'
);
CREATE TABLE component_role_bindings (
  id UUID PRIMARY KEY, component_id UUID NOT NULL REFERENCES components(id),
  subject_type TEXT NOT NULL CHECK (subject_type IN ('user','group')),
  subject_id TEXT NOT NULL, component_role_id UUID NOT NULL REFERENCES component_roles(id),
  UNIQUE (component_id, subject_type, subject_id, component_role_id)
);

-- 审批
CREATE TABLE pipeline_approvals (
  id UUID PRIMARY KEY, run_id UUID NOT NULL REFERENCES pipeline_runs(id),
  task_run_id UUID REFERENCES task_runs(id),
  component_id UUID NOT NULL REFERENCES components(id),
  status TEXT NOT NULL CHECK (status IN ('Pending','Approved','Rejected','Cancelled')),
  requested_by TEXT NOT NULL, approver TEXT, decision_comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), decided_at TIMESTAMPTZ
);
```
