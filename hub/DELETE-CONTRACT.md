# 删除契约：级联校验 + 409 verdict（hub API 行为契约）

> 本文档是 hub 侧删除端点的**权威实现契约**，由 console `CONSOLE-UI-DESIGN.md` 附 A（N-15 / N-5）与 附 C 中"hub 实现细节"迁出归位而来（2026-09-16，按"对应内容放对应 docs 文件"整理）。
> console 文档保留**前后端分工决策（附 C）**与 **UX 行为**，本文档保留 **hub 端点的行为规格**——单一真相源在 hub。

## 0. 总则（与 console 决策一致）

- **判定权威唯一在后端**：前端只触发 `DELETE` + 渲染 `409 + {reasons}` verdict，不持有任何数据判断。
- 级联校验在 `DELETE` 事务内**原子**完成。
- 适用端点：`DELETE /services/:id`（服务树中的服务节点）、`DELETE /components/:id`（组件叶子）、`DELETE /pipelines/:id`（流水线）。
  > ⚠️ 旧文写 `DELETE /api/servicetree/:id`，但现 hub **无该路由**：服务树在现模型 = Org 1:1 树 + `services` 子资源 + `components` 叶子（见 `hub/API-REFERENCE.md` §3/§4）。节点删除落到 `services`/`components` 资源，不再有独立的 servicetree 删除端点。

## 1. 服务树节点删除（N-15）

> 现模型中"服务树节点"∈ {Service, Component}：Service 节点 = `DELETE /services/:id`；Component 叶子 = `DELETE /components/:id`。两者沿用同一 409 级联 verdict 模式。

### 1.1 级联规则（递归）
1. **组件（Component）**：其下流水线（pipeline）+ 环境/发布（release/env）必须清零；
2. **服务（Service）**：其下 Component 必须全部清零（每个 Component 再走规则 1）；
3. **Org**：其下 Service 必须清零；
4. 任一环节有残留即收集 reasons 并拒绝。

清理顺序提示（给用户）：组件 → 流水线/环境 → 服务 → … → Org。

> ⚠️ **本节"有下级即拒绝"策略已由 §6.4 修正（2026-09-16）**：域内改为**级联软删**，仅对"**活跃运行**"拒绝。§1.1 保留为原始契约记述，实现请以 §6.4 为准。

### 1.2 响应规格
| 情况 | 状态码 | body |
| --- | --- | --- |
| 成功 | `200` / `204` | 节点及其子树移除 |
| 级联不满足 | `409` | `{ "reasons": [ "platform-eng / svc-a / comp-web：2 条流水线、1 个环境未清理", … ] }`（`reasons` 为逐层、含路径的未清理清单，层级从最深层向上收集） |

### 1.3 实现态（2026-09-22 更新，source-grounded 核对 hub 代码）
- `DELETE /services/:id` —— `internal/catalog/service/service.go` `ServiceService.Delete`：✅ **已落地**。经窄接口 `ActiveRunCounter.CountActiveByService`（下钻 component → pipeline → run）计数，有活跃 phase → `409 + {reasons}`；否则软删。**不**对"有下级 component"拒绝（§6.4 结论 2：改为级联软删；本轮只做"活跃运行"这条硬规则）。
- `DELETE /components/:id` —— `internal/component/service/component.go` `ComponentService.Delete`：✅ **已落地**。同上，经 `CountActiveByComponent` 计数；有活跃运行 → `409 + {reasons}`；否则软删（`Base.DeletedAt`）。
- `DELETE /environments/:id` —— `internal/environment/service/environment.go` `EnvironmentService.Delete`：✅ **已落地（审计式，非拒绝）**。删前统计该环境的配置覆盖条数并写审计告警，随后硬删（§6.4 #8）；其审计历史行因 FK 已摘（B-14）而存活。
- **部分落地（2026-09-23 更新）**：§6.4 的"域内级联软删"中 **service→component 段已实现并真集群验证**——`ServiceService.Delete` 在同一事务内级联软删下级 component、硬删 `component_role_bindings`（实测 DB 侧两表 `deleted_at` 时间戳一致、bindings 零残留）；缺陷登记与后续范围（org→service、制品/对象处理）见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §16.3。
- **事务性缺口（§4.2 步骤 5）未做**：校验与删除目前不在同一事务，并发插入理论上可绕过校验。
- 前端 `delDetail` 仍调 `mockDeleteNode`（后端模拟占位），待切换真端点（把 409 body 的 `reasons` 直接渲染进"无法删除"弹窗）。

## 2. 流水线删除 `DELETE /pipelines/:id`（N-5）

### 2.1 契约
- 与服务树删除**同一模式**（附 C / N-15）：在事务内判定，有残留即 `409 + {reasons:[...]}`；前端零判断、只渲染 verdict。
- 残留判定：该流水线仍有**进行中 / 待审批**的运行（`phase` ∈ {running, waiting}）→ 拒绝并 reasons 列出；历史运行（succeeded/failed）**不阻塞删除**，仅解除编排关联，运行日志保留。
- 待确认项：硬删 / 软删 / 保留历史运行；进行中运行能否级联终止。

### 2.2 响应规格
| 情况 | 状态码 | body |
| --- | --- | --- |
| 成功 | `200` / `204` | 流水线定义移除（历史运行日志保留） |
| 有进行中/待审批运行 | `409` | `{ "reasons": [ "1 条运行仍在进行（运行中），需先终止后再删除", … ] }` |

### 2.3 实现态（2026-09-22 更新，source-grounded）
- ✅ **已落地且语义已对齐**：`internal/pipeline/service/pipeline.go` `PipelineService.Delete` 改用 `runRepo.CountActiveByPipeline(id, activePhases)`，`activePhases = {Pending, Running, WaitingApproval}`；有活跃 → `common.DomainErrorWithReasons(KindPipeline, http.StatusConflict, 1, …)`，历史运行（Succeeded/Failed/Cancelled）**放行**（不再调用 `CountByPipeline`）。
- ✅ **409 body 已带 `reasons[]`**：`internal/common/errors.go` 的 `APIError` 增 `Reasons []string`（json `reasons,omitempty`）与构造器 `DomainErrorWithReasons`；`internal/common/response.go` 的 `Envelope` 同增字段，`AbortWithError` / `Fail` 两条序列化路径都已带上。
- 单测 `internal/pipeline/service/pipeline_delete_test.go`：活跃 → 409 且**不碰 repo**；仅 42 条历史 → 放行，并断言**不再调用** `CountByPipeline`（钉住"任意历史即拒"的旧语义不会回归）。
- 原型 `delPipeline` 待切真端点（同 §1.3 的前端项）。

## 3. 验证 gate
| 层 | 断言 | 通过判据 |
| --- | --- | --- |
| 原型（已落地） | `mockDeleteNode(id)` / `mockDeletePipeline(name)` 覆盖有/无残留 | 已清 → `{ok:true}`；有残留 → `{ok:false, reasons:[...]}` 且 reasons 层级正确 |
| 后端（N-15 未落地） | `DELETE /services/:id` / `DELETE /components/:id` 对残留节点 | `409` + `{reasons}` 层级正确、覆盖最深层未清理项；清空后 `204` |
| 后端（N-5 部分落地） | `DELETE /pipelines/:id` 对有 running/waiting 运行的流水线 | `409` + `{reasons}` 列出进行中/待审批；**仅有历史运行时应放行（204）** |
| 事务 | 校验与删除同事务 | 并发插入不会绕过校验（同事务内二次校验 / 唯一约束兜底） |

## 4. 后端实现计划（hub，未落地 → 落地）

> 本节为**实施计划**（source-grounded，2026-09-16 核对 `software-distribution-platform-hub`）。目的是把 §1/§2 契约从"前端模拟"落到 hub 真实端点。

### 4.1 现状差距

| 端点 | 代码位置 | 现状 | 与契约差距 |
| --- | --- | --- | --- |
| `DELETE /services/:id` | `internal/catalog/service/service.go` | ✅ `CountActiveByService` → 活跃运行 `409 + {reasons}`；否则软删 | 无"下属 Component 为空"级联校验（**有意不做**，§6.4 结论 2）；无事务 |
| `DELETE /components/:id` | `internal/component/service/component.go` | ✅ `CountActiveByComponent` → 同上 | 同左；子资源（pipeline/env）的**级联软删**未做（本轮只做硬规则） |
| `DELETE /pipelines/:id` | `internal/pipeline/service/pipeline.go` | ✅ `CountActiveByPipeline` → 仅活跃拒绝；409 带 `reasons` | **已对齐契约** |
| `DELETE /orgs/:id` | `internal/org/service/org.go` | `orgRepo.Delete`（软删） | 无管理员校验（待 Epic C 权限拍板后补） |
| `DELETE /environments/:id` | `internal/environment/service/environment.go` | ✅ 删前统计配置覆盖 + 审计告警；**不拒绝** | 无"关联运行中发布"校验（hub 无该数据源，见 §6.3 ⑦） |

**统一响应体缺口：已闭合** —— `APIError` 已增 `Reasons []string`（json `reasons,omitempty`）与构造器 `DomainErrorWithReasons`；`Envelope` 同步增字段，`AbortWithError` / `Fail` 两条序列化路径都带上。

### 4.2 实施步骤
1. **协议层（`internal/common`）**：给 `APIError` 增加 `Reasons []string`（json tag `reasons,omitempty`），新增构造器 `DomainErrorWithReasons(kind, httpCode, seq, msg, reasons...)`；`common.Fail` 序列化时带上 `reasons`，并保持既有单 message 响应的向后兼容。
2. **计数接口（仿 `PipelineRunExistence`）**：为 component / service / release(env) 定义 `CountByX` 接口，在装配处注入具体 repo（保持 service 层不直连 DB）。
3. **service 层级联校验（事务内）**：
   - `ComponentService.Delete`：注入 `PipelineCounter` / `EnvironmentCounter`，`Delete` 前计数 > 0 → `409 + reasons`（如 "N 条流水线、M 个环境未清理"）。
   - `ServiceService.Delete`：注入 `ComponentCounter`（或递归收集 component→pipeline/env 汇总），有残留 → `409 + reasons`（逐层含路径）。
   - `OrgService.Delete`：注入 `ServiceCounter`；**决策点**——org 现为软删（保留恢复窗口），软删是否也强制级联校验需产品确认（建议：软删不强制，但标记不可恢复的硬删走校验）。
4. **对齐 N-5（流水线删除语义）**：`PipelineService.Delete` 从"任意运行历史即拒"改为"仅 running/waiting 拒绝"；新增按 `phase` 计数的查询（如 `CountByPipelineAndPhase(id, phases...)`）；历史运行不阻塞（解除编排关联、日志保留）。
5. **事务原子性**：级联校验 + 删除置于同一事务（`db.Transaction(func(tx *gorm.DB) error { … })`），避免"校验通过后、删除前"被并发插入；必要时在事务内二次校验或以唯一约束兜底。
6. **handler 一致性**：确保各 Delete handler 统一按 `*common.APIError` 透传状态码（`pipeline/handler/pipeline.go:97-106` 已是此模式，`catalog`/`component` handler 对齐）。
7. **前端切换**：console `delDetail` / `delPipeline` 用真 `DELETE /services/:id`、`/components/:id`、`/pipelines/:id` 替换 `mockDeleteNode` / `mockDeletePipeline`，直接把 409 body 的 `reasons` 渲染进"无法删除"弹窗。

### 4.3 落地 gate（在 §3 基础上细化）
- **单测**：三个 Delete service 层的"有残留 → `409 + reasons` / 无残留 → 成功"分支；Pipeline "仅 active 拒绝、仅历史放行"分支。
- **集成**：`DELETE /components/:id` 对仍有 pipeline 的组件 → `409` + reasons 层级正确；清空流水线/环境后 → `204`。`DELETE /services/:id` 对仍有 component 的服务 → `409`。
- **事务/并发**：同一事务内校验+删除；并发插入场景不绕过校验。

### 4.4 关联 backlog
- `hub/STORY-BACKLOG.md` 新增 **B-12：后端 DELETE 级联校验（N-15 / N-5）落地**（见该文 §1）；本轮另增 B-13~B-16（见 §6.7）。
- **2026-09-22 状态**：B-12 / B-13 / B-14 / B-15 ✅ 已完成；B-16 🟡 部分（源头已堵）。本轮实现清单、验证 gate 与"明确不做"见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §3。

## 5. 关联文档
- console 设计决策（前后端分工 + 钢人论证）：[`console/CONSOLE-UI-DESIGN.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) 附 C
- console 后端依赖索引：同上 附 A（N-15 / N-5）
- hub API 参考：`hub/API-REFERENCE.md` §3/§4
- 数据模型（环境分组落库）：`hub/DATA-MODEL.md` §8
- hub 待办汇总：`hub/STORY-BACKLOG.md`（B-12 ~ B-16）
- 未落地模块总表与执行顺序：[`plans/UNIMPLEMENTED-MODULES-PLAN.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/UNIMPLEMENTED-MODULES-PLAN.md)（§3 为 Epic A 的交付清单 / gate / 落地结果）

---

## 6. 附录：删除检查项梳理 + 逐项双向钢人（2026-09-16）

> 起因：用户问「"有未清理资源就拒绝" 现在检查哪些内容？删除是不是独立的、没有依赖、有没有可能造成残留？」
> 本节 source-grounded（核对 `software-distribution-platform-hub` 的 `migrations/`、各 `models/`、各 `service/*.go`、`internal/common/{base,repository}.go`）。
> ⚠️ **本节结论会修正 §1.1 的"有下级即拒绝"策略** —— 见 §6.4。

### 6.1 现状盘点：现在检查了什么

| 实体 | 端点 / 代码位置 | 软删? | **hub 现有检查** | 原型 `mockDelete*` 检查 |
| --- | --- | --- | --- | --- |
| Org | `DELETE /orgs/:id` · `org/service/org.go:58` | **软删** | **无**。TODO：平台管理员校验；注释明写"只做软删除，保留恢复窗口，不允许立刻级联物理清除下属全部资源" | 递归下级 service/component |
| Service | `DELETE /services/:id` · `catalog/service/service.go:31` | **软删** | **无**。TODO："删除前检查是否还有下属 Component" | 同上（递归） |
| Component | `DELETE /components/:id` · `component/service/component.go:98` | **软删** | **无**。TODO：权限校验 + "检查是否还有运行中的 PipelineRun" | 同级流水线数 + 环境数 |
| Environment | `environment/service/environment.go:39` | **硬删** | **无**。TODO：生产环境二次确认 + "检查是否还有关联的运行中发布" | 被 `RELEASES.env` 引用即拒 |
| Pipeline | `DELETE /pipelines/:id` · `pipeline/service/pipeline.go:79` | **软删** | ✅ **有**：`CountByPipeline>0` → `409`（**任意** run 历史即拒） | `mockDeletePipeline` |
| EnvironmentGroup | — | 表不存在 | — | 组内有环境即拒 |
| PipelineStage / TaskTemplate | `pipeline/service/stage.go:39` / `task_template.go:65` | 硬删 | 无 | — |
| ComponentConfig | `component/service/config.go:56` | 硬删 | 无（但写 `component_config_history` 审计） | — |
| Artifact | `artifact/service/artifact.go:41` | 硬删 | 无（删 DB 行 + **best-effort** 删对象） | — |
| RolloutRun（= Release 视图） | `run/service/release.go:41` | 硬删 | 无 | — |
| Binding / User / Target | `permission/service/*` · `target/service/target.go:29` | Binding·Target 硬删 / User 软删 | 无 | — |

**结论：hub 侧目前只有 pipeline 一条真实检查。** 原型的 4 条（组件→流水线+环境、服务/org→递归、环境→发布、分组→环境）在 hub **全部未落地**，其中"环境→发布"一条**在 hub 没有数据源**（见 §6.3 ⑦）。

### 6.2 残留矩阵：决定"该检查什么"的四条底层机制

| # | 机制 | 证据 | 后果 |
| --- | --- | --- | --- |
| ① | **软删不触发 `ON DELETE CASCADE`** | `common/base.go:13-18` `Base`（含 `gorm.DeletedAt`）被 orgs / services / components / **pipelines** / users 嵌入；`common/repository.go:51` 的 `Delete` 走 GORM `Delete` → 软删是 `UPDATE deleted_at` | 删 org/service/component/pipeline 时 DB 级联**永不执行**，下级**物理全部留下** |
| ② | **子表软硬删混用 → 硬删表无法表达"父已删"** | `BaseNoSoftDelete` 用于 targets / **environments** / service_trees / **pipeline_stages** / **pipeline_task_templates** / 全部 run 历史；`component_configs` / `artifacts` / bindings 亦**无 `deleted_at`** | 父删除后这些行**没有任何自我标记**，只能靠 join 父表 `deleted_at is null` 过滤 → **漏一处过滤即"孤儿可见"** |
| ③ | **硬删撞 NO CASCADE 外键 → 500** | `pipeline_runs.pipeline_id`(NOT NULL, 无 cascade)、`environments.target_id`、`pipeline_runs.target_id`、`component_config_history.environment_id`、`artifacts.pipeline_run_id/task_run_id`、`task_runs.task_template_id`、`pipeline_task_templates.environment_id` | 硬删这些父行会 **FK 报错**（不是优雅 409） |
| ④ | **cascade 静默删（无提示、无审计）** | `component_configs.environment_id ... on delete cascade`（`0002_component_management.sql:68`） | 删环境**静默带走**该环境全部配置覆盖行 |

> 附：`common/base.go` 的两条注释与实际嵌入情况**不完全一致**（`Base` 注释漏了 users；`BaseNoSoftDelete` 注释漏了 service_trees、且 `pipeline_task_templates` 实际**连 `BaseNoSoftDelete` 都没嵌**）。属文案滞后，建议顺手补齐。

**逐实体残留 / 丢失判定：**

| 删除操作 | 级联触发 | 留下什么 | 能表达"已删"? | 风险定性 |
| --- | --- | --- | --- | --- |
| Org（软删） | ❌ | service_trees / services / components / environments / pipelines / configs / artifacts / bindings 全留 | 仅 orgs·services·components·pipelines；**其余不能** | **孤儿可见** + 物理残留 |
| Service（软删） | ❌ | components 及其全部下级 | components 可；environments / configs / artifacts **不能** | 同上 |
| Component（软删） | ❌ | pipelines / environments / configs / config_history / artifacts / bindings | pipelines 可；**environments·configs·artifacts·bindings 不能** | **残留面最大**（每次删组件都批量产生 artifact 行 + 对象孤儿） |
| Environment（硬删） | ✅ configs cascade | config 覆盖行**被静默删**；若 config_history 有该环境行 → **FK 500** | — | **静默丢失 + 随机 500**（不是残留） |
| Pipeline（软删） | ❌ | pipeline_stages / task_templates / pipeline_versions 全留（**均无 `deleted_at`**） | **都不能** | 孤儿可见 + 物理残留 |
| Target（硬删） | — | — | — | 有 environment / run 引用 → **FK 500** |
| Artifact（硬删） | — | **对象存储文件可能留下** | — | **孤儿对象，且当前不可观测** |

**一句话**：**残留的真身不是"下级还在"，而是"软删不级联 + 一半子表没有 `deleted_at`"。** 因此 §1.1 的"有下级就拒绝"**既消除不了残留**（拒绝只是不让删，物理行原样保留），**又把清理成本转嫁给用户**（删一个服务要先逐层删几十个组件）。

### 6.3 逐项双向钢人

> 每项三段：**钢人**（支持检查的最强论证）→ **假钢人**（反对检查的最强论证）→ **判定**。
> 判定三元组：是否需检查 / 删除是否独立无依赖 / 残留风险。

#### ① Org 删除 ← 有下级 Service？
- **钢人**：Org 是租户根，误删影响面最大；要求"下方清零"可强制自下而上清理，也符合原型 verdict。
- **假钢人**：orgs 是**软删**（有恢复窗口），而软删不触发 cascade → "拒绝"**防不住任何残留**，只是挡掉一个**可恢复**的操作。租户注销的本质是"停用整个租户"，要求先逐层删净几十个组件在运营上不可行。代码注释本身已是这个立场。
- **判定**：**不必检**（不因有下级而拒）。正确语义 = **停用（软删）+ 平台管理员权限 + 明确"停用 ≠ 物理删除"**；真要物理清空走独立的高危运维流程（带备份）。**残留：有（可控）** —— 要求所有租户级查询带 `orgs.deleted_at is null`（含 join 到 service_trees）。

#### ② Service 删除 ← 有下级 Component？
- **钢人**：代码 TODO 自陈"避免误删导致孤儿数据"；service 与 components **都是软删**，本可表达"已删服务下组件仍在"。
- **假钢人**：检查只能防"用户以为删干净了"，物理行仍留 → 防不住残留真身。一个 service 下 20 个组件就要先删 20 次，纯成本。
- **判定**：**不必检；改为级联软删**（删 service 时把其下 components 一并置 `deleted_at`）。一次操作、语义清晰、无孤儿。**残留：有（可控）** —— components 下的 environments / configs 仍无自我标记。

#### ③ Component 删除 ← 有下级 Pipeline？
- **钢人**：流水线重建成本高；不级联会留下"指向已删组件的流水线"。
- **假钢人**：组件下线即整条交付链下线，流水线对组件无独立价值；pipeline **有 `deleted_at`**，可表达"随组件停用"。
- **判定**：**不必检；级联软删**。**残留：有（可控）** —— `pipeline_stages` / `pipeline_task_templates` 是**硬删表且无 `deleted_at`**，其"是否已删"只能靠 join `pipelines.deleted_at`。**建议**给这两张表补 `deleted_at`，否则这是孤儿可见的固定通道（已由 §6.6-3 决策为"补"）。

#### ④ Component 删除 ← 有下级 Environment？
- **钢人**：环境绑定真实集群 + 命名空间，且 environments 是硬删表不留标记，组件删了环境即成永久孤儿。
- **假钢人**：环境对组件同样无独立价值；**真问题是集群里已部署的资源要不要回收**——那是"目标态被移除后的反向投射"，与 DB 层是否拒绝删除**毫无关系**，DB 层拒绝反而会掩盖它。
- **判定**：**不必检；级联硬删**（environment 本就是硬删表）。**集群侧资源已于 2026-09-16 拍板"不回收"**（**平台侧与目标侧生命周期解耦**：无论哪条接入通道，删除平台记录都不回收目标侧资源，避免误伤生产）→ **不构成残留**，见 §6.5。**残留：有（可控）** —— 仅指**平台侧** environments 孤儿行（无 `deleted_at`，须服务层显式级联）。

#### ⑤ Component 删除 ← 有下级 ComponentConfig？
- **钢人**：配置是平台的权威参数记录，删组件等于丢弃全部参数，应提示。
- **假钢人**：config 的 `component_id` 是 `NOT NULL + cascade`，组件没了配置无归宿；且 config 是**目标态**而非历史，历史在 `component_config_history`。
- **判定**：**不必检；级联删**。注意：因组件软删，cascade **不触发** → 须服务层显式删；而 `component_config_history` 挂在 component 下同为 cascade，**审计历史随组件保留反而合理**（显式删时不要连历史一起删）。**残留：有（可控）** —— 历史行是有意保留。

#### ⑥ Component / Pipeline 删除 ← 存在**活跃**运行（running / waiting）？
- **钢人**：正在发布中被删 → runner 的 Job 仍在跑、状态还要回写 → **功能性破坏**。这是唯一"必须拒绝"的硬理由。
- **假钢人**：run 挂在 pipeline 下（软删不级联），组件/流水线消失后 runner 仍可凭 CR 名回写；若条件写成"有任意历史即拒"，废弃流水线会**永远删不掉**。
- **判定**：**须检**，但条件**必须收窄为活跃 phase**（`Pending` / `Running` / `WaitingApproval`），历史（Succeeded / Failed / Cancelled）**放行** —— 即 §2.1 的 N-5 契约。**独立：不独立**（须等活跃运行结束）。**残留：无**。

#### ⑦ Environment 删除 ← 被 Release / Deploy 任务模板引用？
- **钢人**：环境是投射目标，其被删会让引用它的流水线无法执行，应拒绝或至少预警。
- **假钢人**：**今天查不到任何东西**。`pipeline_task_templates.environment_id` 在 **Go 模型 `PipelineTaskTemplate` 中根本没有字段**（全 hub `grep EnvironmentID` 仅命中 `component/models/config.go:15,37` 与 `component/service/config.go:46,71`）→ 该列是**死列、恒 NULL**（DDL 有、代码读写不到）。且 `pipeline_runs` 只有 `target_id`，`target → environments` 是 1:N，**无法反推唯一环境**。故"发布绑定环境"这个事实在 hub **不存在** —— 原型 `mockDeleteEnv` 查的 `RELEASES.env` 在 hub **无对应数据源**。
  > 附带事实：该列的 DDL 是 `environment_id uuid references environments(id)`（**无 `on delete`** → `NO ACTION`）。一旦将来真写入了值，删环境会直接 **FK 500**（不是优雅 409）。
- **判定**：**今天不可检**。待 §4.2 后续步骤（给 `PipelineTaskTemplate` 补 `EnvironmentID`，即"目标环境成为代码事实"）落地后再做，且建议 **警告 + 放行**（列出引用它的任务模板），而非硬拒 —— 环境消失应在运行时报错清晰，不应逼用户先改流水线。**残留：有（可控）** —— 死引用（可空 FK，DB 不拦）。

#### ⑧ Environment 删除 ← 有配置覆盖行？（现状 cascade 静默删）
- **钢人**：环境删了，环境级覆盖无意义，级联删最省事（现状）。
- **假钢人**：**静默删是危险的** —— 用户不知道该环境上有 N 条覆盖参数（可能含 `secret_ref`），删环境毫无提示；更糟的是 `component_config_history.environment_id` **无 cascade**，于是同一次删除**行为不一致**：历史表无该环境行 → 静默删成功；有 → **FK 500**。
- **判定**：**须处理，但不是"拒绝"**：(a) 删除前统计并**告知**"将随之删除 N 条环境配置覆盖"并写审计；(b) **统一 cascade 语义** —— 建议把 `component_config_history.environment_id` 改为 `ON DELETE SET NULL`（历史保留、解除环境引用），消除 500。**残留：无**（历史有意保留）。→ **2026-09-16 细化决策见 §6.6-2（推荐"去 FK + 加快照列"，覆盖本条的 SET NULL 建议）。**

#### ⑨ Pipeline 删除 ← 有 run 历史？（现状实现）
- **钢人**：run 历史是审计资产；拒绝可强制形成归档意识。
- **假钢人**：**过度限制**。pipeline 是软删、run 表独立（`pipeline_runs.pipeline_id` 无 cascade），删 pipeline 并不破坏历史；用户想清掉一条跑过 100 次的废弃流水线会被**永久拒绝**。与 N-5 契约（历史放行）直接冲突。
- **判定**：**须改**（§4.2 步骤 4）：从"任意历史即拒"改成"仅活跃 phase 拒绝"。**残留：有（可控）** —— 软删后 stages / task_templates 无 `deleted_at`（同 ③）。

#### ⑩ Artifact 删除 ← 对象存储文件
- **钢人**：对象存储是钱和空间；best-effort 是务实取舍 —— 不能因对象存储抖动就阻塞元数据删除。
- **假钢人**：`artifact/service/artifact.go:50` 是 `_ = s.store.Delete(...)` —— **吞错 + 无重试 + 无对账**，注释 "nothing to roll back" 等于明说放弃一致性 → **孤儿对象永久累积且不可观测**。且 `expires_at` 列**全仓无任何读取点** → DDL 注释承诺的"后台清理任务"**并不存在**。
- **判定**：可接受**但须补对账**：周期性 GC / 对账任务（列对象 → 比对 `artifacts` 表 → 删孤儿）。**残留：有（不可观测 → 须治理）**。→ **2026-09-16 细化决策见 §6.6-4（顺序改为"先堵源头、后做对账"，且对账仅报告不自动删）。**

#### ⑪ EnvironmentGroup 删除 ← 组内有环境？（新表，见 `DATA-MODEL.md` §8）
- **钢人**：分组是壳，组内有环境时删掉会让环境变成无组孤儿；原型即此语义。
- **假钢人**：`environments.group_id` 可空 → "未分组"本身是合法状态，拒绝并非必需；也可 `SET NULL` 自动降级。
- **判定**：**须检（按原型语义拒绝）** —— 理由是**语义清晰**（分组是用户显式建立的组织结构，静默降级会丢失归类信息），不是残留。**残留：无**。

### 6.4 结论：删除检查项清单（**修正 §1.1**）

| # | 检查项 | 是否检查 | 处理方式 | 契约变更 |
| --- | --- | --- | --- | --- |
| 1 | Org 有下级 Service | ❌ 不检 | 软删停用 + 平台管理员权限；物理清空走独立运维流程 | **修正 §1.1 规则 3** |
| 2 | Service 有下级 Component | ❌ 不检 | **级联软删** components | **修正 §1.1 规则 2** |
| 3 | Component 有下级 Pipeline | ❌ 不检 | **级联软删** pipelines | **修正 §1.1 规则 1** |
| 4 | Component 有下级 Environment | ❌ 不检 | **级联硬删** environments（平台侧；**集群侧不回收**，已拍板） | **修正 §1.1 规则 1** |
| 5 | Component 有下级 Config | ❌ 不检 | 级联删（服务层显式，软删不触发 cascade）；**保留 config_history** | 新增 |
| 6 | 存在**活跃**运行（running/waiting） | ✅ **须检** | `409 + {reasons}`；历史放行 | **强化 §1.1 / 对齐 §2.1** |
| 7 | Environment 被任务模板引用 | ⏸ 待"目标环境事实"落地 | 警告 + 放行（非硬拒） | 待定 |
| 8 | Environment 有配置覆盖 | ⚠️ 提示、不拒绝 | 删除前告知 N 条 + 写审计；history 引用改"去 FK + 快照列"（§6.6-2） | 新增 |
| 9 | Pipeline 有 run 历史 | ✅ 须检（**已实现，语义需收窄**） | 仅活跃 phase 拒绝 | 对齐 §2.1 |
| 10 | Artifact 对象存储 | ⚠️ 须治理（源头优先，§6.6-4） | 级联 + 清理标记；对账仅报告 | 新增 |
| 11 | EnvironmentGroup 组内有环境 | ✅ 须检 | `409 + {reasons}` 列出未清理环境 | 见 `DATA-MODEL.md` §8.4 |

> **2026-09-22 落地**：#11 已实现（`internal/environmentgroup/service/environment_group.go`）—— 原实现返回 `400` 且**不带 `reasons`**，与本节契约不符；已改为 `DomainErrorWithReasons(KindEnv, 409, 2, …, reasons)`，reasons 带组内环境条数，单测 `internal/environmentgroup/service/delete_test.go` 固定。

**对用户三问的直接回答：**

1. **现在检查什么？** hub 侧**只有** `DELETE /pipelines/:id` 一条（任意 run 历史 → 409）；orgs / services / components / environments **全部无检查**。原型侧有 4 条，但"环境→发布"在 hub **无数据源**（⑦）。
2. **删除是否独立、无依赖？** **不是。** 除 Artifact 与 Target 外，其余实体的删除独立性被 DB 外键 + 软删机制**否定**了：要么 cascade **静默吞掉**下级（环境→配置），要么 **NO CASCADE 直接 500**（目标、运行历史、配置历史），要么软删**不级联**导致下级物理留下。
3. **有无残留？** **有，分三类（均为平台侧）** —— ① **孤儿可见**（软删父 + 无 `deleted_at` 的子表：environments / configs / stages / task_templates / artifacts / bindings）；② **静默丢失**（删环境带走配置覆盖，无提示无审计）；③ **不可观测残留**（Artifact 孤儿对象）。**集群侧已部署资源不计入残留**（见 §6.5 决策 1）。

**建议把 §1.1 的"有下级即拒绝"改为四句：**
- **域内级联软删**（org → service → component → pipeline 一路 `deleted_at`）；
- **只对"活跃运行"拒绝**（功能安全，唯一硬规则）；
- **硬删表补齐 `deleted_at` 或改为随父级联**（消除孤儿可见的固定通道）；
- **cascade 类删除（环境→配置）前置提示 + 审计**。

### 6.5 已拍板决策（2026-09-16）

> 用户于 2026-09-16 对原"需产品拍板"四项给出决定。原第 1 项直接拍板；第 2~4 项要求先做双向钢人（见 §6.6）后再定。

| # | 决策点 | 结论 | 依据 |
| --- | --- | --- | --- |
| 1 | 删环境 / 删组件时，**集群侧**已部署资源是否回收 | **不回收** | 平台与目标环境是**隔离**的；由平台主动回收目标集群资源会造成"生产被平台误伤"的风险。集群侧资源的存在与清理是**环境自身**的职责，不是平台删除操作的后置动作。 |
| 2 | `component_config_history.environment_id` 改 `ON DELETE SET NULL`？ | **不止 SET NULL → 去 FK + 加 `environment_key` 快照列** | 现状是"最差组合"：既有 FK（→删环境随机 500）、又无快照（溯源本就不健全）。详见 §6.6-2 |
| 3 | `pipeline_stages` / `pipeline_task_templates` 补 `deleted_at`？ | **补** | 代码库显式声明了"恢复窗口"设计意图（`org/service/org.go` 注释），而 pipeline **必须**软删（run 历史），故子表补 `deleted_at` 是唯一自洽解。详见 §6.6-3 |
| 4 | Artifact 孤儿对象对账排期 | **排期，顺序为"先堵源头 → 后做对账"，且对账仅报告不自动删** | 对象误删不可逆；"少删"优于"多删"。先做无猜测的源头治理。详见 §6.6-4 |

**「残留」的定义（用户口径，2026-09-16 澄清）——只指平台侧遗留：**
- ✅ 计入：**DB 行**（孤儿可见 / 静默丢失）、**对象存储对象**、**配置与审计数据**的遗留。
- ❌ 不计入：**集群侧已部署资源**（helm release / k8s 资源）—— 它是平台**有意保留**的目标态投射结果（决策 1）。
- 因此 §6.2 残留矩阵中"集群侧已部署资源"**移出残留定义**；§6.3 ④ 的"残留：有（不可观测）"收窄为"平台侧 environments 孤儿行（可控）"。

### 6.6 决策 2 / 3 / 4 的双向钢人论证

> 每项四段：**钢人**（支持该做法的最强论证）→ **假钢人**（反对的最强论证）→ **分歧 + 关键变量** → **判断**。
> source-grounded（2026-09-16 核对 `software-distribution-platform-hub`）。

---

#### 决策 2：`component_config_history.environment_id` 该怎么处理？

**代码事实**
- `component_config_history.environment_id uuid references environments(id)` —— **无 `on delete`** → `NO ACTION`（`migrations/0002_component_management.sql:93`）。
- 对照：`component_configs.environment_id ... on delete cascade`（同文件 `:68`）。
- 审计行**确实会被写入**：`component/service/config.go:44`（Upsert）与 `:69`（Delete）都调 `repo.LogHistory`，`EnvironmentID` 取自 `cfg.EnvironmentID` / `old.EnvironmentID`（`config.go:46,71`）。
- 环境删除是**硬删**（`environment/service/environment.go:39` → `repo.Delete`），handler 不做特殊处理 → FK 报错直接塌成 **500**。

**钢人（支持 `ON DELETE SET NULL`）**
1. **消除"同一操作两种结果"**：现在删环境要么静默成功、要么 500，**取决于审计表里有没有该环境的行** —— 典型的"取决于历史的随机失败"。`SET NULL` 让语义唯一：删环境总是成功。
2. **审计表是 append-only 事实记录**，`environment_id` 在此是**上下文标注**，不应承担外键完整性职责 —— 与 §6.3 ⑤ 已确立的"审计历史随组件保留反而合理"同向。
3. **不引入新的 NULL 语义**：`component_config_history.environment_id` 本来就允许 NULL（全局默认行），查询侧已必须处理 NULL。
4. **成本极低**：一条迁移；因未上线可直接改 `0002`。

**假钢人（反对 `SET NULL`）**
1. **`SET NULL` 破坏溯源**：删环境后历史行的 `environment_id` 变 NULL，与"全局默认"行**无法区分** → "某人在 alpha 环境改了 REGISTRY" 退化成 "某人改了 REGISTRY（环境未知）"。而审计表存在的**唯一目的**就是溯源。
2. **审计表根本不该有外键**。审计/历史表的通行做法是：存 `environment_id` 但**不加约束**，并**冗余一份快照**（如 `environment_key`）。这样环境被删后历史仍可读（"alpha（已删除）"）。
3. 若坚持保留 FK，语义正确的选项其实是 **`RESTRICT`**（显式拒绝 + 前置提示），但那与决策 1 的"平台侧不阻塞用户操作"取向相反。

**真正的分歧**：`component_config_history.environment_id` 是**外键**（完整性约束）还是**历史标注**（事实快照）？

**关键变量**：删除环境后，还需要从历史里回答"这条变更发生在**哪个环境**"吗？

**判断（推荐）**：**两个候选都不如"去 FK + 加 `environment_key` 快照列"**，优于单纯 `SET NULL`：
- **现状是最差组合** —— 既有 FK（→随机 500）、又无快照（溯源本就做不到，等于白背了 FK 的代价）。
- **单纯 `SET NULL` 是"修一个 bug、引入一个缺陷"**：500 消失，溯源灭失。
- `去 FK + 快照列` 与 `SET NULL` **是同一个迁移的成本**，却同时解决 500 与溯源 —— 且符合"审计表引用其他实体时存快照、不加外键"的通行做法。
- 与决策 1 自洽：环境被删后历史行是**有意保留**（不是残留），所以必须让它**可读且不阻塞删除**。
- 迁移草案：
  ```sql
  alter table component_config_history drop constraint component_config_history_environment_id_fkey;
  alter table component_config_history add column environment_key varchar(64); -- 写审计时冗余当时的环境 key
  ```
  （`environment_id` 列保留为"尽力引用"，仅去约束；写入时同时落 `environment_key`。backlog B-14）

##### 6.6-2 落地记录（2026-09-22）

**已实现**，与本节的迁移草案一致（backlog B-14 ✅）：

| 项 | 落地内容 | 代码锚点 |
| --- | --- | --- |
| 快照列 | `ComponentConfigHistory.EnvironmentKey string`（`size:64`，json `environmentKey,omitempty`） | `internal/component/models/config.go` |
| 写入路径 | config 服务经窄接口 `EnvKeyResolver{ResolveKey(uuid.UUID) (string, error)}` 取 `environments.key`；`Upsert` 与 `Delete` 两条历史写入都落快照 | `internal/component/service/config.go`；`internal/environment/repository/environment.go` 的 `ResolveKey` |
| 去 FK + 补列 | `drop constraint if exists component_config_history_environment_id_fkey` + `add column if not exists environment_key varchar(64)`（幂等，含自检） | `migrations/0008_config_history_env_key.sql` |
| 装配 | `NewComponentConfigService(componentConfigRepo, envRepo)`；`*EnvironmentRepository` 直接满足 `EnvKeyResolver` | `cmd/hub/main.go` |

**实现要点（与原草案的差异，均为有意为之）**

1. **快照解析失败降级为 `""`，不阻断配置写入**：`environment_key` 是"当时发生了什么"的记录，不是配置变更的正确性门禁。环境刚被删（或 id 不存在）时，把 500 从"删除侧"搬到"写入侧"毫无意义。该降级有单测固定（`internal/component/service/config_test.go`，4 例）。
2. **`ResolveKey` 落在 environment repo 且返回 `string` 而非 `*models.Environment`**：沿用本仓既有的"窄接口、不跨层 import 模型"手法（同 `StageStore`、`ActiveRunCounter`）。
3. **不做猜测式回填**：加列之前写入的历史行 `environment_key` 保持 NULL（当时无该列）。

**验证**

- `go build ./...` / `go vet ./...` / `go test ./...` 全绿。
- 新增 DB-free schema 回归测试 `internal/db/schema_dryrun_test.go`（GORM DryRun，**不需要真实库**）：断言 `component_config_history` 映射出 `environment_key varchar(64)`，且 `environment_id` 列**保留**（只摘约束、不删列）。
- **未跑**：真实库上的 0008 迁移（本地无 Postgres / Docker）。落地到环境时需确认：从 0001 建库时约束名确为 Postgres 默认的 `component_config_history_environment_id_fkey`；本文件用 `if exists` + 自检兜底。

---

#### 决策 3：`pipeline_stages` / `pipeline_task_templates` 补 `deleted_at`？

**代码事实**
- `pipelines` **软删**：嵌 `common.Base`（含 `gorm.DeletedAt`，`common/base.go:13-18`）；`common/repository.go:51` 的 `Delete` 走 GORM `Delete` → `UPDATE deleted_at`。
- `pipeline_stages` 嵌 `common.BaseNoSoftDelete`（`pipeline/models/stage.go:12`）；`pipeline_task_templates` **连 `Base` 都没嵌**（`pipeline/models/task_template.go:14-46` 只有 `ID` + 业务字段，**未映射 `created_at` / `updated_at`**）。
- 两表 DDL 的父 FK 都是 `on delete cascade`（`0001_init_schema.sql:126`、`:140`）—— **但软删不触发 cascade** → pipeline 软删后两表行**物理留下**，且**无 `deleted_at` 可表达"父已删"**。
- **固定通道（已核实）**：`StageHandler.List` → `StageService.ListByPipeline` → `StageRepository.ListByPipelineID` = `Where("pipeline_id = ?")`（`pipeline/repository/stage.go:19-23`），**不检查 pipeline 是否存在 / 是否软删** → `GET /pipelines/:id/stages` 对**已软删的 pipeline 照样返回阶段**。
- **同族缺口（孤儿制造入口）**：`StageHandler.Create`（`POST /pipelines/:id/stages`）同样**不校验父存在** → 可在**已软删的 pipeline 下新建阶段**（父行物理仍在，FK 通过）。
- **另一个必配修复**：`pipelines` 的 `unique (component_id, name)`（`0001_init_schema.sql:117`）**不含 `deleted_at`** → 软删一条流水线后，**新建同名流水线会唯一键冲突 → 500**。

**钢人（支持补 `deleted_at`）**
1. **治本消除"孤儿可见"固定通道**：补列后 GORM 默认 scope 会给所有 stage/template 查询自动加 `deleted_at is null`，即使漏了 join 父表也不会露出已删流水线的结构。这正是 §6.2 机制② 的正解。
2. **语义自洽**：`pipelines` 本身软删，父子应同标记机制；当前"父软删、子硬删"正是 §6.2 判定的"混用"实例。
3. **代码库显式声明了"恢复窗口"设计意图**：`org/service/org.go` 的 TODO 注释写明"只做软删除，**保留恢复窗口**，不允许立刻级联物理清除下属全部资源"（`common/base.go:10-12` 同旨："Deleting a row here should never cascade-delete run history"）。
4. **成本可控**：可空列 + 服务层级联软删，**无回填**（历史行 NULL = 活着，正是期望语义）。

**假钢人（反对补 `deleted_at`）**
1. **stages/templates 是"定义（模板）"不是"历史"**，删流水线就是想它消失；留一个"软删的阶段"没有独立恢复场景。
2. **硬删是更强的保证**：数据**不存在** → **没有任何查询能漏**；而 `deleted_at` 是"有标记但可能漏查"（raw SQL / 手写 join 不受 GORM 默认 scope 保护）。从"消除残留"角度，硬删优于软删。
3. **硬删在 DB 层已就绪**：父 FK 本就是 `on delete cascade`，只需在服务层显式发硬删。
4. **`pipeline_versions` 已是定义的专属承载者**（`0002:109`，`snapshot jsonb`，`pipeline_id → pipelines(id) on delete cascade`；`PipelineService.PublishVersion` 已存在，快照组装仍是 TODO）→ "恢复定义"有专属机制，结构软删是**冗余的第二套恢复机制**，两套易不一致。
5. **软删扩散会增加漏过滤面**：每多一张软删表，就多一处"必须记得过滤"的地方。

**真正的分歧**：stages / templates 是**独立生命周期的实体**，还是 **pipeline 聚合内的部件**？

**关键变量**：是否存在"**恢复已删流水线（含其结构）**"的产品需求？

**判断（推荐）**：**补 `deleted_at`**。理由：
- **pipeline 必须软删**：`pipeline_runs.pipeline_id` 是 `NOT NULL references pipelines(id)` 且**无 cascade** → 硬删 pipeline 一旦有 run 历史就撞 **FK 500**；这正是 `common/base.go` 注释的本意（"should never cascade-delete run history"）。
- 而代码库**显式承诺了"恢复窗口"** → 于是"pipeline 行可恢复、结构不可恢复"会产出**半状态**：恢复出来是空壳，且 `unique(component_id, name)` 仍被占。**这是最差的第三种状态**（既不是纯软删、也不是纯硬删）。
- 假钢人第 2 条的"硬删保证更强"方向正确，但**以牺牲恢复语义为代价**；恢复语义在本代码库已被显式承诺。二者不可兼得时，**宁可让标记机制统一（P1），也不接受自相矛盾的半状态**。
- 该选择**可逆**：若未来明确"不做恢复"（并删掉软删承诺），再切换为"软删 pipeline + 硬删级联子表"即可。

**无论选哪个方案，以下三项都必须做（否则治不干净）：**
- **(a) 封父存在性校验**：`StageHandler.Create` / `List`（及对应 TaskTemplate handler）操作前确认 pipeline **存在且未软删**，否则 `404` / `409` —— 这是把"孤儿制造入口"从源头关掉，比补列更直接。
- **(b) 修 `pipelines` 唯一约束**：`unique (component_id, name)` → partial unique index `... where deleted_at is null`（或含 `deleted_at` 的复合唯一）。否则"删了流水线却建不回同名"会立刻变成新的 500。
- **(c) 补齐模型映射**：`PipelineTaskTemplate` 补 `created_at` / `updated_at`（DDL 有列、模型未映射，API 读不到时间）。

##### 6.6-3 落地记录（2026-09-16）

**(a)(b)(c) 三项已实现** —— 它们是§6.6-3 里"无论选哪个方案都必须做"的部分，不依赖任何产品拍板。

| 项 | 落地内容 | 代码锚点 |
| --- | --- | --- |
| (a) 父存在性校验 | stage / task template 的 **Create / List** 之前校验父链存活；父缺失或已软删统一 **404**（`ERR.08404001` pipeline / `ERR.08404002` stage）。handler 从 `common.Fail(500)` 改走 `common.AbortWithError`，否则域错误的 404 会被塌成 500 | `internal/pipeline/service/stage.go`（`ensureLivePipeline` / `EnsureStageExists`）、`service/task_template.go`、`handler/{stage,task_template}.go` |
| (b) `pipelines` 唯一约束 | 改为 partial unique index：`idx_pipelines_component_name_active on pipelines(component_id, name) where deleted_at is null`。三处同义声明：模型 `uniqueIndex` tag、`migrations/0001` DDL、新增 `migrations/0006` 增量补丁 | `internal/pipeline/models/pipeline.go`、`migrations/0006_pipeline_active_uniqueness.sql` |
| (c) 模型映射补齐 | `PipelineTaskTemplate` 嵌 `common.BaseNoSoftDelete`，`created_at` / `updated_at` 进入 API 输出（表里本来就有列） | `internal/pipeline/models/task_template.go` |

**实现要点（与原推荐的差异，均为有意为之）**

1. **校验下沉到 service 层，不在 handler**：契约与传输层解耦。`StageService` 通过 `StageStore` / `PipelineParent` 两个窄接口依赖持久化（沿用 run 包 `PipelineRunStore` 的写法），因此**不需要 Postgres 就能单测**；`TaskTemplateService` 直接复用 `StageService`，避免父链解析逻辑重复三份。
2. **只封 Create / List，不封 Update / Delete**：前者是"孤儿制造入口 + 读侧泄漏固定通道"；后者不制造孤儿，反而是 pipeline 已软删后**清理残留结构的唯一通道**，关死会让孤儿行变成不可删的死数据。该非对称已在代码注释与单测里固定下来。
3. **软删与不存在共用 404**：`GetByID` 走 GORM 软删 scope，"已删父"与"从未存在"都收敛成 `ErrRecordNotFound` —— 对调用方语义一致（聚合根已不在）。
4. **(b) 的真实作用域需要澄清（原§6.6-3 的描述不完整）**：运行时表结构由 GORM `AutoMigrate` 管理（`internal/db/db.go`，见 `cmd/hub/conf/README.md`），`0001` 里的 `unique (component_id, name)` **只存在于"从 0001 建库"的环境**；纯 AutoMigrate 建库的库里该约束**从未被创建过**（旧模型没有任何唯一性 tag），那里的缺陷方向是反的 —— **允许同一组件下两条同名活流水线**。partial unique index 两个方向一起修正：模型 tag 让 AutoMigrate 建出正确索引（`CREATE UNIQUE INDEX IF NOT EXISTS`），`0006` 负责删掉旧约束（**AutoMigrate 只加不删约束**）。
5. **未做：`pipeline_stages` / `pipeline_task_templates` 补 `deleted_at`** —— 三项里唯一需要产品答案（"是否支持恢复已删流水线**含其结构**"）的项。补上 (a) 之后，孤儿"可见"与"可造"两条路都已断，该列从"治本必修"降级为"只在需要恢复语义时才需要"。

**验证**

- `go build ./...` / `go vet ./...` / `go test ./...` 全绿；新增 `internal/pipeline/service/stage_guard_test.go`（8 条用例：父已删 → 404 且不落库、父存活 → 放行、父链 stage→pipeline 两段校验、清理通道保持开放）。
- AutoMigrate 生成的索引 DDL 已用 GORM DryRun 实测（不需要真实库）：
  `CREATE UNIQUE INDEX IF NOT EXISTS "idx_pipelines_component_name_active" ON "pipelines" ("component_id","name") WHERE deleted_at IS NULL`
- **未跑**：`plans/e2e-smoke.sh`（本地 ingress/hub 未运行）、真实库上的 AutoMigrate 启动验证（Docker daemon 未运行）。落地到环境时需确认：若目标库里已有同名活流水线，建索引会报 duplicate key，须先改重名。

##### 6.6-3 落地记录 · `deleted_at`（2026-09-22）

原"三项里唯一需要产品答案"的项已按 §6.5 决策 3（= **补**）落地（backlog B-15 ✅）：

| 项 | 落地内容 | 代码锚点 |
| --- | --- | --- |
| 补 `deleted_at` | `PipelineStage` / `PipelineTaskTemplate`：`common.BaseNoSoftDelete` → `common.Base`（AutoMigrate 加列，**无回填**；历史行 NULL = 活着，正是期望语义） | `internal/pipeline/models/{stage,task_template}.go` |
| 活行唯一 | 旧 `unique (pipeline_id, sequence)` / `unique (stage_id, name)` → partial unique index（`where deleted_at is null`），模型侧同义 `uniqueIndex` 标签；迁移负责摘旧约束（AutoMigrate 只加不删） | `migrations/0009_stage_template_soft_delete.sql` |
| 服务层级联 | `StageService.Delete` 先软删该 stage 下全部模板、再软删 stage（DDL 的 `on delete cascade` 对软删**不触发**）；新增窄接口 `TemplateCascade` | `internal/pipeline/service/stage.go`；`internal/pipeline/repository/task_template.go` 的 `DeleteByStageID` |

**实现要点（与原推荐的差异，均为有意为之）**

1. **级联顺序 = 模板先删、stage 后删**：级联失败时 stage 仍在，整个删除**可重试**；反序会留下"stage 已删、模板仍是活行"的不一致状态。该不变量有单测固定（`TestStageDelete_StopsWhenCascadeFails`）。
2. **唯一约束必须一起改，否则引入新的 500**：补 `deleted_at` 后，软删的 stage/template 仍占着旧唯一键 → 同 pipeline 再建同 sequence、同 stage 再建同名模板都会直接失败。与 (a)(b)(c) 里 `pipelines` 的处理同源。
3. **`uniqueIndex` 标签的 participating 字段必须写全**（本次实际踩到并已修）：首版只在 `Name`/`Sequence` 上打标签，GORM 生成的索引是 `UNIQUE(name, sequence)`（**漏 `pipeline_id`**）与 `UNIQUE(name)`（漏 `stage_id`）—— 语义会从"pipeline 内唯一"悄悄变成"全表唯一"。DB-free schema 测试断言**整条索引 DDL（含列清单）**，正是为钉死这一点。

**验证**

- `go build ./...` / `go vet ./...` / `go test ./...` 全绿；新增 `internal/pipeline/service/pipeline_delete_test.go`（stage 级联 3 例）。
- DB-free schema 测试实测输出（GORM DryRun，不需要真实库）：
  `CREATE UNIQUE INDEX IF NOT EXISTS "idx_stages_pipeline_seq_active" ON "pipeline_stages" ("pipeline_id","sequence") WHERE deleted_at IS NULL`
  `CREATE UNIQUE INDEX IF NOT EXISTS "idx_task_templates_stage_name_active" ON "pipeline_task_templates" ("stage_id","name") WHERE deleted_at IS NULL`
- **未跑**：真实库上的 0009 迁移。落地到环境时需确认：若库里已有重复的**活行**（纯 AutoMigrate 建库期间没有唯一约束，允许重复），建索引会报 duplicate key，须先人工去重。

---

#### 决策 4：Artifact 孤儿对象对账是否排期？

**代码事实**
- `artifact/service/artifact.go:50`：`_ = s.store.Delete(a.StorageKey)` —— **best-effort、吞错、无重试、无对账**，注释自陈 "object already unreferenced; nothing to roll back"。
- **hub 里没有任何 GC / 定时清理实现**：`expires_at` 仅出现在 DDL（`0002:145`）与模型（`artifact/models/artifact.go:26`），**全仓无任何读取点** → DDL 注释"过期后由后台任务清理存储与本行"**描述的是一个不存在的任务**。
- `artifacts.component_id ... on delete cascade`（`0002:130`），但 components 是**软删** → **cascade 不触发** → **每次删组件都会批量留下 artifact 行 + 其对象存储文件**（且 `ListByComponent` 不 join components，孤儿**可见**）。

**钢人（支持排期对账）**
1. **对象存储是钱**：孤儿对象单调累积且不可见；`expires_at` 列已存在却从不被消费 → **表结构承诺了保留策略但功能不存在**，比没有更糟（让人误以为有保留策略）。
2. **这是"不可观测残留"里最容易治理的一类**：对象存储可列举、DB 有权威记录 → 纯离线比对，**不需要改在线路径**。
3. **泄漏是高频、必然的**：删组件（软删）不触发 cascade → 每次都批量产生孤儿，不是边缘情况。
4. **存在更省事的替代形态**：不物理删，改为"标记 + 保留期"，让 `expires_at` 真正生效 —— 同时让 DDL 注释不再撒谎。

**假钢人（反对排期）**
1. **当前可能根本不是真实问题**：`store` 可为 `nil`（对象存储未配置）、归档阶段任务尚未落地 → `artifacts` 可能还没有存量。**功能未启用就做 GC 是过早优化**，而 GC 任务本身要开发、测试、监控、长期维护。
2. **构建产物理论可重建**，早期存储成本通常可忽略。
3. **误删不可逆**：GC 一旦有 bug（key 前缀解析错、时间/时区比较错）会**删掉有效产物** —— 比"多留一些对象"严重得多。工程上 **"少删"永远优于"多删"**。
4. **更好的方向是堵源头，而不是事后捞**：把 artifacts 纳入"删组件 / 删运行"的级联处理（服务层显式，因软删不触发 cascade），把泄漏**从源头关掉**，比事后对账更符合"消除残留"的目标。
5. **`_ = store.Delete()` 的吞错问题与对账是两件事**：前者是"已知要删的对象删失败"，只需记日志 + 重试标记即可，**不需要任何猜测**。

**真正的分歧**：治理对象是"**已泄漏的存量**"还是"**正在泄漏的源头**"？

**关键变量**：① 对象存储驱动是本地（hub 自管文件）还是 S3/兼容（成本在云上）？② 归档阶段是否已上线（有无存量）？③ 是否接受"产物不可重建、误删不可逆"？

**判断（推荐）**：**排期，但按"先堵源头 → 后做对账"的顺序，且对账只报告、不自动删。**
- **第 1 步（源头，优先做，不需要任何猜测）**
  (a) 把 artifacts 纳入"删组件 / 删运行"的级联处理（服务层显式，因为父软删不触发 DB cascade）；
  (b) 把 `_ = s.store.Delete(...)` 改为**记录失败 + 标记待清理**（如 `cleanup_state` 列或 tombstone），失败可重试；
  (c) 让 `expires_at` 真正生效（保留期到 → 进入待清理），**或删掉该列 / 改注释** —— 不要留"承诺了功能"的空列。
- **第 2 步（对账，可延后；进 backlog 但不设 deadline）**：周期性任务**先只输出报告**（列对象 → 比对 `artifacts.storage_key` → 报出孤儿清单），**人工确认后再删**。理由是假钢人第 3 条成立：**自动删对象的误删风险 > 收益**。
- 三个关键变量的作用：① 决定第 2 步的必要性（S3 更值得做）；② 决定顺序（无存量时第 1 步已足够）；③ 决定第 2 步是否**必须人工确认**（不可重建 ⇒ 必须）。

### 6.7 派生 backlog（本轮新增）

| 编号 | 事项 | 关联 |
| --- | --- | --- |
| B-12 | 后端 DELETE 级联校验（N-15 / N-5）落地 | §4 |
| B-13 | **环境分组落库**（`environment_groups` + `environments.group_id`） | `DATA-MODEL.md` §8 |
| B-14 | `component_config_history` **去 FK + 加 `environment_key` 快照列** | §6.6-2 |
| B-15 | stages/templates **补 `deleted_at`** + **封父存在性校验** + **修 `pipelines` 唯一约束** | §6.6-3（✅ 后两项 + 模型映射已于 2026-09-16 落地，只剩 `deleted_at`） |
| B-16 | artifacts **源头治理**（级联 + 清理标记 + `expires_at` 生效）+ **孤儿对账（仅报告）** | §6.6-4 |

> **2026-09-23 状态（第十五批更新）**：B-12 ✅、B-13 ✅（含修掉 §6.4 #11 的 `400 → 409 + {reasons}` 偏差）、B-14 ✅（落地记录见 §6.6-2）、B-15 ✅（`deleted_at` 落地记录见 §6.6-3）、**B-16 ✅（只剩域内级联软删一项，见 §6.4）** —— **源头已堵**（`ArtifactService.Delete` 不再吞错、失败记结构化日志）；**`expires_at` 已生效**（保留期 GC：`artifact/service/gc.go`，`ARTIFACT_GC_INTERVAL` 默认 `0` = 关闭，先删对象后删行）；**`cleanup_state` 清理标记已落**（`migrations/0016`：对象删失败 ⇒ 行**保留** + `pending_deletion` + 下一轮自动重试）；**周期性孤儿对账已落**（仅报告、默认关闭）。**仍未做**：Artifact 的域内级联软删（§6.4）——其中 service→component 段已于 2026-09-23 落地并真集群验证（§1.3），剩余为 org→service 及制品/对象处理。未落地模块总表与执行顺序见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §11.3 与 §15。
