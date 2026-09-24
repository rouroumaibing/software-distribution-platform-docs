> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · §6 核心任务流程
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 6. 核心任务流程

### 6.0 执行模型（已确认）

- **阶段（Stage）串行**：流水线由有序阶段组成，按 `sequence` 从前到后逐阶段执行；前一阶段全部子任务完成（成功/跳过）才解锁下一阶段。
- **阶段内子任务按 `executionMode` 串行/并行**（**`ExecutionMode` 已确认放在 Stage 级**，一个阶段统一一种模式）：
  - `Parallel`（默认）：阶段内子任务并发启动，互不等待；
  - `Serial`（✅ **调度已落地（2026-09-23，C-06）**）：hub `buildSpec` 在同阶段子任务间按序推导「紧邻前驱」`DependsOn` 链，严格先后（调用方手写 `DependsOn` 优先）；runner `serialBlocked()` 消费；
  - **阶段完成条件**：该阶段所有子任务 `Succeeded` 或 `Skipped` 即视为完成；任一 `Failed` 且不可重试 → 阶段失败，下游不调度（DAG `Skipped`）。
- **数据与执行解耦（推送模型，已确认）**：触发 `POST /pipelines/:id/runs` 时 hub 先把"任务落实到数据库"（`pipeline_runs` + 按 DAG 种子的 `task_runs` + `dispatch_jobs`），再把整份已解析 spec 经 WebSocket **推送**给目标环境 runner；runner 在集群内建 CRD 执行，**不直连 hub DB**，状态经 WS `status_update` 流回 hub 写回 `task_runs`。详见 [hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) §6 / [runner STORY](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) §4.3。
- **原型对应**：编排页阶段卡可前后移动（重排 `sequence`）、阶段内子任务可上下移动（重排 `displayOrder`）、阶段头 `executionMode` 一键在 并行/串行 间切换（原静态「并行 ▾」已改为可点击切换）。

### 6.1 流水线 CRUD 全流程（P5，本次重设计重点）

> **删除逻辑统一原则（v4.3 / v4.5）**：**所有删除操作（服务树节点 + 流水线）判定权威唯一在后端**，前端只触发 `DELETE` + 渲染后端 `409 + {reasons}` verdict，不持有任何数据判断逻辑。级联校验在 `DELETE` 事务内原子完成。服务树见 附 C / N-15；流水线见本节 D1 与 N-5。

**正向主干**

| 步骤 | 操作 | 端点 | 状态 |
| --- | --- | --- | --- |
| C1 新建 | 组件「交付→流水线」→ **＋ 新建流水线** → 表单（名称 / 类型 build·release·custom / 描述 / 关联组件）→ 保存并编排 | `POST /pipelines` | ✅ **已落地（2026-09-22，见 附 H）**：原型已实现，且**组件上下文锁定**：对话框里"所属组件"只读，`componentId` 直接取当前组件 uuid，不存在跨组件选择 |
| C2 编排 | 进入编辑器 → 加阶段（名称+`executionMode`）→ 加子任务（填发布配置 / 审批人 / 命令） | `POST /pipelines/:id/stages`、`POST /stages/:id/tasks` | ✅ 已落地（2026-09-22） |
| C3 触发 | 编辑器/详情 → 触发对话框（选目标 + 本次 params） | `POST /pipelines/:id/runs` | 已有 |
| C4 提交 | 编排完成「保存」→ 弹出**请求体预览**（JSON / YAML 可切换）→ 发送到 hub | `PUT /pipelines/:id`（已存在）或 `POST /pipelines`（新建） | ✅ **已落地（2026-09-22）**：保存前弹 JSON / YAML 双视图，并**如实标注实际调用序列**（hub 无整 DAG 端点，见 附 H.3） |
| E1 编辑元信息 | 详情头部「编辑」→ 改名称/描述 → 保存 | `PUT /pipelines/:id` | ✅ **已落地（2026-09-22）** |
| E2 编辑结构 | 加阶段/任务、改任务、删阶段/任务 | `POST/PUT/DELETE`（stage/task） | ✅ **已落地（2026-09-22）**：**已放开 `kind` 限制**，三种取值均可编排 |
| D1 删除 | 列表行内/头部「删除」→ **强确认（输入名称）→ `DELETE` → 后端级联校验**；有残留（进行中 / 待审批运行）则 `409 + {reasons}`，前端渲染"无法删除"弹窗——**前端不预先计算影响面**（判定权威唯一在后端，与服务树删除同原则，见 附 C / N-15） | `DELETE /pipelines/:id` | ✅ **已落地（2026-09-22）**：前端强确认 + 渲染 verdict；后端级联校验见 `hub/DELETE-CONTRACT.md` §4 |

**异常分支（前端只渲染后端 verdict — 与 v4.3 服务树删除同一契约，见 附 C）**

| 异常 | 触发 | 后端行为（DELETE 事务内判定） | 前端渲染 |
| --- | --- | --- | --- |
| 删除有运行中的实例 | 流水线有 `Running` 的 run | `409 + {reasons:["N 条运行进行中，请先终止"]}`【待确认：是否允许级联终止】 | 渲染 reasons 进"无法删除"弹窗；不灰显、不预拦截 |
| 删除有待审批运行 | 流水线有 `WaitingApproval` 的 run | 同上一行（原型 `mockDeletePipeline` 把 `running` 与 `waiting` 都算作阻塞） | 渲染 reasons |
| 删除有历史运行 | 存在已完成 run | 允许删除；**历史运行不被删除，仅解除编排关联，运行日志保留** | 成功 toast + 列表移除 |
| 并发编辑冲突 | 两人同时改同一流水线 | 保存时按 `updatedAt`/`version` 比对，冲突 → 行内警告"内容已被他人更新" | 刷新后再改 |
| 保存校验失败 | 阶段无任务 / 任务必填缺失 / Release 无 chart 且无 manifest | 行内错误定位到具体阶段/任务，不阻断其他编辑 | 修正后重存 |
| 无权限 | 缺 `pipeline:*` | 按钮禁用 + hover 提示所需权限（见 §7.9） | 申请 role-binding |

**关键策略**（2026-09-22 已定）：删除语义 = **软删 + 保留历史运行**；**进行中 / 待审批运行一律拒绝删除，不级联终止**；`version` 随结构更新 +1。权威契约见 `hub/DELETE-CONTRACT.md` §4。

### 6.2 异常分支（子任务 → 阶段 → 运行 三级）

| 异常 | 触发 | 子任务级 | 阶段级 | 运行级 | 用户操作入口 |
| --- | --- | --- | --- | --- | --- |
| 任务失败可重试 | 命令非零退出 / Pod OOM | `retryPolicy` 自动重试（≤N 次退避），超次置 `Failed` | 阶段标 `Failed`，下游 `Skipped` | `Failed` | 运行监控→失败节点「查看日志 / 重新投递(redispatch)」 |
| 任务终态失败 | 重试耗尽 / 硬错误 | `Failed` | 阶段 `Failed` | `Failed`；可整跑重投或单阶段重跑 | redispatch / 跳到失败阶段重跑 |
| 上游失败跳过 | 依赖任务 `Failed` | 未调度，`Skipped` | — | — | 查看 DAG 跳过关系 |
| 超时 | `timeoutSeconds` 到 | `Failed(Timeout)` | 阶段 `Failed` | `Failed` | 调大超时后重投 |
| 权限不足 | §7 Enforcement 未授权 / 生产环境无审批权限 | 触发即拒或运行中拒 | — | `Failed(PermissionDenied)` | 申请 role-binding / 走审批（见 §1.2、§7.9） |
| 回滚 | 灰度健康度不达标 / 手动 | — | Release 阶段可回滚 | `Succeeded` 后走回滚流程 | 灰度步骤器「回滚」 |
| 审批拒绝 | 审批人 `Rejected` | Approval 任务 `Failed` | 阶段 `Failed` | `Failed` | 修正后重跑该 Approval 阶段 |

> 权限相关分支已由 **§7 Enforcement**（P3a 落地）实现：生产环境强制审批 + 组件级 role-bindings + 防自审，详见 [hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)。
> 流水线**删除**类异常（新，v4.5）见 §6.1 的异常分支表。

### 6.3 用户旅程（正向主干）

1. **配置参数**：组件详情 → 配置 Tab → 增/改/删 ComponentConfig（key/value/isSecret/来源/环境）。
2. **编排流水线**：服务树→组件→交付→流水线 → 编排器阶段组横向流；加阶段时设 `executionMode`（串行/并行开关），加子任务。
3. **触发运行**：编排器 / 组件详情 → 触发对话框（选目标 + 注入本次 params，可预填参数管理 key）→ `POST /pipelines/:id/runs`。
4. **监控运行**：运行中心 / 下钻 → 运行监控（顶部**阶段进展条** + 子任务网格 + DAG + 进度轮询 2~3s + 重新投递 + 日志面板）。
5. **审批卡点**：轮询发现 task `phase==WaitingApproval` → 审批卡 → `POST .../decision`。
6. **灰度控制**：发布视图 → 灰度（步骤器 + 健康指标 + 暂停/晋升/回滚，经 G4 端点）。
7. **看日志 / 下制品**：日志面板（`GET /runs/:id/tasks/:name/log`）+ 制品库（签名 URL 直连）。

**关键数据链路**：参数管理（预置变量库）→ 触发参数（本次值）→ hub dispatch 前替换进任务 command/args/env。

### 6.4 总览求助流（P2）

Dashboard「待办」区三段，每段一个 CTA（深链形态与 §7.6 的视图 URL 契约一致）：

1. **待我审批** `n` → `/runs?view=runs&filter=waiting`（"待我"这层身份过滤需附 A N-2 的 `assignee=me`，未落地前退化为全部待审批）；
2. **失败运行** `n`（近 24h）→ `/runs?view=runs&filter=failed`（近 24h 这个时间窗需 N-1 端点加参数）；
3. **暂停的灰度** `n` → `/runs?view=releases&filter=paused`（原型 `todoCard` 的 `data-nav="runs" data-run-tab="releases"`；**注意**：`paused` 这个发布筛选的后端支持见 §7.6 与附 A N-3）。

> 原型实测：三张待办卡、KPI 四张（今日运行 / 成功率 / 运行中 / 在线目标，其中"在线目标"可点直达接入管理页）、「最近运行」表 3 行（列：流水线 / 流水线ID / 组件 / 触发人 / 状态 / 耗时 / 开始时间）+「查看全部 42 条 →」。

---
