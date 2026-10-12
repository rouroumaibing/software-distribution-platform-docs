> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · 附 A 后端依赖与待确认 + 附 D API 契约与三层数据模型
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 附 A：后端依赖与待确认

| # | 项 | 类型 | 说明 |
| --- | --- | --- | --- |
| N-1 | 全局运行聚合端点 | **已落地** | `GET /runs` 已存在（hub `cmd/hub/main.go` 的 `scoped.GET("/runs", pipelineRunHandler.ListAll)`，service/repo 按 `created_at desc` 排序，支持 `page/pageSize/phase` 精确匹配）。**【2026-10-08 更新】时间窗过滤已落地**：`?createdAfter=`（RFC3339，hub `run/handler/pipeline_run.go:139-147`）；仍未支持 `assignee`（N-2） |
| N-2 | 待我审批端点 | 【后端依赖】 | 建议 `GET /runs?filter=awaiting_me` 或在 N-1 内加 `assignee=me&phase=WaitingApproval`。当前只能筛到 `phase=WaitingApproval`（"待我"这层身份过滤未实现）——**因此运行视图的「待我审批」筛选项目前名不符实** |
| N-3 | 跨组件发布列表 + 全局流水线端点 | **部分落地 / 部分消解** | hub 现已暴露全局 `GET /pipelines`（列表）与完整 `/releases` CRUD（`POST`/`GET`/`GET/:id`/`PUT`/`DELETE`）。**v4.4 后"全局流水线列表"无消费面**（流水线列表归组件「交付」）；发布视图在**设计层面**可直接走后端全局端点，无需前端聚合兜底（**实现版仍走扫描 + kind 聚合** —— console 侧尚无 `releaseApi` 封装，见 附 B B.10「刻意不做」①）。另：**「已暂停」筛选已落地【2026-10-08 核对】**：`GET /releases?scope=global&state=paused` 已支持（hub `run/service/release.go:32-55` 将 `state` 语义键 `all/running/paused/succeeded` 映射为 RolloutPhase、非法键 400；handler 校验 `scope` 仅接受 `global`；`Paused` 属 Rollout 任务级状态，见 §7.6），无需逐 run 拉 tasks（N+1） |
| N-4 | `/pipelines` CRUD 端点存在性 | **已核对（2026-09-15）后端有** | `internal/pipeline/handler/pipeline.go` 显式注册了 `POST /pipelines`、`GET/PUT/DELETE /pipelines/:id`、`GET /components/:id/pipelines`（注释里写明"exposes the pipeline CRUD surface consumed by the console's createCrud('/pipelines')"）。**旧文 附 A.1「后端无 GET/POST/PUT/DELETE `/pipelines/:id`」的说法作废** |
| N-5 | 流水线删除语义 + 级联校验契约 | 【待确认 + 后端依赖】 | 行为契约（残留判定 + `409 + {reasons}` 规格 + 实现态）见 [`shared/DELETE-CONTRACT.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md) §2，与服务树删除同模式（附 C / N-15）；前端零判断、只渲染 verdict。原型 `delPipeline` 走后端 verdict 模式（见 §6.1 D1 / §7.4） |
| N-6 | 流水线 `version` 递增策略 | 【待确认】 | 更新后是否 `version+1`；无历史表时仅作展示 |
| N-7 | 编排 `kind` 限制 | **已消解【2026-10-08 核对】** | 客户端不设「仅 `kind==='build'` 可编排」闸门（`PipelinesTab.vue:73-77` 注明：hub 的 `kind` 是自由分类、无服务端校验，与可编排范围无关，见 附 H.5-3）；release/custom 均可编排 |
| N-8 | 全局搜索端点 | ✅ **已落地** | 建议 `GET /search?q=&type=component,pipeline,service&limit=20`，返回 `{type,name,path,id}`。**R-7 全局搜索依赖此端点**；无则退化为前端在已加载资源内搜索（不覆盖未展开的深层节点）。console 侧客户端索引：`useResourceMap.buildResourceIndex()` 一次遍历服务树摊平 Service/组件/流水线建索引，`utils/search.ts` 客户端打分排序，可跨层直达（不依赖树展开），代价是索引在**首次 ⌘K 时**全量拉取（M1 百级请求可接受，且启动 0 次树请求的 S5 不变量不受影响）。落地记录见 附 G。hub 侧 `GET /search`（`internal/search`：三类各取 `limit` 条、`ILIKE` + LIKE 元字符转义、精确命中 > 前缀 > 包含 的排序；响应 `[{type,id,name,path,keyword}]`）；console 的 ⌘K 为**服务端优先、客户端索引兜底**，降级时浮层明示（不静默）；客户端索引保留为空查询的"头部视图"来源（§5.3 要求）。见 附 I |
| N-9 | 树分层懒加载端点 | ✅ **已落地** | 建议的三条全部存在：`GET /orgs`（已有）、`GET /orgs/:id/services`（`internal/catalog`；一次把组织 id 解析成 1:1 服务树再列直接子层，替前端省掉一跳）、`GET /services/:id/components`（已有）。懒加载按此实现，S5 的"分层请求"成立；服务树页展开组织 = 1 次请求、展开服务 = 1 次请求，挂载 = 2 次（组织 + 首个组织的服务），不随服务数线性膨胀。见 附 I |
| ~~N-10~~ | ~~「最近访问」持久化~~ | **已废** | 左栏无「最近访问」分组（S5 恒定不变量），无需持久化方案 |
| N-11 | 两个搜索入口是否合并 | 【待确认】 | 服务树页内搜索（就地定位，含未展开的深层节点）与顶栏 ⌘K（跨页跳转）是否重叠。选项：① 保留分工（当前）② 页内搜索降级为"仅过滤已加载节点"，统一由 ⌘K 承担跨层搜索 ③ 去掉页内搜索 |
| N-12 | 目标 KPI 与接入管理页的关系 | 【待确认】 | Dashboard「在线目标 3/4」是否直接复用 `/admin/targets` 的聚合（避免两处口径不一致） |
| N-13 | 运行中心视图的路由形态 | **已裁决（A）** | 取 `?view=runs\|releases`（query），**不**用嵌套子路由。双向钢人论证 + 5 条硬约束见 **附 B**。**真实 console 已于 2026-09-19 同步为两视图**（`src/constants/runCenter.ts` + `router` redirect + `pnpm test:runcenter` 断言 + §10.2 用例一次原子改，落地记录见 附 B B.10） |
| N-14 | 全局视图的状态筛选是否需要后端参数 | **部分落地** | 运行视图的 `phase` 已下推服务端（`GET /runs?phase=`）；发布视图因走前端聚合，筛选只能在已拉取的窗口内生效——数据被截断时表格上方会显式提示"按最近 N 条运行聚合，全局聚合端点待补"，不静默给错数字 |
| N-15 | 服务树节点删除的级联校验端点 | **已落地** | hub 端点已实现：**活跃 run → `409 + {reasons}`，其余一律级联软删**（hub `catalog/service/service.go:145-168`：fast-path 即时 409 + 级联事务内 guard 复检、同一事务；`common/errors.go:153-158` 提供 `409 + {reasons}` 结构）。console 侧 `ServiceTreeView.vue:565-640` 真调用 `DELETE` 并渲染 409 reasons（非 mock）。行为契约详见 [`shared/DELETE-CONTRACT.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md) §1，论证与前端分工见 **附 C**。清理顺序提示：组件 → 流水线/环境 → 服务 → 组件 … → Org |

---

## 附 D：API 契约与三层数据模型（console 侧事实来源）

> **边界**：本附录只保留 **console 侧的消费状态**（哪个桩接了哪个端点）。**请求体 / 响应 / 字段名的权威定义在** [`shared/API-REFERENCE.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md)；**删除语义**在 [`shared/DELETE-CONTRACT.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md)；**数据模型**在 [`shared/DATA-MODEL.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)。

### D.1 hub `/api/v1` 端点契约（console 桩状态）

| 域 | 方法 & 路径 | console 桩 |
| --- | --- | --- |
| Org | `GET /orgs` | org.ts ✅ |
| Org | `GET /orgs/:id/service-tree` | org.ts ✅ |
| Catalog | `GET /service-trees/:treeId/services` | catalog.ts ✅ |
| Component | `GET /services/:serviceId/components` | component.ts ✅ |
| Config | `GET /components/:componentId/configs?environmentId=` | component.ts ✅ |
| Config | `PUT /components/:componentId/configs/:key` | component.ts ✅ |
| Config | `DELETE /components/:componentId/configs/:key` | component.ts ✅（G3 已修） |
| Target | `GET /targets` | target.ts ✅ |
| Environment | `GET /components/:componentId/environments` | environment.ts ✅ |
| Pipeline | `GET /components/:componentId/pipelines` | pipeline.ts ✅ |
| Pipeline | `POST /pipelines`、`GET/PUT/DELETE /pipelines/:id` | **后端已有**（N-4 已核对）；console 的新建/更新/删除入口见 §6.1 |
| Stage | `POST/GET/DELETE /pipelines/:id/stages` `/stages/:id` | pipeline.ts ✅ |
| Task | `POST/GET/PUT/DELETE /stages/:stageId/tasks` `/tasks/:id` | pipeline.ts ✅ |
| Run | `POST /pipelines/:id/runs` | run.ts ✅ |
| Run | `GET /pipelines/:id/runs` `/runs/:id` `/runs/:id/tasks` | run.ts ✅ |
| Run | `GET /runs`（全局列表，`page/pageSize/phase`） | **后端已有**（N-1）；运行中心运行视图的数据源 |
| Run | `GET /runs/:id/progress` | run.ts ✅ |
| Run | `GET /runs/:id/stage-progress` | run.ts ✅（后端按 `StageName` 聚合下发） |
| Run | `POST /runs/:id/redispatch`（全局路径【2026-10-08 核对】，hub `cmd/hub/main.go:548`；console `src/api/run.ts:113` 同步） | run.ts ✅ |
| Run | `POST /pipelines/:id/runs/:runId/tasks/:taskName/decision` | run.ts ✅（后端 `h.Approve` 已实现） |
| Artifact | `GET /components/:componentId/artifacts` `/artifacts/:id` `/download` `/DELETE` | artifact.ts ✅ |
| Permission | `GET /component-roles`（§7.9 角色选择器数据源）`POST/GET /components/:componentId/role-bindings` `/DELETE /role-bindings/:id` `GET /roles` | permission.ts ✅（**无 `GET /users`**【2026-09-23 核对】：hub 不存用户表（D3），主体取「绑定表派生 + 手输 `sub`」，见 ACCOUNT-PERMISSION-DECISIONS §3.5 (b′)） |
| Release | `GET /releases`、`POST/GET/PUT/DELETE /releases/:id` | **后端已有**（N-3，全局端点、非组件作用域）；发布视图数据源。**【2026-10-08 核对】`?scope=global&state=` 细粒度筛选已落地**（hub `run/service/release.go:32-55`：`state` 语义键 `all/running/paused/succeeded` → RolloutPhase，非法键 400；handler 校验 `scope` 仅 `global`）。「前端聚合 + 数据截断显式提示」为筛选落地前的历史过渡态描述 |
| Search | `GET /search?q=&type=&limit=` | **后端已有**（N-8，2026-09-22）；result = `[{type,id,name,path,keyword}]`，`type` ∈ `service,component,pipeline`（逗号分隔、缺省三类全搜） |

> **作废声明**：本表旧版曾写"后端无 `GET/POST/PUT/DELETE /pipelines/:id`（仅按组件列出）→ 流水线自身 CRUD 曾受 G1 影响"、"无 `PUT /stages/:id`（G6 已修）"、"无独立 Rollout 控制/日志读取端点（G4/G2 已修）"。**这些结论均已过期**：`/pipelines` 的 CRUD 已于 N-4 核对存在；G1–G6 全部关闭。

### D.2 三层数据模型

| 层 | 来源 | console 关注 |
| --- | --- | --- |
| 定义态 | `PipelineStage` + `PipelineTaskTemplate` | 编排器画法 / 子任务表单 |
| 运行态 | `PipelineRun` + `TaskRun` | DAG / 进度轮询 |
| 参数态 | `ComponentConfig` + `TriggerRequest.Params` | 参数管理 + 触发注入 |

### D.3 三态子任务表单（MOD-3，核心）

| 类型 | 含义 | 表单字段 |
| --- | --- | --- |
| **Build** | 命令型：工具镜像跑命令 | `image` + `command`([]string) + `args` + 可选 `scriptPath` + `produces`/`consumes` + `timeoutSeconds` + `retryPolicy` |
| **Release** | 声明式施加软件单元 | `releaseConfig.chart`(repoURL/name/version；【2026-10-08 更新】`chartUrl` 字段名已更正为 `repoURL`，对齐 runner ChartSource，见 `src/api/pipeline.ts:45` 与 附 G-12) + `releaseConfig.values` + `releaseConfig.manifest`；带 `rolloutConfig` 走金丝雀（**注意**：常被称作「发布目标」的那个目标是**运行级**参数、由触发时选定，**不是**任务级字段 —— 见 附 H.2） |
| **Approval** | 人工卡点 | `approvalConfig.allowedApprovers`（审批人）+ `requiredApprovals`（需几人通过）+ `timeoutSeconds`；原型字段名 `approvers` |

保存 = `POST /stages/:stageId/tasks`（新建）或 `PUT /tasks/:id`（更新）。

> **产品语言（2026-09-17 拍板）**：`Build` / `Release` / `Approval` 是**内部派发码**，不是用户可选分类。编辑器只显示「构建 / 运行任务」「发布任务」「人工审核阶段」，`type` 由配置**派生**（见 §7.4）。✅ **已落地（2026-09-22）**：派生规则在 `src/utils/pipeline.ts` 的 `deriveTaskType()`；派生信号取**真实落库**的 `releaseConfig`（chart / manifest）与 `approvalConfig.allowedApprovers` —— **不用**不存在的任务级「发布目标」（见 附 H.2）。

### D.4 编排请求体（console → hub）

编排完成「保存」时 console 生成的请求体结构（原型 `buildPipelineRequest()`；字段映射以 [`shared/API-REFERENCE.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) 为准）：

```
{ componentId, name, kind, description,
  stages: [ { name, sequence, executionMode,
              tasks: [ { type, name, displayOrder, image?, command?[], args?[], timeoutSeconds?, ... } ] } ] }
```

- 目标端点：已在 hub 的流水线 = `PUT /api/v1/pipelines/:id`（更新）；本次新建 = `POST /api/v1/pipelines`（创建）。
- **已知落差**：hub 的 `POST /pipelines` 是**扁平创建**（仅 `componentId`/`name`/`kind`/`description`），阶段/任务需经 `POST /pipelines/:id/stages` → `POST /stages/:id/tasks` 级联落库；console 侧发出完整 DAG，**由 console 展开为多次调用**。【待拍：是否新增"整 DAG 一次提交"端点】 ✅ **已按此实现（2026-09-22）**：见 **附 H.3**。

---

## 附 A 补充：2026-10-08 原型补齐轮新增/澄清（只追加，不改写上方 N-1–N-15 历史行）

> 背景：原型补齐轮（运行域闭环 + 平台管理，见 ui-05 §7.13 / ui-11 附 K）触发的依赖增补与端点记账。

| # | 项 | 类型 | 说明 |
| --- | --- | --- | --- |
| N-16 | 平台审计日志查询端点 | 【后端依赖】 | 原型「用户与权限」页新增平台审计日志表，覆盖：审批（decision）、运行取消（cancel）、手动执行（`POST /environments/:id/exec`，`target:exec` 逐条审计）、凭据轮转/创建、目标注册、组映射变更。建议 `GET /audit?who=&act=&page=`；写入面 hub 侧已具备，**统一查询端点是否存在待核对**，缺则登记为新端点 |
| N-17 | 通知聚合数据源 | 【待确认】 | 顶栏通知中心（待审批 / 失败运行 / 目标异常 + 未读角标）。**前端聚合可先行、零新端点**：待审批 = `GET /runs?phase=WaitingApproval`、失败 = `GET /runs?phase=Failed&createdAfter=`（N-1 时间窗已落地）、目标异常 = targets 心跳状态；独立 `GET /notifications` 仅在需要已读状态 / 跨设备同步时立项 |
| N-18 | 配置版本化层（整环境快照 + comment + 回滚） | 【后端依赖】 | 4.1 需求：配置按环境保存版本、版本列表/详情/回滚、保存接口收 `comment`。**现状**：`ComponentConfigHistory`（key 级 append log、secret 已脱敏 `<secret>`）已存在 → 缺"整环境 YAML 快照版本 + `comment` 字段 + 两版整配置 diff + 回滚生成新版本"。**决策 #2**：与 pipeline 定义版本（N-19 同表）共用 UI 层、分离数据层 |
| N-19 | 版本晋级 / 按版本回滚（跨环境） | 【后端依赖】 | 4.2 需求：版本实体与查询、晋级接口、按版本回滚、与制品/运行关联。**现状**：pipeline **定义**版本 `PipelineVersionService`(List/Compare/Rollback, append-only) 已存在；"发布版本跨环境晋级 / 部署状态徽章 / 指定版本回滚"净新增（`packageversion` 仅平台三版本部署常量矩阵，不可晋级）。**决策 #2/#7**：版本视图复用 N-18 的版本抽屉 UI；回滚后发布状态置 `rolled_back`（见 N-23） |
| N-20 | 整 spec 提交端点 `PUT /pipelines/:id/spec` | 【后端依赖】 | 4.3 需求（**决策 #3**）：编排 + 触发器 + 变量 + 设置 四分区原子提交，错误按分区/字段分组返回（如 `{triggers:[...], dag:[...]}`）。**现状**：hub 已有 pipeline 更新路径，但四 Tab 拆多次 PUT 易产生"触发器已存、DAG 没存"中间态；新增整提交端点降低竞态 |
| N-21 | 触发器 CRUD / Webhook 签名 / 调度 / 并发策略 | 【后端依赖】 | 4.3 需求：多类型触发器（手动/Git 事件/cron/上游完成/Webhook）、Webhook 签名与轮换、调度器、并发策略字段（排队/取消旧运行/拒绝新运行）。**现状**：`TriggerRequest` 仅为手动运行输入体，无类型/调度/签名/并发策略 |
| N-22 | 审计 `reason` / `ticket` 字段 + 组件级入口 | 【后端依赖】 | 4.4 / 5.4 需求：审计新增结构化 `reason`/`ticket`、前后差异、服务端筛选分页、`component:manage` 组件级审计入口。**现状**：`GET /audit-logs` 六维 filter + 分页已存在（N-16 已核对）；缺 `reason`/`ticket` 过滤（依赖本项）与组件级作用域 |
| N-23 | `RolloutPhase` 补 `Failed` / `RolledBack` 终态 | 【后端依赖】 | 4.5 需求（**决策 #7**）：发布状态独立为 进行中/已暂停/成功/失败/**已回滚**。**重要更正**：`Environment.Status` 后端已是 4 值枚举（`unconfigured/configured_unverified/verified/failed`），计划的"paused 混用"在后端模型层已不成立；真正缺口在 `RolloutPhase` 缺 `Failed`/`RolledBack` 终态 |
| N-24 | 审批策略实体 + `assignee` + 变更窗口 | 【后端依赖】 | 5.1 需求（**决策 #4**）：审批策略（环境级默认 + 组件级覆盖）、`assignee=me` 过滤、超时调度、转交、变更窗口。**现状**：`PipelineApproval`(run/component/org 三级作用域, Pending/Approved/Rejected/Cancelled) 已存在；缺 `Assignee` 字段（无法 `assignee=me`）、策略配置实体、审批中心后端、变更窗口。配置动作需 net-new `approval:configure`（见 N-32） |
| N-25 | 通知订阅规则 / 渠道适配 / 静默 | 【后端依赖】 | 5.2 需求（**决策 #5**）：事件总线、订阅规则存储、渠道适配（站内+Webhook+邮件首批；企业 IM 作适配器插件）、已读状态、静默时段。**现状**：`GET /notifications` + `POST /notifications/read-mark` 已存在（N-17）；缺订阅规则/渠道/静默 |
| N-26 | 普通变量 / 共享变量组实体 | 【后端依赖】 | 5.3 需求（**决策 #6**）：普通变量、共享变量组（首批 Service 级，Org 级延迟强管控）、运行时参数声明、日志脱敏规则。**现状**：`credentials/` 全 CRUD + AES-GCM + 不回明文已存在（密钥底座）；缺普通变量/变量组/运行时参数声明 |
| N-27 | 运行级 SSE 包装 / 续跑 / 批量逐对象 | 【后端依赖】 | 5.5 需求：流式日志（运行级 SSE 包装）、进度指示、失败点续跑、批量终止/重跑逐对象返回。**现状**：`TaskRunLog` 持久化 + 查询端点、`run_control` 批量终止/重跑已存在；agent_op 有 SSE 基础设施；缺运行级 SSE 包装/续跑/批量逐对象结果 |
| N-28 | 服务树治理属性（owner/tags/lifecycle/dependency） | 【后端依赖】 | 6.1 需求：节点 owner/描述/标签/生命周期（活跃/冻结/废弃）、组件依赖图与被谁依赖。**现状**：org/component CRUD 基础在；缺治理属性模型与依赖关系 |
| N-29 | 制品签名 / SBOM / 漏洞扫描 / 跨组件检索 | 【后端依赖】 | 6.2 需求：制品校验和/签名状态/SBOM/漏洞扫描、跨组件检索、被使用环境。**现状**：`Artifact`(checksum/ExpiresAt/CleanupState) 已存在；缺签名/SBOM/扫描/跨组件检索/被使用环境。**决策 #1**：制品表预留 nullable `tenant_id`/`external_ref`（外部分发耦合保险，不实现逻辑） |
| N-30 | Runner 容量队列 / 配额用量 / 全局策略 / 公告 | 【后端依赖】 | 6.3 需求：Runner 视图（版本/在线数/并发容量/排队数/升级结果 + 批量升级回退）、配额用量（按 Org 运行次数/存储/Runner 时长）、全局默认策略、系统公告、平台健康。**现状**：agent_op(Runner 升级/版本/队列) + metrics/keycloak 在；缺聚合视图/配额用量/全局策略/公告端点 |
| N-31 | PAT 实体（用户级，复用 `user:manage`） | 【后端依赖】 | 6.4 需求：个人访问令牌（范围/有效期、创建/列表/吊销、明文仅展示一次、写审计）。**现状**：净新增实体；权限上复用 `user:manage`（自身范围），不引入新组件级动作 |
| N-32 | 权限词表扩展：`notification:read`/`configure`、`approval:configure` | 【后端依赖】 | 前端补全计划引入的新动作（5.1/5.2），不在 hub §7 词表内：建议新增 `notification:read`/`notification:configure`（通知读取与配置）、`approval:configure`（审批策略配置，或复用 `component:manage`/`org:manage`，待 N-24 冻结时拍板）。其余工作项均复用既有 `component:*`/`pipeline:*`/`config:*`/`artifact:*`/`page:*`/`org:manage`/`user:manage` |
| N-33 | 组件可部署版本列表 `GET /components/:id/versions` | 【后端依赖】 | 4.2「指定版本回滚」目标来源：组件全部可部署版本（新→旧；版本号 / 构建时间 / 大小 / SHA256）。**核对结论**：`packageversion` 端点是平台自身三版本（ConfigMap 常量，不可晋级，N-19 已述），组件级版本矩阵净新增。回滚语义 = append 新 release 记录（`ver`=目标版本），与 `PipelineVersionService`（定义版本 append-only）同构不同体：前者制品/部署版本，后者结构快照。console 原型已按 mock 落地（`RELEASE_VERSIONS`），hub 侧待立项 |

> **2026-10-11 补记（前端设计补全计划）**：N-18–N-32 由原三份后端契约文档（2026-10-11，已并入 ui-12 后删除）逐条核对 hub 源码后抽取；多数 P0/P1 后端底座已存在（credentials AES-GCM、`PipelineApproval`、`PipelineVersionService`、`TaskRunLog`、agent_op SSE、`Artifact` 等），净新增集中在触发器/版本晋级/审批策略/通知订阅/变量组/制品扫描/Runner 视图/PAT。决策挂钩见 `CONSOLE-DECISIONS-STEELMAN-2026-10-11.md`（#1–#7）。

**D.1 补记（不改上方 D.1 表历史行）**：Run 域取消桩在 D.1 表中缺登记，本轮补记——`POST /runs/:id/cancel`（console `src/api/run.ts:149-150`；hub 侧取消运行中流水线已落地，语义 = 停掉 Pending/Running/WaitingApproval 的 run）。审批决策（`run.ts:124`）与单任务重跑（`run.ts:112` redispatch）上表已列。**原型 2026-10-08 补齐轮的 终止 / 审批 / 仅失败任务重跑 三个动作，实现版直接消费以上既有桩，无新后端依赖**。

---
