> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · 附 A 后端依赖与待确认 + 附 D API 契约与三层数据模型
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 附 A：后端依赖与待确认

| # | 项 | 类型 | 说明 |
| --- | --- | --- | --- |
| N-1 | 全局运行聚合端点 | **已落地** | `GET /runs` 已存在（hub `cmd/hub/main.go` 的 `scoped.GET("/runs", pipelineRunHandler.ListAll)`，service/repo 按 `created_at desc` 排序，支持 `page/pageSize/phase` 精确匹配）。仍未支持 `assignee`（N-2）与时间窗过滤 |
| N-2 | 待我审批端点 | 【后端依赖】 | 建议 `GET /runs?filter=awaiting_me` 或在 N-1 内加 `assignee=me&phase=WaitingApproval`。当前只能筛到 `phase=WaitingApproval`（"待我"这层身份过滤未实现）——**因此运行视图的「待我审批」筛选项目前名不符实** |
| N-3 | 跨组件发布列表 + 全局流水线端点 | **部分落地 / 部分消解** | hub 现已暴露全局 `GET /pipelines`（列表）与完整 `/releases` CRUD（`POST`/`GET`/`GET/:id`/`PUT`/`DELETE`）。**v4.4 后"全局流水线列表"不再有消费面**（流水线列表归组件「交付」）；发布视图在**设计层面**可直接走后端全局端点，不再依赖前端聚合兜底（**实现版仍走扫描 + kind 聚合** —— console 侧尚无 `releaseApi` 封装，见 附 B B.10「刻意不做」①）。另：**「已暂停」筛选需要 `GET /releases?scope=global&state=paused`**（`Paused` 属 Rollout 任务级状态，见 §7.6），未提供前实现版需逐 run 拉 tasks（N+1） |
| N-4 | `/pipelines` CRUD 端点存在性 | **已核对（2026-09-15）后端有** | `internal/pipeline/handler/pipeline.go` 显式注册了 `POST /pipelines`、`GET/PUT/DELETE /pipelines/:id`、`GET /components/:id/pipelines`（注释里写明"exposes the pipeline CRUD surface consumed by the console's createCrud('/pipelines')"）。**旧文 附 A.1「后端无 GET/POST/PUT/DELETE `/pipelines/:id`」的说法作废** |
| N-5 | 流水线删除语义 + 级联校验契约 | 【待确认 + 后端依赖】 | 行为契约（残留判定 + `409 + {reasons}` 规格 + 实现态）已迁出至 [`hub/DELETE-CONTRACT.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DELETE-CONTRACT.md) §2，与服务树删除同模式（附 C / N-15）；前端零判断、只渲染 verdict。原型 `delPipeline` 已改为后端 verdict 模式（见 §6.1 D1 / §7.4） |
| N-6 | 流水线 `version` 递增策略 | 【待确认】 | 更新后是否 `version+1`；无历史表时仅作展示 |
| N-7 | 编排 `kind` 限制 | 【待确认】 | 现编辑器仅 `kind==='build'` 可编排；release/custom 是否放开 |
| N-8 | 全局搜索端点 | ✅ **已落地（2026-09-22）** | 建议 `GET /search?q=&type=component,pipeline,service&limit=20`，返回 `{type,name,path,id}`。**R-7 全局搜索依赖此端点**；无则退化为前端在已加载资源内搜索（不覆盖未展开的深层节点）。**2026-09-22 现状**：console 走的正是这条降级路径 —— `useResourceMap.buildResourceIndex()` 一次遍历服务树摊平 Service/组件/流水线建索引，`utils/search.ts` 客户端打分排序；已能跨层直达（不依赖树展开），代价是索引在**首次 ⌘K 时**全量拉取（M1 百级请求可接受，且启动 0 次树请求的 S5 不变量不受影响）。落地记录见 附 G。**2026-09-22 落地**：hub 侧新增 `GET /search`（`internal/search`：三类各取 `limit` 条、`ILIKE` + LIKE 元字符转义、精确命中 > 前缀 > 包含 的排序；响应 `[{type,id,name,path,keyword}]`）。console 的 ⌘K 改为**服务端优先、客户端索引兜底**，降级时浮层明示（不静默）；客户端索引保留为空查询的"头部视图"来源（§5.3 要求）。见 附 I |
| N-9 | 树分层懒加载端点 | ✅ **已落地（2026-09-22）** | 建议的三条全部存在：`GET /orgs`（已有）、`GET /orgs/:id/services`（**本次新增**，`internal/catalog`；一次把组织 id 解析成 1:1 服务树再列直接子层，替前端省掉一跳）、`GET /services/:id/components`（已有）。懒加载按此落地，S5 的"分层请求"成立；服务树页展开组织 = 1 次请求、展开服务 = 1 次请求，挂载 = 2 次（组织 + 首个组织的服务），不再随服务数线性膨胀。见 附 I |
| ~~N-10~~ | ~~「最近访问」持久化~~ | **已废（v4）** | 该分组已从左栏删除，无需持久化方案 |
| N-11 | 两个搜索入口是否合并 | 【待确认】 | 服务树页内搜索（就地定位，含未展开的深层节点）与顶栏 ⌘K（跨页跳转）是否重叠。选项：① 保留分工（当前）② 页内搜索降级为"仅过滤已加载节点"，统一由 ⌘K 承担跨层搜索 ③ 去掉页内搜索 |
| N-12 | 目标 KPI 与接入管理页的关系 | 【待确认】 | Dashboard「在线目标 3/4」是否直接复用 `/admin/targets` 的聚合（避免两处口径不一致） |
| N-13 | 运行中心视图的路由形态 | **已裁决（A）** | 取 `?view=runs\|releases`（query），**不**用嵌套子路由。双向钢人论证 + 5 条硬约束见 **附 B**。**真实 console 已于 2026-09-19 同步为两视图**（`src/constants/runCenter.ts` + `router` redirect + `pnpm test:runcenter` 断言 + §10.2 用例一次原子改，落地记录见 附 B B.10） |
| N-14 | 全局视图的状态筛选是否需要后端参数 | **部分落地** | 运行视图的 `phase` 已下推服务端（`GET /runs?phase=`）；发布视图因走前端聚合，筛选只能在已拉取的窗口内生效——数据被截断时表格上方会显式提示"按最近 N 条运行聚合，全局聚合端点待补"，不静默给错数字 |
| N-15 | 服务树节点删除的级联校验端点 | 【后端依赖】**未落地** | hub 端点的**行为契约（级联规则 + `409 + {reasons}` 规格 + 实现态）已迁出至 [`hub/DELETE-CONTRACT.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DELETE-CONTRACT.md) §1**；console 侧仅负责"强确认 → `DELETE` → 渲染 409 verdict"，论证与契约见 **附 C**。清理顺序提示：组件 → 流水线/环境 → 服务 → 组件 … → Org |

---

## 附 D：API 契约与三层数据模型（console 侧事实来源）

> **边界**：本附录只保留 **console 侧的消费状态**（哪个桩接了哪个端点）。**请求体 / 响应 / 字段名的权威定义在** [`hub/API-REFERENCE.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/API-REFERENCE.md)；**删除语义**在 [`hub/DELETE-CONTRACT.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DELETE-CONTRACT.md)；**数据模型**在 [`hub/DATA-MODEL.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)。

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
| Pipeline | `POST /pipelines`、`GET/PUT/DELETE /pipelines/:id` | **后端已有**（N-4 已核对）；console 的新建/更新/删除入口见 §6.1（新增 UI） |
| Stage | `POST/GET/DELETE /pipelines/:id/stages` `/stages/:id` | pipeline.ts ✅ |
| Task | `POST/GET/PUT/DELETE /stages/:stageId/tasks` `/tasks/:id` | pipeline.ts ✅ |
| Run | `POST /pipelines/:id/runs` | run.ts ✅ |
| Run | `GET /pipelines/:id/runs` `/runs/:id` `/runs/:id/tasks` | run.ts ✅ |
| Run | `GET /runs`（全局列表，`page/pageSize/phase`） | **后端已有**（N-1）；运行中心运行视图的数据源 |
| Run | `GET /runs/:id/progress` | run.ts ✅ |
| Run | `GET /runs/:id/stage-progress` | run.ts ✅（后端按 `StageName` 聚合下发） |
| Run | `POST /pipelines/:id/runs/:id/redispatch` | run.ts ✅ |
| Run | `POST /pipelines/:id/runs/:runId/tasks/:taskName/decision` | run.ts ✅（后端 `h.Approve` 已实现） |
| Artifact | `GET /components/:componentId/artifacts` `/artifacts/:id` `/download` `/DELETE` | artifact.ts ✅ |
| Permission | `GET /component-roles`（§7.9 角色选择器数据源）`POST/GET /components/:componentId/role-bindings` `/DELETE /role-bindings/:id` `GET /roles` | permission.ts ✅（2026-09-23 **去掉 `GET /users`**：hub 不存用户表（D3），主体改为「绑定表派生 + 手输 `sub`」，见 ACCOUNT-PERMISSION-DECISIONS §3.5 (b′)） |
| Release | `GET /releases`、`POST/GET/PUT/DELETE /releases/:id` | **后端已有**（N-3，全局端点、非组件作用域）；发布视图数据源。`?scope=global&state=paused` 细粒度筛选尚未加（`internal/run/handler/release.go` 仅基础 CRUD + 列表）；console 侧以「前端聚合 + 数据截断显式提示」过渡，不静默给错数字 |
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
| **Release** | 声明式施加软件单元 | `releaseConfig.chart`(repo/name/version 或 chartUrl) + `releaseConfig.values` + `releaseConfig.manifest`；带 `rolloutConfig` 走金丝雀（**注意**：常被称作「发布目标」的那个目标是**运行级**参数、由触发时选定，**不是**任务级字段 —— 见 附 H.2） |
| **Approval** | 人工卡点 | `approvalConfig.allowedApprovers`（审批人）+ `requiredApprovals`（需几人通过）+ `timeoutSeconds`；原型字段名 `approvers` |

保存 = `POST /stages/:stageId/tasks`（新建）或 `PUT /tasks/:id`（更新）。

> **产品语言（2026-09-17 拍板）**：`Build` / `Release` / `Approval` 是**内部派发码**，不是用户可选分类。编辑器只显示「构建 / 运行任务」「发布任务」「人工审核阶段」，`type` 由配置**派生**（见 §7.4）。✅ **已落地（2026-09-22）**：派生规则在 `src/utils/pipeline.ts` 的 `deriveTaskType()`；派生信号取**真实落库**的 `releaseConfig`（chart / manifest）与 `approvalConfig.allowedApprovers` —— **不用**不存在的任务级「发布目标」（见 附 H.2）。

### D.4 编排请求体（console → hub）

编排完成「保存」时 console 生成的请求体结构（原型 `buildPipelineRequest()`；字段映射以 [`hub/API-REFERENCE.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/API-REFERENCE.md) 为准）：

```
{ componentId, name, kind, description,
  stages: [ { name, sequence, executionMode,
              tasks: [ { type, name, displayOrder, image?, command?[], args?[], timeoutSeconds?, ... } ] } ] }
```

- 目标端点：已在 hub 的流水线 = `PUT /api/v1/pipelines/:id`（更新）；本次新建 = `POST /api/v1/pipelines`（创建）。
- **已知落差**：hub 的 `POST /pipelines` 是**扁平创建**（仅 `componentId`/`name`/`kind`/`description`），阶段/任务需经 `POST /pipelines/:id/stages` → `POST /stages/:id/tasks` 级联落库；console 侧发出完整 DAG，**由 console 展开为多次调用**。【待拍：是否新增"整 DAG 一次提交"端点】 ✅ **已按此实现（2026-09-22）**：见 **附 H.3**。

---
