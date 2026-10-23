> **来源**：本文件是 [`CONSOLE-UI-DESIGN.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) 的配套特性文档，承接 `前端设计补全计划（已完成并删除，内容并入本文）`（计划分析与落地）与 `四份前端 spec（已并入本文各节，计划文档已删除）`、`CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md`、`CONSOLE-DECISIONS-STEELMAN-2026-10-11.md`。
> **拆分说明**：前端设计补全计划（四期、15 个工作项）的**前端侧设计事实**集中落地于此，章节号沿用计划原编号（4.1–4.5 / 5.1–5.5 / 6.1–6.5 / 第四期 §4.1–4.5），外部可引用「ui-12 §4.1」等。
> **铁律**：本文**只追加**——后续修订轮次追加到文末「变更历史」章节，禁止改写历史段落；状态判断以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **标记约定**：`【假设】` / `【待确认】` / `【后端依赖】` / 【原型未展开】。
> **权限事实源**：hub `internal/permission/models/role.go` §7 action 词表（Casbin 式 `resource:action`）：`component:read/update/delete/create/manage`、`pipeline:read/trigger/create/update/delete`、`approval:approve`、`config:read/update`、`artifact:read/download`、`page:overview/servicetree/settings:view`、`org:manage`、`user:manage`；内置组件角色 `component-viewer/editor/approver/admin`。

---

## 0. 总览与 IA 约束

计划目标：在不改动现有信息架构（左栏恒 5 项、服务树独立页、运行中心两视图、组件详情 11 主 Tab）前提下，分四期把 Console 从「主链路可用」推进到「可放心用于生产发布」。

| 期 | 主题 | 优先级 | 工作项 |
|---|---|---|---|
| 第一期 | 生产发布可控 | P0 | 4.1 配置版本历史与 diff；4.2 版本一等对象与指定版本回滚；4.3 流水线触发方式；4.4 高危操作变更原因；4.5 状态枚举修正 |
| 第二期 | 流程完整 | P1 | 5.1 审批配置与历史；5.2 通知订阅；5.3 变量与密钥；5.4 审计增强；5.5 实时日志与运行体验 |
| 第三期 | 治理与规模 | P2 | 6.1 服务树治理；6.2 全局制品库；6.3 平台运维视图；6.4 PAT 与 API 入口；6.5 外部客户分发（决策 #1：单独立项，本期不实现） |
| 第四期 | 通用体验层 | P1–P2 | §4.1 无权限态与按钮规则（即 `CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md`）；§4.2 分页检索全覆盖；§4.3 总览趋势与下钻；§4.4 未保存守卫；§4.5 i18n 与响应式 |

**IA 落点纪律**：所有新增入口严格落在现有页面 Tab / 子视图 / 弹窗，**不新增左栏项**（左栏恒 5 项：`总览 · 服务树 · 运行中心 · 接入管理 · 用户与权限`，沿用 ui-03）。新增能力若需新页面，必须过评审（沿用 §11 风险应对）。

**四件套**：每个工作项设计评审提交「交互稿 + 五态 + 权限矩阵 + 后端契约」，缺一不过审（计划 §12）。后端契约见 `三份后端契约（已并入本文并落码，见文末「变更历史」）`；五态规范见 `CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md`。

---

## 第一期（P0）：生产发布可控

### §4.1 配置版本历史与 diff

- **入口**：组件详情「配置」Tab 右侧工具栏「历史」按钮（不新增左栏项）。
- **关键交互**：右滑抽屉列版本（版本号/保存人/时间/变更摘要/关联运行）；选两版进 diff（左右对比、行级高亮、仅看变更）；每版「回滚到此版本」生成新版本（不覆盖）；保存弹轻量对话框（变更说明必填，生产环境强制）；YAML 编辑器对 `password/token/secret/key` 提示引导改用凭据引用。
- **权限矩阵**：查看 `config:read`（viewer+）；保存/回滚 `config:update`（editor/admin）。无权限 → 列表 403 态 / 按钮禁用+tooltip `config:update`。
- **五态**：引用 `CONSOLE-FRONTEND-FIVES-STATES` §2（配置版本抽屉列表、diff 视图覆盖五态）。特殊态：生产保存未填说明 → 字段校验拦截（非 403）。
- **后端契约**：`P0 后端契约（已并入本文并落码，见文末「变更历史」）` §4.1（配置版本化层 net-new：`ComponentConfigHistory` 已存在 key 级 append log，缺整环境快照版本 + `comment` + 两版整配置 diff + 回滚生成新版本）。
- **决策挂钩**：#2（版本组件共用 UI 层、分离数据层）。

### §4.2 版本作为一等对象，支持指定版本回滚

- **入口**：组件详情「交付」下新增子视图「版本」（与流水线/运行/发布并列，不新增左栏项）。
- **关键交互**：版本列表（版本号/构建来源运行/制品/创建时间/各环境部署状态徽章）；版本详情（Release Notes 可编辑、关联制品与校验、关联运行、已部署环境矩阵、晋级历史）；版本对比（选两版对比制品/配置/说明）；晋级（详情内「晋级到下一环境」，staging→prod 串联，prod 晋级触发审批）；回滚（灰度弹窗选目标版本→填原因→确认，完成后状态置 `rolled_back` 非 `failed`）；版本矩阵升级为独立面板、单元格可点跳详情。
- **权限矩阵**：查看 `component:read`/`pipeline:read`；晋级/回滚 `component:manage`（admin）；prod 晋级额外需 `approval:approve`（走审批中心）；编辑 Release Notes `component:update`。
- **五态**：引用共享规范 §2（版本列表/详情环境矩阵/对比覆盖五态）。特殊态：环境部署状态徽章在 runner→hub 回流缺口闭合前用「未知/聚合兜底」占位并标注（见 `shared/runner-reflux-spec`）。
- **后端契约**：`P0 后端契约（已并入本文并落码，见文末「变更历史」）` §4.2（pipeline **定义**版本 List/Compare/Rollback 已存在；"发布版本跨环境晋级/部署状态徽章/指定版本回滚" net-new，`packageversion` 仅部署常量矩阵）。
- **决策挂钩**：#7（新增 `rolled_back`）、#2。

### §4.3 流水线触发方式

- **入口**：流水线编辑器新增「触发器」Tab（与编排/变量/设置并列四 Tab）。
- **关键交互**：触发器列表（类型图标+名称+启停开关+最近触发，多触发器分别启停）；类型配置（手动/Git 事件/定时 cron+未来5次预览+非法即时校验/上游完成/Webhook 签名 URL 可轮换）；设置分区（并发策略排队/取消旧运行/拒绝新运行、最大并发、超时、重试）；运行列表「触发方式」列 + 详情触发上下文；触发器经 `POST/PUT/DELETE /pipelines/:id/triggers/:triggerId` 独立维护（`console/src/api/trigger.ts`），设置分区随 `PUT /pipelines/:id` 落库（`console/src/api/pipeline.ts`）——决策 #3 登记的整提交端点 `PUT /pipelines/:id/spec`（N-20）为未建的后端依赖，「四分区原子提交」为设计目标。
- **权限矩阵**：查看 `pipeline:read`；增删改触发器/设置 `pipeline:update`（editor/admin）；手动触发 `pipeline:trigger`；Webhook 签名轮换 `pipeline:update`。
- **五态**：引用共享规范 §2（触发器列表、运行列表触发方式列覆盖五态）。特殊态：cron 非法 → 字段级即时校验；Webhook 签名仅展示一次 + 轮换。
- **后端契约**：`P0 后端契约（已并入本文并落码，见文末「变更历史」）` §4.3（触发器净新增；`TriggerRequest` 仅手动运行输入体）。
- **决策挂钩**：#3（整 DAG/spec 提交端点）。

### §4.4 高危操作统一确认与变更原因

- **入口**：横切组件 `HighRiskConfirmDialog`，被 4.2 晋级/回滚、配置保存/回滚、审批通过/驳回、凭据轮转统一调用。
- **关键交互**：显示影响范围（环境/组件/当前版本→目标版本）、必填原因、可选工单号；最高危操作要求输入对象名称二次确认；原因+工单号结构化写入审计（后端需扩 `reason`/`ticket`）。
- **权限矩阵**：生产晋级/回滚 `component:manage` + `approval:approve`（prod）；生产配置 `config:update`；审批 `approval:approve`；凭据轮转 `component:manage`。
- **五态**：本工作项无独立列表；宿主列表按共享规范覆盖五态。特殊态：未填原因 → 提交拦截；最高危未输对象名 → 二次确认拦截。
- **后端契约**：`P0 后端契约（已并入本文并落码，见文末「变更历史」）` §4.4（`production_guard` 已存在 fail-closed 409；审计缺 `reason`/`ticket` 字段）。

### §4.5 状态枚举修正

- **入口**：状态词表集中修订（设计备注 + 徽章样式表），无新页面。
- **关键交互**：环境状态独立词表（未配置/已配置未验证/验证通过/验证失败）；发布状态独立词表（进行中/已暂停/成功/失败/**已回滚**）；两套徽章样式表分开维护；全站同一状态同一图标+文案。
- **权限矩阵**：纯前端词表修正，不引入新权限；读取沿用 `component:read`/`pipeline:read`。
- **五态**：影响状态徽章（发布/环境），非新增列表；特殊态：状态词表集中管理，新增状态须同步 `StatusVocab` 与两套徽章表，杜绝 `paused` 混用复发。
- **后端契约**：`P0 后端契约（已并入本文并落码，见文末「变更历史」）` §4.5（**重要更正**：`Environment.Status` 后端已是 4 值枚举，计划的"paused 混用"在后端模型层已不成立；真正缺口在 `RolloutPhase` 缺 `Failed`/`RolledBack` 终态）。
- **决策挂钩**：#7。

---

## 第二期（P1）：流程完整

### §5.1 审批配置与历史

- **入口**：运行中心下第三视图「审批」（待我审批/我发起的/已处理，依托后端 `assignee=me`，net-new）；流水线编辑器「人工审核阶段」审批人改从策略选；运行详情审批时间线。
- **关键交互**：审批策略配置（环境级默认 + 组件级覆盖，决策 #4）；通过规则（任一/全部/N 人）、超时 + 超时动作（提醒/升级/自动驳回）、转交委托；变更窗口（环境级禁发布时段 + 例外审批）。
- **权限矩阵**：查看审批中心 `approval:approve`（approver）；配置策略 `org:manage`/`component:manage`（组件级覆盖，net-new `approval:configure` 或复用 manage）；通过/驳回/转交 `approval:approve`。
- **五态**：引用共享规范 §2（审批中心三视图、策略列表、时间线覆盖五态）。特殊态：待我审批空 → 空态引导；超时自动驳回 → 时间线标记。
- **后端契约**：`P1 后端契约（已并入本文并落码，见文末「变更历史」）` §5.1（`PipelineApproval` 三级作用域已存在；缺 `Assignee` 字段/策略实体/`assignee=me`/变更窗口）。
- **决策挂钩**：#4。

### §5.2 通知订阅与通知中心

- **入口**：顶栏铃铛通知中心（已存在，扩展已读/未读/过滤/分页）；个人中心「通知设置」；组件详情订阅规则。
- **关键交互**：订阅规则（按事件类型选渠道：站内/邮件/Webhook；企业 IM 作适配器插件，决策 #5）；通知中心已读/未读/全部标记已读/按类型过滤/分页；告警静默（指定目标/组件静默时段 + 留痕）。
- **权限矩阵**：查看通知（自身）net-new `notification:read`；配置个人通知 `notification:configure`；配置组件订阅/静默 `component:manage`。
- **五态**：引用共享规范 §2（通知中心、订阅规则、渠道配置覆盖五态）。特殊态：未读计数 badge；静默生效中标记。
- **后端契约**：`P1 后端契约（已并入本文并落码，见文末「变更历史」）` §5.2（`GET /notifications` + `POST /notifications/read-mark` 已存在；缺订阅规则/渠道适配/按类型过滤/静默）。
- **决策挂钩**：#5。

### §5.3 变量与密钥管理

- **入口**：组件详情「配置」Tab 扩展为「参数（YAML）/ 变量」两子分区；流水线编辑器「变量」Tab 声明运行时参数。
- **关键交互**：变量三类（普通变量/密钥只写不回显复用 `xxxSet:true`/共享变量组首批 Service 级，决策 #6）；作用域优先级可视化（运行时参数>环境变量>组件变量>变量组）；触发弹窗按声明渲染表单；日志脱敏规则声明。
- **权限矩阵**：查看 `config:read`；普通变量增删改 `config:update`；密钥创建/轮转 `component:manage`（沿用凭据库）；变量组（Service 级）`component:manage`；（Org 级延迟）`org:manage`。
- **五态**：引用共享规范 §2（变量/密钥列表仅引用名/变量组覆盖五态）。特殊态：密钥永不明文；日志脱敏。
- **后端契约**：`P1 后端契约（已并入本文并落码，见文末「变更历史」）` §5.3（credentials 全 CRUD+AES-GCM+不回明文已存在；缺普通变量/变量组/运行时参数声明/脱敏规则）。
- **决策挂钩**：#6。

### §5.4 审计增强

- **入口**：审计页筛选+分页增强；组件详情「日志」Tab 子视图（组件管理员看本组件范围）。
- **关键交互**：筛选（时间/操作人/动作类型/对象/结果/原因关键词）；服务端分页；CSV 导出带筛选；审计详情抽屉（请求摘要/前后差异/来源 IP 与客户端）。
- **权限矩阵**：平台审计 `page:settings:view` + 平台角色；组件审计 `component:manage`（组件 admin）。
- **五态**：引用共享规范 §2（审计列表、组件审计子视图覆盖五态）。特殊态：10 万级数据服务端分页，筛选无结果 → 空态。
- **后端契约**：`P1 后端契约（已并入本文并落码，见文末「变更历史」）` §5.4（`GET /audit-logs` 六维 filter+分页已存在；缺 `reason`/`ticket` 过滤（依赖 4.4）、组件级入口、前后差异）。

### §5.5 实时日志与运行体验

- **入口**：运行详情/日志页接入流式日志；运行列表批量操作；运行详情产物区。
- **关键交互**：SSE 流式日志（自动滚动/暂停/断线重连/"跳到末尾"）；运行中进度（当前阶段/已耗时）+ 列表周期性刷新；产物区（制品列表+下载 `artifact:download`）；批量终止/重跑（强确认+权限校验，逐对象返回）；失败运行「从失败点续跑」。
- **权限矩阵**：查看 `pipeline:read`；终止 `pipeline:update`；重跑/续跑 `pipeline:trigger`；下载 `artifact:download`；批量按动作组合、逐项校验。
- **五态**：引用共享规范 §2（运行列表批量/产物区/实时日志区覆盖五态）。特殊态：日志断线重连属错误态子类；产物区无制品 → 空态。
- **后端契约**：`P1 后端契约（已并入本文并落码，见文末「变更历史」）` §5.5（`TaskRunLog` 持久化+查询已存在；agent_op 有 SSE 基础设施；缺运行级 SSE 包装/进度/续跑/批量逐对象结果）。

---

## 第三期（P2）：治理与规模

### §6.1 服务树治理

- **入口**：服务树节点详情/编辑表单（替换 toast 占位）；搜索增强（按标签/负责人/生命周期过滤）。
- **关键交互**：真实表单（负责人/描述/标签/生命周期 活跃/冻结/废弃）；组件依赖图 + 被谁依赖；废弃流程（禁新触发+保留历史+逐层清理校验）。
- **权限矩阵**：查看 `component:read`/`page:servicetree:view`；编辑 `component:update`；新建 `component:create`；删除/废弃 `component:delete`（高危确认）；Org 级 `org:manage`。
- **五态**：引用共享规范 §2（节点详情/依赖图/搜索结果覆盖五态）。特殊态：废弃节点横幅；环状依赖警告。
- **后端契约**：`P2 后端契约（已并入本文并落码，见文末「变更历史」）` §6.1（org/component CRUD 基础在；缺 owner/tags/lifecycle/dependency 模型）。

### §6.2 全局制品库

- **入口**：服务树页第二视图（跨组件制品检索，不新增左栏项）。
- **关键交互**：按名称/版本/组件/时间/环境筛选；制品详情（校验和/签名状态/SBOM 摘要/漏洞扫描严重级别计数与明细/被哪些环境使用）；策略可视化（保留期/冷热层/即将过期/"被使用中的制品不可过期"）；不开放删除（仅展示 GC 状态）；按决策 #1 预留 nullable `tenant_id`/`external_ref`。
- **权限矩阵**：检索/查看 `artifact:read`；下载 `artifact:download`；删除不开放（隐藏入口）。
- **五态**：引用共享规范 §2（跨组件检索结果、制品详情覆盖五态）。特殊态：未扫描/扫描中占位；即将过期徽章。
- **后端契约**：`P2 后端契约（已并入本文并落码，见文末「变更历史」）` §6.2（`Artifact` checksum/ExpiresAt/CleanupState 已存在；缺签名/SBOM/漏洞扫描/跨组件检索/被使用环境）。
- **决策挂钩**：#1。

### §6.3 平台运维视图

- **入口**：接入管理页 Runner 视图；平台设置；配额用量；平台健康。
- **关键交互**：Runner（版本/在线数/并发容量/排队数/最近升级结果 + 批量升级回退）；平台设置（SSO 只读/全局默认策略/系统公告）；配额用量（按 Org 运行次数/存储/Runner 时长 + 超配额提示）；平台健康（hub/runner 网关/对象存储 状态与版本）。
- **权限矩阵**：查看/操作均 `org:manage`/`page:settings:view`（平台级，非 `org:manage` 用户隐藏入口）。
- **五态**：引用共享规范 §2（Runner 视图/配额/健康覆盖五态）。特殊态：Runner 离线/升级失败红警；配额超用红条。
- **后端契约**：`P2 后端契约（已并入本文并落码，见文末「变更历史」）` §6.3（agent_op Runner 升级/版本/队列 + metrics/keycloak 在；缺聚合视图/配额用量/全局策略/公告端点）。

### §6.4 PAT 与 API 入口

- **入口**：个人中心「访问令牌」。
- **关键交互**：创建（范围/有效期，明文仅展示一次）；列表（掩码）/吊销（高危确认）；令牌创建/使用/吊销写审计；API 文档入口。
- **权限矩阵**：自身令牌管理复用 `user:manage`（自身范围），任意登录用户可管理自身令牌——**权限上不净新增**（后端实体净新增）。
- **五态**：引用共享规范 §2（令牌列表覆盖五态）。特殊态：明文仅创建时展示；无令牌 → 空态引导。
- **后端契约**：`P2 后端契约（已并入本文并落码，见文末「变更历史」）` §6.4（PAT 净新增；credentials 是组件级密钥非用户 PAT）。

### §6.5 外部客户分发（决策 #1：单独立项，本期不实现）

- **本期不交付**，仅在 6.2 制品 schema 预留 `tenant_id`/`external_ref`（决策 #1 保险）。预期需 net-new 租户/许可证动作（`tenant:manage`/`license:read`），待立项补。
- **权限矩阵**：本期无（模块未立项）。
- **后端契约**：不起草（见 `P2 后端契约（已并入本文并落码，见文末「变更历史」）` §6.5）。

---

## 第四期（通用体验层，可并行）

> §4.1 无权限态与按钮规则 = `CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md`（已交付，含五态定义 + 无权限三策略 + 覆盖清单）。本文件不重复。

### §4.2 分页与检索全覆盖
- **交互**：统一分页组件（页码/页大小/总数/翻页）+ 检索栏（关键词 + 适用筛选），复用运行中心分页组件；契约 `page`/`pageSize`/`keyword`/`filters` → `{items,total,page,pageSize}`。
- **权限**：沿用各列表既有读取动作；无权限按共享规范三策略。
- **五态**：引用共享规范 §2（统一分页列表覆盖五态）。特殊态：筛选无结果 → 空态；大数据量仅渲染当前页，禁用"全选所有页"。

### §4.3 总览趋势与下钻
- **交互**：KPI 时间范围切换（7/30 天）+ 趋势图（成功率/耗时）；KPI/图表点击 → 运行中心带筛选下钻（如失败段 → `result=failed`+时间窗）。
- **权限**：读取 `page:overview:view`；下钻目标 `pipeline:read`。
- **五态**：引用共享规范 §2（趋势图无数据 → 空态；加载超时 → 错误态重试）。特殊态：区间切换骨架；下钻空结果 → 运行中心空态。

### §4.4 未保存守卫
- **交互**：`UnsavedGuard` 路由守卫泛化到配置 YAML/环境表单/变量编辑；dirty 状态离开 → "有未保存更改，确认离开？"（保留/丢弃）；明确 dirty 白名单。
- **权限**：纯客户端，不引入权限。
- **五态**：不适用（交互安全层）。特殊态：守卫弹窗模态强确认，高亮"丢弃"为高危。

### §4.5 i18n 与响应式
- **交互**：文案抽离语言包（先中+英）；响应式断点 1280/1024/768（左栏收起/表格降列/卡片化）；键盘可达 + 焦点管理。
- **权限**：纯前端，不引入权限。
- **五态**：不适用（全局层）。特殊态：窄屏五态提示同样可读；语言切换不丢 dirty 状态（与 §4.4 协同）。

---

## 7. 落实清单与交叉引用

| 工作项 | 交互稿 | 权限矩阵 | 五态 | 后端契约 | 决策 |
|---|---|---|---|---|---|
| 4.1 | 本文件 §4.1 | 本文件 §4.1 | FIVES §2 | P0 契约 §4.1 | #2 |
| 4.2 | 本文件 §4.2 | 本文件 §4.2 | FIVES §2 | P0 契约 §4.2 | #2/#7 |
| 4.3 | 本文件 §4.3 | 本文件 §4.3 | FIVES §2 | P0 契约 §4.3 | #3 |
| 4.4 | 本文件 §4.4 | 本文件 §4.4 | （宿主列表） | P0 契约 §4.4 | — |
| 4.5 | 本文件 §4.5 | （无新权限） | （徽章） | P0 契约 §4.5 | #7 |
| 5.1 | 本文件 §5.1 | 本文件 §5.1 | FIVES §2 | P1 契约 §5.1 | #4 |
| 5.2 | 本文件 §5.2 | 本文件 §5.2 | FIVES §2 | P1 契约 §5.2 | #5 |
| 5.3 | 本文件 §5.3 | 本文件 §5.3 | FIVES §2 | P1 契约 §5.3 | #6 |
| 5.4 | 本文件 §5.4 | 本文件 §5.4 | FIVES §2 | P1 契约 §5.4 | — |
| 5.5 | 本文件 §5.5 | 本文件 §5.5 | FIVES §2 | P1 契约 §5.5 | — |
| 6.1 | 本文件 §6.1 | 本文件 §6.1 | FIVES §2 | P2 契约 §6.1 | — |
| 6.2 | 本文件 §6.2 | 本文件 §6.2 | FIVES §2 | P2 契约 §6.2 | #1 |
| 6.3 | 本文件 §6.3 | 本文件 §6.3 | FIVES §2 | P2 契约 §6.3 | — |
| 6.4 | 本文件 §6.4 | 本文件 §6.4 | FIVES §2 | P2 契约 §6.4 | — |
| 6.5 | （不实现） | （无） | （无） | （不起草） | #1 |
| 第四期 §4.1 | FIVES 规范 | FIVES 规范 | FIVES 规范 | N/A | — |
| 第四期 §4.2–4.5 | 本文件 §4.2–4.5 | 本文件 §4.2–4.5 | FIVES §2 | N/A | — |

> 详版四件套（含组件清单、字段级契约、错误响应）见 `四份前端 spec（已并入本文各节，计划文档已删除）` 与 `CONSOLE-DECISIONS-STEELMAN-2026-10-11.md`；后端端点/实体/字段级契约以 `三份后端契约（已并入本文并落码，见文末「变更历史」）` 与 `ui-09` 附 A（本计划缺口续接）为准。

---

## 附 A · 原型落点对账（集成轮，以原型为准）

> 补全内容已按评审意见**分布集成进 [`CONSOLE-UI-prototype.html`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-prototype.html) 原有页面**（companion 独立原型的「15 工作项独立左栏」形态被否决，文件已删除，见 `CONSOLE-UI-DESIGN.md` 变更历史 #19）。下表为原型**实际落点**与上文各节「设计入口」的对照；有差异处以原型渲染结果为准（事实源声明），上文入口描述保留作设计初衷记录。6.5（决策 #1 不实现）与第四期 §4.2–4.5 属设计稿层面，未做原型页。

| 工作项 | 设计入口（上文） | 原型实际落点 | 差异说明 |
|---|---|---|---|
| 4.1 | 配置 Tab 工具栏「历史」 | 配置 Tab 工具栏「⟳ 版本历史」按钮 → 整环境快照抽屉（快照 + diff + 回滚） | 一致 |
| 4.2 | 交付下子视图「版本」 | 版本一等对象承载于 4.1 抽屉内（版本列表 / 回滚），未单开交付子视图 | 入口收敛进 4.1 抽屉，避免交付 Tab 再膨胀 |
| 4.3 | 编辑器「触发器」Tab（四 Tab 并列） | 编辑器工具栏「⚙ 触发器」按钮 → 弹窗（手动 / Cron / Webhook / 事件 + 并发 / 签名） | Tab 改工具栏弹窗，避免编辑器 Tab 膨胀 |
| 4.4 | 横切 `HighRiskConfirmDialog` | 灰度控制弹窗内联：晋级 / 回滚必填原因（写入审计），回滚落 `rolled_back` 终态 | 首批仅灰度场景内联，复用场景增多后再抽横切组件 |
| 4.5 | 状态词表集中修订 | `PH` 词表扩 `rolled_back` / `verified` / `configuring` + 发布视图示例行 r4 | 一致 |
| 5.1 | 运行中心第三视图「审批」 | `RUN_VIEWS` 第三视图「审批」（按 `phase=waiting` 筛；`assignee=me` 仍依赖 ui-09 附 A 审批策略缺口） | 一致 |
| 5.2 | 顶栏铃铛 + 个人中心通知设置 | 顶栏铃铛下拉 →「查看全部通知 →」通知中心全页（未读 / 已读 + 条目直达）；个人中心「通知设置」未落 | 部分落地 |
| 5.3 | 配置 Tab 扩「参数 / 变量」两子分区 | 组件详情独立「变量与密钥」Tab（第 8 主 Tab；密钥掩码不回明文） | 子分区改独立主 Tab |
| 5.4 | 审计筛选 + 分页增强 | 用户与权限页审计区分类段控件（审批 / 运行 / 凭据 / 目标 / 权限）；分页未加 | 部分落地 |
| 5.5 | 运行详情 / 日志流式接入 | 日志 Tab「● 实时流」徽章（灰盒标注 runner→hub 回流缺口，前端轮询兜底） | 占位级 |
| 6.1 | 节点详情 / 编辑表单 | 服务树节点详情治理属性卡片（只读展示） | 只读先行，编辑表单待后端治理字段（ui-09 附 A） |
| 6.2 | 服务树页第二视图 | 组件制品 Tab →「查看全局制品库 →」独立页（sha256 / 签名 / SBOM / 扫描） | 入口改经制品 Tab，独立页贴合「库」语义 |
| 6.3 | 接入管理页 Runner 视图 | 接入管理「Runner」Tab（版本 / 队列 / 心跳 + 详情弹窗 / 升级） | 一致 |
| 6.4 | 个人中心「访问令牌」 | 右上用户菜单「个人访问令牌」→ PAT 页（创建明文一次展示 / 吊销） | 一致 |

---

## 变更历史

> 本节收口各开发轮次（R2–R5）的落地记录与拍板决策（含理由），按 clean-change-comments 规则 4 收口于此；正文只描述当前设计状态。

## 变更历史 · 修订 R2：后端净新增落地记录（开发轮 1）

本轮按「前端全量 + hub 端点一并开发」执行（steelman 定序：4.4/4.5 → 4.1/4.2 → 5.3 → 4.3 → 5.1 → 5.2 → 5.4+5.5）。已落码并过 gate（hub: go build/vet/test + gofmt；console: vue-tsc+vite build + scripts/*.mjs 契约冒烟 71/71）：

| 项 | hub | console | 状态 |
| --- | --- | --- | --- |
| 4.4/4.5 高危审计 + Rollout 终态 | AuditLog.Reason/Ticket + SetAuditReason 注解；runner Failed/RolledBack 枚举 + 终态保持 | HighRiskConfirm + ReleaseDetailView 接线 | ✅ |
| 4.1/4.2 配置版本化 + 变量组 | ConfigSnapshot 三表 + diff/回滚；VariableGroup + 绑定 + VarSource 四层解析 | ConfigVersionDrawer + VarsTab（独立主 Tab） | ✅ |
| 5.3 运行参数声明 | Pipeline.Params(ParamDecl) + PUT 透传 | 编辑器声明 UI + 触发弹窗按声明渲染 + sanitize/buildDeclaredRunParams 冒烟 | ✅ |
| 4.3 触发器 | PipelineTrigger 三型 + cronexpr（5 段解析器+全单测）+ ticker(FOR UPDATE SKIP LOCKED) + webhook 根路由 + run.finished 钩子 + TriggerSource 列 | TriggerPanel（预览5次/启停/轮换一次性展示）+ RunsTab「方式」列 | ✅ |
| 5.1 审批策略/中心 | ApprovalPolicy 实体+CRUD+校验；Assignee 播种；GET /approvals 三视图；PipelineID 直达 | RunCenter 第三视图「审批」（三子表+直达运行详情） | ✅（见下注） |
| 5.2 通知订阅 | 现有通知中心（List/unreadCount/read-mark）已覆盖铃铛基线 | — | ⚠️ B 类登记 |
| 5.4 审计过滤 | reason/ticket 过滤（4.4 已落） | PlatformAdmin 审计区补原因关键词/变更单号筛选+列 | ✅（组件级入口= B 类） |
| 5.5 日志 SSE | GET /runs/:id/log/stream（回放+游标增量+终态关闭） | streamRunLogs（fetch 流式+parseSSERawEvent 复用）+ RunMonitor 接线，轮询兜底 | ✅ |

**本轮 B 类登记（需拍板，未 silently 假修）**：
1. **5.2 订阅规则/渠道适配/静默**：需外部渠道凭据（SMTP/企业 IM）与适配器形态决策。
2. **5.1 变更窗口**（环境禁发布时段+例外审批）：独立实体+触发时校验链，产品形态待拍板。
3. **5.1 环境覆盖档执行路径**：策略实体已支持组件默认+环境覆盖两档，但 run↔environment 无直连，执行只解析组件默认（approval_center.go 范围注记）。
4. **5.4 组件级审计入口**：hub 端点挂 platformGroup（user:manage），组件管理员访问需权限矩阵放宽决策。

**未完成（A 类可续，plans 文档因此未迁移删除）**：6.1 服务树治理字段（编辑表单+后端列）、6.2 全局制品库后端（S-2 裁定：字段+POST /artifacts/:id/scan-result 双通道）、6.3 Runner 聚合、6.4 PAT（S-1 裁定：TokenHash/Prefix/Scopes/ExpiresAt）。plans/ 各 P0-P2 契约与五态文档保留至 6.x 收尾后再迁移。

---

## 变更历史 · 修订 R3：开发收口 —— A 类全部完成，B 类全部决议，计划文档并入删除

用户拍板后的收口轮（hub 30 测试包 ok / console build + 7 冒烟脚本全绿）：

| 项 | 落码 |
| --- | --- |
| **5.2 邮箱订阅**（决策 #5 收敛：先邮箱） | `NotificationSubscription`（subject 主键 + email + 事件白名单 approval_required/run_finished/run_failed + Enabled 总开关=静默保留配置）；`SMTPMailer`（STARTTLS 优先，net/smtp；SMTP_HOST/PORT/FROM/USERNAME/PASSWORD env，未配置=NoopMailer 分发 no-op）；事件源：run 终态（ApplyStatus）+ 待审批播种双钩子，best-effort 绝不污染状态写入；`GET/PUT /notifications/subscription`；console 通知设置页（铃铛面板入口） |
| **5.1 变更窗口** | `platform_settings` KV 单表 + `ChangeWindow{enabled,start,end,weekdays}`（跨零点窗口凌晨段按前一天星期归属；配置损坏 fail-closed，读取失败 fail-open——闸门挡"时机"非"事故"）；`InWindow` 纯函数+全边界单测；`runSvc.SetChangeWindowGuard` Trigger 入口 409（同 B-11 拒绝形状，改配置即时生效）；console 平台设置 Tab 开关/时段/星期 + 触发弹窗预拦截（窗外横幅+禁按钮） |
| **6.1 治理字段** | Component +`Tags`/`Lifecycle`(active/frozen/deprecated)；`ComponentDependency` 双向依赖 + 写入时 DFS 环检测（409）；deprecated 禁新触发（`ComponentGuard` 窄接口，历史保留）；`POST/DELETE/GET /components/:id/dependencies`；console 组件概览治理卡（生命周期/标签/双向依赖/同服务选择器） |
| **6.2 全局制品库** | Artifact +`ScanStatus/Signed/Signature/SbomSummary/Sev{Critical,High,Medium,Low}`（S-2 双通道：无内置扫描器，字段+`POST /artifacts/:id/scan-result` 回写，幂等全量覆盖）；`GET /artifacts` 跨组件检索（live 谓词+7 过滤，dryrun 钉形状）；console 服务树第二视图「制品库」（版本/key/类型/扫描态过滤） |
| **6.3 平台运维** | `GET /ops/runners`（目标聚合+在线判定心跳 90s）/`GET /ops/health`（DB ping+进程信息）/`GET /ops/quota`（30 天按目标维度运行计数）；console 接入管理页「平台运维」块 |
| **6.4 PAT** | S-1 落地：`PersonalAccessToken{TokenHash=sha256,Prefix,Scopes=read|write,ExpiresAt,RevokedAt,LastUsedAt}`；明文仅创建响应一次；auth 中间件 `sdp_pat_` 前缀→哈希查表→属主身份（Groups 空，RBAC 照常）；`GET/POST/DELETE /me/tokens`；创建/吊销经审计中间件自动留痕；console 个人中心「访问令牌」（明文一次性弹窗+高危吊销确认） |

### 变更历史 · B 类决议（本轮全部闭环）

1. **5.2 渠道** → 本期仅邮箱（用户拍板）；IM/Webhook 留适配器插件位。
2. **5.1 变更窗口** → 平台设置特性开关 + 时段 + 星期管控，前端预拦截 + hub 409 双保险（用户拍板）。
3. **5.1 环境覆盖档** → 保留实体两档能力（组件默认+环境覆盖），**执行路径仅解析组件默认**：`pipeline_runs` 未反规范化 `environment_id`/`org_id`，run↔environment 的绑定只存在于派发 Job 语境。环境档生效需先做 run 行反规范化 —— 已登记为后续项。
4. **5.4 组件级审计入口** → 维持 platformGroup（user:manage）；组件管理员下沉需权限矩阵放宽（未拍板，维持现状）。

### 变更历史 · 计划文档并入删除（内容权威已在本文件 + 落码）

`CONSOLE-FRONTEND-DESIGN-COMPLETION-PLAN`、`CONSOLE-P0/P1/P2-BACKEND-CONTRACT`、`CONSOLE-P0/P1/P2/P3-FRONTEND-SPEC`、`CONSOLE-COMPLETION-DEV-STEELMAN`、`CONSOLE-DECISIONS-STEELMAN`（决策记录权威 = ui-10 折叠版）。`CONSOLE-FRONTEND-FIVES-STATES` 保留（共享五态规范，持续被引用；盘点后迁 [./CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md)）。

## 变更历史 · 修订 R4：收口轮 2 —— R3 留守项全部闭环，平台自升级审批流完整版落码

R3 的四项 B 类留守中，**#3 环境覆盖档执行**与 **#4 组件级审计下沉** 本轮正式落码；**#1 渠道**与 **#2 变更窗口** 已在 R3 落码；**#5.1 环境覆盖档** 原"执行仅解析组件默认"的缺口补完；另就 **B2 Build→Harbor** 与 **B3 canary 真流量 E2E** 两项历史遗留拍板。

### 变更历史 · 本轮落码

| 项 | 落码 |
| --- | --- |
| **A1 环境覆盖档执行**（补完 R3 留守 #3） | `pipeline_runs` 反规范化 `org_id` / `environment_id`（AutoMigrate 加列 + 迁移 `0019` 双校验）；触发时按 `(component, target, namespace)` 经 envRepo 解析环境（多命中不猜、留空 fail-open）；审批策略执行路径接通**环境覆盖档优先、组件默认兜底**（`applyApprovalPolicy` 两档解析）；`running` 配额由 target 维度升级为支持反规范化后口径。单测：归属落列 + 解析边界 + 两档策略（service 层 fake）。 |
| **B1 组件级审计下沉**（补完 R3 留守 #4，用户拍板完整版） | `audit_logs` 加 `component_id`（迁移 `0020`）；`AuditMiddleware` 写时经 `Locator` 反规范化归属组件（best-effort，解析失败留空不阻断写行）；`RequireAuditAccess` 中间件双通道：平台管理员（`user:manage`）全量 + 组件管理员（`component:manage`）须带 `?componentId=` 且 handler 强制钳到该组件；`GET /audit-logs` 加 `componentId` 过滤 + repo 形状单测；console 组件详情新增「审计」Tab（403 静默降级为"无权限"提示）。 |
| **B4 平台自升级审批流完整版**（用户拍板完整版） | upgrade op 创建即入 `pending_approval` 闸（不派发）；`POST /agent-ops/:opId/approve`（`pending_approval→queued` 并派发）、`POST /agent-ops/:opId/reject`（→`failed`，reason 留痕），挂 `RequirePlatformPermission(ops:manage)`；`GET /agent-ops?status=pending_approval` 平台级台账；**顺带修 §16.5 死锁**——`tryDispatch` 此前只放行 exec，upgrade 永远 queued 无法升级，现 upgrade 在 queued 下与 exec 同等派发；`SweepApprovalTimeouts`（24h）复用 B-11 语义自动驳回；`ops:manage` 写入 RBAC 词表与 `sdp-admin` 种子；console 平台管理新增「升级审批」Tab。 |

### 变更历史 · B2 / B3 最终决策（历史遗留两项）

1. **B2 Build→Harbor** → 维持登记（用户拍板）：等首个真实构建推送需求出现再拍板 scope（registry 配置入口 + `REGISTRY_*` 注入 + docker login 凭据 + image 制品命名约定）。裁定写入 STATUS §2 `O-22②`，设计仍存 [../plans/HARBOR-REGISTRY-INTEGRATION-2026-09-28.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/HARBOR-REGISTRY-INTEGRATION-2026-09-28.md) 作为待启动 spec。
2. **B3 canary 真流量 E2E** → 留**云上验收 gate**（用户拍板，与 FIDELITY 清单口径一致）：canary 权重回传代码侧已落地完成，剩余纯验证；不本地 kind 实跑（本地维持代码侧已验证状态）。STATUS §2 `#10` 按 FIDELITY 收敛，设计仍存 [../plans/FIDELITY-KIND-VS-CLOUD-2026-10-09.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/FIDELITY-KIND-VS-CLOUD-2026-10-09.md) 作为云上验收 gate 清单。

### 变更历史 · 平台遗留项全口径（R4 后无 open 的实现缺口）

- **已落码**：ui-12 全部 A 类 + B1 + B4；R3 的 5.2/5.1/6.1~6.4。
- **刻意不做 / 条件未触发（合法状态，非缺口）**：IM/Webhook 通知渠道（R3 决策）、G-3 版本选择完整版、G-4 专用构建环境模板库、Casbin 条件触发、DAG 画布拖拽编排、G-7 全局策略/公告端点。
- **登记为后续项（非本轮 scope）**：B2 Build→Harbor（待真实需求）、B3 canary 云上验收（随云上首跑）、自升级完整审批流的角色矩阵产品语义（B4 已用平台 `ops:manage` 落地，角色矩阵另行立项即此）。
- **结论**：所有条目均有显式 disposition，"没有遗留项" = 每一项都关闭或登记，而非强行清零。

### 变更历史 · 验证 gate（R4 轮）

hub：`go build ./...` / `go vet ./...` 全绿；`internal/target` / `internal/permission` / `internal/platform` / `internal/run` 单测包全绿（新增：upgrade 审批闸 + 派发修复 + 超时回收 + 审计归属反规范化 + 双通道鉴权 + componentId 过滤形状）。
console：`vue-tsc --noEmit` / `pnpm build` 全绿；7 个 `scripts/*-smoke.mjs` 全绿。

## 变更历史 · 修订 R5：原型路线图落地轮 —— 4.1 / 4.2 / 4.3 / 4.4 / 5.1 / 5.2 全部收口

`plans/CONSOLE-UI-PROTOTYPE-ROADMAP-2026-10-12.md`（控制台原型代码层审查的后续路线图）全部落地，内容权威并入本文，**该 plan 已删除**。范围仅原型（`console/CONSOLE-UI-prototype.html` 内联 JS），console 实现仓未动。

### 变更历史 · 本轮落码（原型）

| 项 | 落码 |
| --- | --- |
| **4.2 版本一等对象 + 指定版本回滚**（P0，原唯一未动项） | `RELEASES` 每条加 `ver`（当前部署版本）；新增 `RELEASE_VERSIONS` 注册表（组件 → 历史版本，新→旧）模拟新契约；`curRelease(comp,env)` 取当前记录；灰度控制台改「选择目标版本 → 必填原因 → 回滚」：**append 一条新 release 记录**（`ver`=目标版本、`step`=100%、`phase`=rolled_back、`from`=旧版本），不再「置 0%」；发布表格加「版本」列，非当前记录标「（历史）」 |
| **4.1 版本 diff + 变更说明** | 配置版本抽屉支持勾选任选两版本出行级 diff（LCS 对齐，+/- 着色，基于整环境快照 `full`）；配置保存经原因弹窗收集**变更说明**并 append 新版本（v5…），回滚同样 append |
| **4.4 原因输入扩展** | 公共 helper `requireReason(id)` / `openReasonModal(title,onOk)`；配置保存（`yaml-save`）、审批意见、凭据轮转三处高危操作**原因必填**并写入审计 |
| **4.3 触发器配置** | Tab 真切换（`data-tab`/`data-panel` 互斥）；cron 五段式校验 + 人类可读预览（下次执行时间，`cronParse`/`cronNext`）；保存**写回 `TRIGGERS[name]`** 并 render（此前空操作只 toast）；事件触发面板补上游契约标注（N-21） |
| **5.1 审批策略 + 时间线** | `APPROVAL_POLICY`（组件默认 + production 环境覆盖两档，hub ApprovalPolicy 已落地）；审批弹窗加策略卡 + 审批时间线（按 run 过滤 `approval.*` 审计记录） |
| **5.2 订阅规则** | `SUBSCRIPTIONS`（事件类型 × 渠道：站内/邮箱，与 hub SMTPMailer 对齐）；通知中心「订阅规则」弹窗，保存写审计 |

### 变更历史 · 决策记录（用户拍板 + 双向钢人，详见 ui-10 附 E.8）

1. **回滚语义 = append 新 release 记录**（用户拍板）：与 `PipelineVersionService`（定义版本）append-only 语义同构；历史可追溯，审计叙事「回滚 X → Y」。
2. **历史版本来源 = 新契约 `GET /components/:id/versions`**（用户拍板）：`GET /package-versions` 经核对是平台自身三版本（ConfigMap 常量），不可作回滚目标——登记 **N-33**（ui-09 附 A）+ API-REFERENCE 待立项。
3. **高危操作原因必填**（钢人裁定）：与灰度控制台既有 `cc-reason` 模式统一；「可选 = 实际不填」为行为学稳态，审批场景以 placeholder 引导降摩擦。

### 变更历史 · 顺带修正（原型）

1. **启动 TDZ**：首屏 `render()` 延迟到整段脚本加载后（服务树/接入/通知中心被 URL 恢复为默认页时不再 ReferenceError）。
2. **审计分类**：`auditCatOf` 将 `/target|runner/` 提前，`runner.upgrade` 归「目标」。
3. **铃铛角标**：按 `NOTIF_READ` 实时算未读，标记已读后即刷新。
4. **PAT 安全**：删「永不过期」、`admin` 加二次确认、生成后弹窗展示明文令牌。
5. **版本矩阵语义勘误**：`GET /package-versions` 实为平台自身三版本（ui-11 已勘误），原型 mock 注释与弹窗文案同步更正，组件级版本矩阵改引新契约。
6. **文件名对齐**：原型 由 `CONSOLE-UI-原型.html` 实际落盘改名为 `CONSOLE-UI-prototype.html`（CONSOLE-UI-DESIGN 变更历史 #11 早已按新名记录，本次磁盘与文档对齐），11 处引用同步更新。

### 变更历史 · 验证 gate（R5 轮）

- 抽出 `<script>` 跑 `node --check`：SYNTAX_OK。
- 纯函数冒烟（从原型抽取 `cronParse`/`cronNext`/`diffLines` + esc/toast stub）：**20/20 通过**（cron 合法/非法/步长/范围/列表、下次执行时间、LCS diff）。冒烟抓出并修复 1 个真 bug：`*/15` 步长式 cron 初版解析不了。
- 内容复核：51 个新标记全部在盘；3 个旧模式（`upd('0%','rolled_back'`、旧角标口径、触发器空保存）清零。

