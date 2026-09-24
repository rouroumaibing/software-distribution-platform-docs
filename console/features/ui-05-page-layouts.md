> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · §7 页面布局
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 7. 页面布局

### 7.1 全局骨架（重设计）

```
┌───────────────┬────────────────────────────────────────────────┐
│ 左栏 268px     │ 顶栏 56px：面包屑  🔍搜索(⌘K) ◐主题 灰阶 ⓘ备注 👤│
│ (折叠→64px)    ├────────────────────────────────────────────────┤
│ 品牌+折叠      │  主内容区（全宽，永不被树挤压）                  │
│ 总览           │  padding 24 · 背景 bg · max-width 1280          │
│ 服务树         │                                                 │
│ 运行中心       │                                                 │
│ ── 平台管理(2) │                                                 │
│ ── 用户与权限   │                                                 │
│ ── 接入管理    │                                                 │
└───────────────┴────────────────────────────────────────────────┘
```

- 左栏背景随主题：light 用 `surface`（**不再用海军蓝**）；dark 用更深 surface。选中项 = 圆角块 + `accent-soft` 底 + `accent` 字（不用 3px 竖条）。
- **左栏无树、无"最近访问"**：资源树只在 `/service-tree` 页内出现（见 7.5）；跳转靠顶栏 ⌘K。
- 主区三项（总览/服务树/运行中心）**不挂分组标签**；仅「平台管理」有标签（见 §5.1 v4.1 调整）。
- 泛化约束：左栏宽度**恒定**（268/64），不随内容伸缩；条目数**恒 5**（见 S5）。
- **面包屑只有顶栏一条**（原型 `#crumb`，`renderCrumb()`），中间层可点；内容区不再重复。段位规则：
  | 页面 | 面包屑 |
  | --- | --- |
  | 总览 / 服务树 / 运行中心（运行视图） | `SDP / 总览`｜`SDP / 服务树`｜`SDP / 运行中心` |
  | 运行中心（发布视图） | `SDP / 运行中心 / 发布`（第二段与 `RUN_VIEWS` 同源） |
  | 组件详情 | `SDP / 服务树 / <组件名 · uuid>`（`服务树` 可点） |
  | 编排页 | `SDP / <组件名> / 交付 / <流水线名>` |
  | 平台管理 | `SDP / 平台管理 / 用户与权限｜接入管理` |

### 7.2 总览指挥中心（重写）

```
你好，张三 👋                         [+ 新建组件] [▶ 触发运行]
⚠ 1 个目标离线（kind-e2e-02），Runner 重连后将自动重放 Pending 任务。
┌ 待办 ─────────────────────────────────────────────┐
│ ⏳ 待我审批 3   ✕ 失败运行 2   ⏸ 暂停的灰度 1       │  ← 可点击的行动卡
┐ 运行态势 ────────────────────── 目标健康 → ────────┐
│ 今日运行 42 │ 成功率 93% │ 运行中 4 │ 在线目标 3/4*│  ← *可点直达接入管理页
┌ 最近运行 ──────────────────── 查看全部 42 条 → ────┐
│ 流水线 | 流水线ID | 组件 | 触发人 | 状态 | 耗时 | 开始时间 │  ← 3 条速览
```

- 待办卡是**行动导向**（数量 + CTA），且**点击即落到对应视图+筛选**（筛选真实生效）：`待我审批 3` → 运行视图 / 待我审批；`失败运行 2` → 运行视图 / 失败；`暂停的灰度 1` → **发布视图**（原先是独立的 `/releases` 页，v4 已并入）。
- 「最近运行」只放 **3 条速览 + 出口**，完整列表归运行中心（避免与运行中心同表重复，见 §8.4）。
- **目标离线提示条（warnbox）** 只讲行动（离线→自动重放），数字口径归 KPI（§8.4）。
- KPI 与最近运行**要求全局聚合**——见 附 A。

### 7.3 组件详情（7 主 Tab）

头部（名称 + `git@…/<comp>.git` + 语言/分支 + **uuid**）→ `[编辑] [▶ 触发] [⋯ 删除]` → 主 Tab 一行 7 个 → 子 Tab pill（仅「交付」）→ 内容。

- **概览 Tab** = KPI 卡（最近一次运行 / 活跃环境 / 成员 / 待处理，数据取 `GET /api/component/:uuid`）。**不设"快速入口"按钮组**——那与主 Tab 重复（§8.4）。
- **交付 · 流水线** = 流水线列表（列：名称 / 类型 / 版本 / 最近运行 / 操作 `运行 · 编辑 · 删除`）+ 右上 `＋ 新建流水线`。**这是流水线列表的唯一归属地**（v4.4）。
- **交付 · 运行** = 该组件运行记录（列：流水线 / 流水线ID / 状态 / 开始时间；原型取前 3 条）。
- **交付 · 发布** = 该组件发布记录（列：环境 / 灰度步骤 / 健康度 / 状态）。
- **配置** = 左环境树（分组 → 环境）+ 右 `values.yaml`（查看 / 编辑 / 导入 / 导出）。
- **环境** = 环境与分组管理：分组可折叠、hover `＋` 新建环境（走**两步向导**）；**分组的删除入口只在"分组为空"时出现**（非空分组不给删除入口，避免误删）；环境删除走右侧详情面板。右侧面板即**对接配置**（基本信息 / 接入方式三选一 / 按接入方式分流的凭据区 / 逐项连接测试），完整规格见 **§7.12**。
- 面包屑只有顶栏一条；内容区不再重复（§8.4）。
- **制品 / 权限 / 日志** 三个 Tab 均已展开（2026-09-21 原型同步设计）：制品库（筛选 + 表格 + 行内操作，§7.10）、组件级权限（`component_role_bindings`，§7.9）、运行日志聚合（§7.11）。权限的 UX 规格见 §7.9。

### 7.4 流水线 CRUD 页面

- **列表（组件交付→流水线）**：列 = 名称 / 类型 / 版本 / 最近运行 / 操作（运行 · 编辑 · 删除）；右上 `＋ 新建流水线`。
- **跨组件视角**：v4.4 起**不再有**独立/视图化的跨组件流水线列表；跨组件巡视只保留运行与发布两个切面。
- **编辑器**：沿用阶段组横向流；顶部工具条 `[保存] [▶ 触发] [🗑 删除流水线]`，阶段头有 `executionMode` 开关与 `[+ 子任务]`，任务卡 hover 出 `[编辑] [删除]`。
- **子任务的"产品语言"（2026-09-17 拍板，原型已实现）**：编辑器**不露 `Build` / `Release` / `Approval` 原词**，只显示「构建 / 运行任务」「发布任务」「人工审核阶段」三种描述；三者由配置**派生**（填了发布目标 → `Release`，填了审批人 → `Approval`，否则 `Build`），`type` 仅作为请求体序列化产物进入 hub 供 runner 派发。**不引入模版目录**。
- **请求体预览**：保存时弹出 JSON / YAML 双视图，标注 `PUT /pipelines/:id`（更新）或 `POST /pipelines`（新建），字段映射见附 D。
- **删除确认弹窗**：标题「删除流水线 <名>？」，**强确认（输入名称）**；提交 `DELETE` 后由**后端判定**——`409 + {reasons}` 时渲染"无法删除"弹窗（reasons 来自后端，含进行中 / 待审批运行等逐条清单），成功则 toast + 列表移除（并提示"历史运行日志保留"）。**前端不预先计算影响面**，契约与服务树删除一致（附 C / N-15）。

> **落地状态（2026-09-22）**：本节 5 条已全部落地，实现清单 / 显式差异 / 门禁见 **附 H**。

### 7.5 服务树页与全局搜索

```
┌ 服务树 ──────────────────── [+ 新建 Service] [+ 新建组件] ┐
│ ┌ 左卡（290px）───────┬ 右卡 ─────────────────────────┐ │
│ │ 🔍 搜索(服务端)      │  [进入组件详情][编辑]          │ │
│ │ ─────────────────── │  ── 节点信息 ──                │ │
│ │ ▾ platform-eng      │  路径   platform-eng/svc-a/... │ │
│ │   ▾ svc-a           │  仓库   git@…/comp-web.git     │ │
│ │     • comp-web      │  语言   Go · main              │ │
│ │   ▸ svc-b  3 项·点开 │  流水线 2 条                    │ │
│ │ ─────────────────── │                                │ │
│ │ ⚡ 懒加载 · 虚拟滚动  │                                │ │
│ └─────────────────────┴────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

- 树面板**自身滚动**，页面不随树变长；懒加载提示挂在未展开节点右侧。
- 右卡只放**节点自身信息**；同级节点已在左卡树中可见，不再重复列表（§8.4）。
- 全局搜索浮层：`⌘K` → 输入 → 结果（类型 + 名称 + 路径）→ Enter 打开。

### 7.6 运行中心（两视图，v4 新增、v4.4 收敛，取代原「全局流水线页 / 全局发布页」）

```
┌ 运行中心 ──────────────────────────────────────────────┐
│ 跨组件巡视 · 运行 / 发布                                 │
│ [运行][发布]   [视图内状态筛选]              共 N 条     │
│ ┌──────────────────────────────────────────────────┐  │
│ │ 运行   → 流水线 | 流水线ID | 组件 | 触发人 | 状态 | 耗时 | 开始时间 │
│ │ 发布   → 组件 | 环境 | 灰度步骤 | 健康度 | 状态 | 控制→ │
│ └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

- **为什么只有一个入口**：运行与发布是"跨组件的同一批数据的不同切面"，各自独立成菜单会让左栏出现同类项膨胀。合并后主区只剩 3 项（总览/服务树/运行中心），且新增切面（如"制品"）不需要再动导航。
- **URL 形态（N-13 已裁决，见附 B）**：`/runs?view=runs|releases`（+ `&filter=` / `&page=`）。视图是**同一页的状态**，不是子页面 —— 因此不进路径层级；切换视图用 `replace`（返回键一次退出运行中心）。
- **视图内筛选真实生效**，且取值只能落在真正存在的枚举里（原型 `RUN_FILTERS`，已逐项核对）：

  | 视图 | 筛选项（原型实测） | 过滤位置 |
  | --- | --- | --- |
  | 运行 | 全部 / 运行中 `running` / 失败 `failed` / **待我审批** `waiting` | 下推 `GET /runs?phase=`，**服务端过滤** |
  | 发布 | 全部 / 进行中 `running` / **已暂停** `paused` / 成功 `succeeded` | 前端聚合数据上过滤（发布无 phase 枚举） |

  > **「已暂停」是已落地的一等状态（2026-09-19 按原型回写）**：原型 `PH` 状态集含 `paused ⏸ 已暂停`，发布数据 `r1` 即 `phase:'paused'`，筛选存在且能出结果。**后端支持仍是缺口**：`Paused` 是 Rollout（runner `Rollout` CRD，**任务级**）的状态，不在 `PipelineRunPhase` 六个枚举（Pending/Running/WaitingApproval/Succeeded/Failed/Cancelled）里。因此在 hub 提供 `GET /releases?scope=global&state=paused` 之前，该筛选项在**真实实现版**需要"逐 run 拉 `GET /runs/:id/tasks`"（N+1）才能判定 —— 登记为附 A N-3。
  > ✅ **原型内部不一致已修（2026-09-19）**：`NOTE['runs-releases']` 第 2 条已改写为“「已暂停」已是本原型的一等状态（`PH` 徽章 + `RUN_FILTERS` 筛选 + 数据行可筛出结果），后端端点待补”；同条第 1 条“hub 无全局发布端点”亦按 N-3（全局 `/releases` CRUD 已落地）改写。
  > ⚠️ **真实实现版的筛选项是「可实现子集」**（2026-09-19 记录）：`src/constants/runCenter.ts` 的 `RUN_VIEWS` 现为 运行「全部 / 运行中 / 失败 / **待我审批**」+ 发布「全部 / 进行中 / 成功」。**「已暂停」在实现版不渲染**（N-3 端点未落地）—— `isValidRunFilter('releases','paused')` 显式返回 `false`：宁可没有该筛选，也不要“点了没反应”（原型铁律：不渲染无 handler 的装饰控件）。
  > 📐 **两层命名（勿混）**：原型 `RUN_FILTERS` 用语义键（`running` / `failed` / `waiting` / `paused` / `succeeded`），实现版用 `PipelineRunPhase` **真实枚举值**（`Running` / `Failed` / `WaitingApproval` / `Succeeded`）直传 `GET /runs?phase=` —— 上表「筛选项」即“语义键 → 真实枚举值”的映射结果。
  > ⚠️ **两处不对称（待拍板，非缺陷）**：运行视图无「成功」、发布视图无「失败」/「待审批」，系原型现行形态（`全部` 已覆盖）。若要放开成状态全集，改 `RUN_VIEWS` 一处即可（纯前端、可逆）；非法值由 `pnpm test:runcenter`「筛选值只落在真实枚举内」断言兜住。

  > **「待我审批」的命名**：筛选标签用「待我审批」（原型），状态徽章用「待审批」（原型 `PH.waiting`）。二者指同一 `WaitingApproval` 状态；**筛选标签表达了意图但在 N-2 落地前名不符实**（当前只能下推 `phase=WaitingApproval`，会列出所有人的待审批）——见附 A N-2。
- 面包屑体现到视图级：`SDP / 运行中心 / 发布`（第二段与 `RUN_VIEWS` 常量同源，附 B 硬约束 ②）；左栏点「运行中心」= 回到**默认"运行"视图、筛选重置**（菜单点击语义 = 回默认态）。
- **运行视图以「流水线名称」为主标识 + 附「流水线ID(uuid)」**（v4.4）：名称是链接（`data-act="open-pl-runs"`），点开看该流水线的运行历史；ID 以 mono 字体并排展示，供精确定位。

### 7.7 发布 / 灰度

- 发布视图行 → `控制 →` 进入灰度控制：步骤器（10%→50%→100%）+ 健康指标 3 卡 + 控制按钮（暂停/晋升/回滚）+ 规则说明。
- 环境状态在环境树中以状态点表达：`succeeded` 绿 / `paused` 黄 / `unknown` 灰（原型 `.dot.*`）。

### 7.8 其余列表页

权限 = 「筛选栏 + 表格 + 分页 + 行内操作」标准布局；**环境不是列表页** = 左侧环境树 + 右侧**对接配置面板**（见 §7.12）；制品库为**只读版本包清单**（仅 3 列 + 顶部归档说明，无筛选栏 / 行内操作，见 §7.10）。

### 7.9 权限与审批 UX（对应 [hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)）

> 授权分层与后端表设计见 [hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) §7：**Keycloak 管身份、k8s 管 runner 部署边界、hub 内两层 RBAC + 审批表**。前端只消费 hub 鉴权结果。钢人论证结论：组件级权限以"管理员/组映射为主" → 不引入 Keycloak UMA；默认审批人 = 组件 owner/管理员。

**授权分层（前端视角）**

| 层 | 前端表现 | 数据来源 |
| --- | --- | --- |
| 平台级 | 顶部导航/页面按 `platform_role` 显隐；设置页仅管理员可见 | hub `platform_role_bindings`（KC 组映射） |
| 组件级 | 组件详情「权限 (permissions)」Tab；按 `component_role` 控制按钮 | hub `component_role_bindings` |
| 审批 | 运行监控 Approval 节点展开审批卡（§7.6） | hub `pipeline_approvals` |

**平台级权限页（页面 × 增删改查颗粒度全面分析）**

平台管理员在「用户与权限」管理 `keycloak_group → platform_role` 映射。各页面颗粒度：

| 页面 / 资源 | 查看 | 新增 | 修改 | 删除 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 总览 Dashboard | ✅ 登录用户 | — | — | — | 只读聚合 |
| 服务树 | ✅ | 🔒 `org:manage` | 🔒 `org:manage` | 🔒 `org:manage` | 组织/目录管理归平台管理员 |
| 组件（列表/详情） | ✅ 平台级 view | 🔒 `component:create`（全局） | 组件级 `component:update` | 组件级 `component:delete` | 单组件 CRUD 走组件级角色 |
| 流水线（编排/触发） | 组件级 `pipeline:read` | 组件级 `pipeline:create` | 组件级 `pipeline:update/delete` | 组件级 `pipeline:delete` | 触发 = `pipeline:trigger` |
| 配置 config | 组件级 `config:read` | — | 组件级 `config:update` | — | 仅修改 |
| 环境 | 组件级 `config:read` | 组件级 `config:update` | 组件级 `config:update` | 组件级 `config:update` | 环境与分组同属"接入准备" |
| 运行监控 / 日志 | 组件级 `pipeline:read` | — | — | — | 随流水线权限 |
| 发布 / 灰度 | 组件级 `pipeline:read` | — | 🔒 `release:manage`（建议 editor/approver） | — | 灰度控制收紧 |
| 制品库 | 组件级 `artifact:read` | — | — | 🔒 `artifact:delete`（管理员） | 下载 = read |
| 用户与权限 / 接入管理（平台） | 🔒 `user:manage`/`org:manage` | 🔒 | 🔒 | 🔒 | 仅平台管理员 |

> 🔒 = 需对应角色；未持有则按钮隐藏 + 路由守卫拦截（见错误态）。

**组件级「权限 (permissions)」Tab**

组件详情的「权限」Tab 管理 `component_role_bindings`（已展开，§5.4 / §7.3）：

| 操作 | UI | 权限要求 |
| --- | --- | --- |
| 查看成员列表 | 表格（类型/主体/角色/来源） | `component:read` |
| 添加成员/组 | 抽屉：选主体类型（`user`/`group`）+ 主体标识 + 选角色 | `component:update` |
| 修改成员角色 | 行内下拉 | `component:update` |
| 移除成员 | 行内删除（确认） | `component:update` |

- 四种组件角色（hub `component_roles` 预置，[hub 数据模型 §7.3](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)）：`component-viewer`（只读）/ `component-editor`（读写+触发+配置）/ `component-approver`（+`approval:approve`）/ `component-admin`（全部组件动作 + `component:manage`）。
- 主体支持 **user 或 group**（`subject_type`/`subject_id`）：组名当前由用户在 console 手填（hub 暂未暴露 Keycloak 组目录，待补 `/groups` 接口）；角色选择器枚举来自 hub `GET /component-roles`（P3c 新增）。
- **默认成员（创建组件时自动生成，满足"默认审批人=owner/admin"）**：组件 owner（user 或 group）**自动绑 `component-admin`**（P3b，含 `approval:approve` + 全量管理动作，非致命失败）；因此 owner 天然是默认审批人（[hub 数据模型 §7.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)）。
- V1 旧绑定行（`userId`/`roleId`）在界面回显兼容，新建/修改一律走 §7 字段。
- 权限实时生效；无权限按钮在界面禁用/隐藏，而非仅报错。

**审批卡 UX（对应 审批分支 §6.2）**

运行监控中 Approval 子任务 `phase==WaitingApproval` 时展开审批卡：

- **审批人显示**：编排指定 approver → 显示「指定：X」；否则显示「默认：组件 owner / 管理员」（取自组件所有权）。
- **操作区**：`批准` / `拒绝` + 意见输入框（必填，见 §8.3）。
- **通过**：提交 → 后端写 `Approved` → runner 解除挂起 → 流程继续（§6.2）。
- **拒绝**：提交 → 后端写 `Rejected` → 运行终止并标 `Failed`（§6.2 审批拒绝分支）。
- **防自审**：当前用户是申请人（或在申请人组内）→ UI 提示并禁用按钮，需另一名 approver 处理（参考 GitHub Environments / GitLab Protected Environments 的 prevent self-review）。
- **审计留痕**：卡下方展示历史决策（谁/何时/意见），数据来自 `pipeline_approvals`。

**权限不足错误态（接入 §8.2）**

- **路由守卫**：未持 `platform_role` → 重定向或显示 §8.2 错误态「无权限访问该页面，请联系管理员」+ 申请入口。
- **按钮级**：无 `component:update` 等 → 按钮禁用 + hover「需要 X 权限」，不依赖点击后才报错。
- **API 403**：偶发越权 → §8.2 错误态「操作被拒绝（403），请申请组件 X 的 Y 角色」。

**开源参考**：平台/组件两层 RBAC ← ArgoCD；默认审批人=owner ← Backstage ownership；选谁审/通过拒绝/防自审 ← GitHub Environments / GitLab Protected Environments / Spinnaker Manual Judgment。

### 7.10 制品库（Artifacts，组件级）

组件详情「制品」Tab = **只读的版本包清单**，作用域主键 = 组件 uuid（`GET /components/:componentId/artifacts`）。本页只展示**流水线构建 / 发布产物**，不是上传入口；人工不可删除 / 上传。

- **列（仅 3 列）**：
  - **版本包**：制品名，`<a>` 超链接，点击经**签名 URL 直连**下载（hub 生成有时效预签名 URL，前端不持有对象存储凭据，不经 console 中转）。
  - **构建时间**：产物落库的本地时间（`builtAt`）。
  - **文件大小**：人类可读体积（`size`）。
- **四态**：有效（默认）/ 空态（组件尚无制品 → "运行构建 / 发布后，产物自动归档进制品库"）/ 加载中 / 错误（拉取失败 → 重试，§8.3）。
- **归档与备份（本页顶部信息条，参考实现）**：
  - **存储**：对象存储 MinIO（3 副本 · 跨 AZ 同步），bucket `sdp-artifacts`，对外域名 `artifacts.sdp.local`；并镜像至 NFS 归档盘 `/data/artifacts/{org}/{component}/{version}/`（断网可取用）。
  - **目录布局**：`sdp-artifacts/{org}/{service_tree_path}/{component}/{run_id}/{artifact_name}`（以 run 为单位归集，便于复现某次构建）。
  - **备份周期**：每日 02:00 增量快照 + 每周日 03:00 全量快照；保留策略为**热层（可下载）90 天 → 转冷归档 1 年（合规留痕）→ GC 报告 + 人工确认后清理**。
  - **过期**：`expires_at` **已生效**（2026-09-23，B-16 收口）—— hub 保留期 GC（`ARTIFACT_GC_INTERVAL`，**默认关闭**）按该声明回收，**先删对象、后删行**；对象删失败的行标记 `cleanup_state='pending_deletion'`（**不再出现在本页列表**）并由下一轮自动重试。对账本身仍是**仅报告 + 人工确认**（见 hub `DELETE-CONTRACT.md` §6.5 / §6.6-4）。
- **删除不可开放给人工**：本页不提供删除 / 上传操作；产物清理由 GC 与过期策略统一处理（与 §7.9 组件级权限一致——`artifact:delete` 在后端保留，但前端不暴露入口）。
- 端点（附 A · N-x / 旧文 `artifact.ts`）：`GET /components/:componentId/artifacts`、`GET /download`（签名 URL）。（原型已移除 `POST/DELETE` 前端入口；后端契约保留。）

### 7.11 日志（Logs，组件级运行日志聚合）

组件级「日志」Tab = **运行日志聚合视图**，不是独立日志服务。作用域主键 = 组件 uuid；每运行经 `GET /runs/:id/tasks/:name/log` 拉取（§7.6），本视图按运行合并、按任务标注、按级别着色。

- **顶部**：运行选择（组件最近运行，默认取首条）+ 级别筛选（`info` · `warn` · `error` · 全部）+ 关键字搜索 + 刷新。
- **日志面板**：等宽、按 `时间戳 [级别] 任务 消息` 渲染；`error` 红、`warn` 黄、`info` 默认色。
- **下钻**：选某运行即切换该运行的 task 日志；可深链到运行监控的日志面板（§7.6）。
- **空态**：运行刚起 / 无输出 → "等待输出"（§8.3 日志面板空态）。
- **加载态**：首次连接日志流用骨架 / spinner；轮询刷新不进加载态（§8.3）。
- **错误态**：日志拉取 / 流失败 → 重试。
- 端点（§7.6）：`GET /runs/:id/tasks/:name/log`。

### 7.12 环境对接配置（创建向导 + 凭据模型，2026-09-21 新增）

> **起因**：组件详情「环境」Tab 此前只有一个 `target` / `namespace` 自由文本框，「新建环境」也只收名称/目标/命名空间 —— **kubeconfig、kube-apiserver 地址、SSH 主机与凭据无处可填**。本节按 hub 实测代码把这件事补完。
>
> **层次前提（2026-09-21 裁定）**：本节讲的是**② 平台怎么够到目标**（目标 = 被纳管集群 / 主机），**不涉及 ③ 平台自身装在哪、怎么升级**。平台自身不进服务树 / 组件 / 环境模型，其部署与升级留在平台之外——三层边界见 [README.md「5.4 平台自身定位与部署形态」](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/README.md)，不采纳自升级的六条理由见 [shared/DATA-MODEL.md §9.11](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)（原 E2E-VERIFY-PLAN P6，已删档归位）。另注：**单机版**（平台与目标同集群）下，`targets` 里那一行目标指向的集群同时也是**平台底座所在**；但 **runner 是接入侧代理组件，其身份与部署形态无关**（2026-09-21 二次裁定），故下文凡提"目标"均指**被接入的目标**角色。
>
> **口径校准（2026-09-21 更正）**：本节早前把 `kubeconfig` / `ssh` 的凭据挂在 **runner 侧 Secret**，并称其"尚未裁决"——**两处都已更正**。用户已澄清：**两条直连通道都由 hub 侧发起连接**（不是给 runner 用），且**发布目标与归档机器都可能是非 K8s 的**，平台须覆盖非容器环境的「连接 / 测试 / 发布 / 执行命令」全链路。跨组件裁定见 [README.md §5.6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/README.md) + `shared/DATA-MODEL.md` §9.5 / §9.7。

#### 7.12.1 接入方式：三条通道，凭据归属不同

对账实测代码（`hub/internal/target/models/target.go`、`hub/internal/environment/models/environment.go`、`runner/pkg/executor/job_builder.go`、`migrations/0001_init_schema.sql`）：

| 事实 | 代码依据 | 对设计的影响 |
| --- | --- | --- |
| `targets` 表只有 `name / vendor / region / status / agent_version / last_heartbeat_at` | `target.go` | 本表**只描述 `agent` 通道的目标**，不含任何凭据列 |
| `environments` = `component_id` + `key` + `name` + **`target_id`**(NOT NULL) + `env_type` + `namespace` | `environment.go` / `0001_init_schema.sql` L89 | `agent` 通道的"接入" = 引用目标 + 命名空间；**但 NOT NULL 的 `target_id` 表达不出非容器目标**（`shared/DATA-MODEL.md` §9.7） |
| `env_type` 只有 `test` / `production` | `environment.go` 常量 | 环境类型选择器只给这两项（审批策略看它，§7.9） |
| 既有凭据惯例是**存引用不落明文**：`components.repo_secret_ref` · `component_configs.secret_ref` | `component.go` L18 / `config.go` L21 + DDL L61/L74 | 直连通道**沿用同一惯例**（只落 `credentialRef`），但**凭据的物理位置从"目标侧"变为"hub 侧"**——这是与旧注释的**结构性**差异 |
| runner 把任务翻译成**目标集群里的一个 K8s Job**（`sh {ScriptPath}` / `helm upgrade` / `kubectl apply`；工作区 EmptyDir 卷） | `runner/pkg/executor/job_builder.go` | Job / ns / SA / RoleBinding / 卷在物理机上都不存在 → **非容器目标无法走 Runner**，只能 hub 直连 `ssh` |
| hub **零 `client-go`**、全仓**零 SSH 代码** | `hub/go.mod` / `git grep ssh` 无命中 | 两条直连通道都是净新增能力 |

**结论**：环境对接不是"往环境里塞一份 kubeconfig"，而是**目标类型 × 接入通道**两个正交维度的组合：

| 目标类型 `targetKind` | 可用通道 `access` |
| --- | --- |
| `k8s`（K8s 集群） | `agent`（推荐 · 现有架构）· `kubeconfig`（hub 直连 apiserver） |
| `host`（**非容器目标**：物理机 / VM / 裸金属 / 归档机） | **仅 `ssh`**（hub 直连主机） |

| `access` | 适用 | 需要填什么 | **谁持有凭据** |
| --- | --- | --- | --- |
| **`agent`**（推荐） | 目标已注册且 Runner Agent 在线 | 目标（下拉 `GET /targets`）+ `namespace` | **不需要凭据** —— Agent 出站回连，hub 零凭据 |
| **`kubeconfig`** | 集群装不了 Agent，或 hub 需主动连 | 凭据来源三选一 + `namespace` | **hub 侧**（环境只存 `kubeconfigSecretRef`） |
| **`ssh`** | **非 K8s 的虚机 / 裸机 / 归档机** | 目标主机列表 + 凭据引用 | **hub 侧**（环境只存 `sshSecretRef`） |

- `agent` 模式下面板显式写一句"不需要 kubeconfig，也不需要 kube-apiserver 地址"，避免用户按旧习惯去找填 kubeconfig 的位置。
- **非容器目标（`ssh`）的能力范围**：连接 / 测试 / **发布（制品分发到主机 + 启停服务）** / **执行命令**；与容器目标的差异在 **无 Job、无命名空间、无 RBAC 隔离**（SSH 用户身份即边界）、**工作区是目标主机上的临时目录**。
- 三种方式**互斥**（一个环境一种主接入方式）；若某次发布同时要动 K8s 与主机，可拆成两个环境，或由发布任务自身去连第二目标。

#### 7.12.2 新建环境 = 两步向导

原弹窗只有名称/目标/命名空间，且创建后**没有落点继续配置**。改为两步：

- **Step 1 基本信息**：环境名称 / 所属分组（只读，来自左树）/ 环境类型（`test` | `production`）。
  - 附说明：**分组 ≠ 环境类型** —— 分组只是归类（可折叠、可为空），与环境类型正交；审批策略只看环境类型（§7.9）。
- **Step 2 接入配置**：接入方式 seg 三选一 → 只渲染该方式的**最小必填项**（`agent` = 目标 + ns；`kubeconfig` = 凭据来源 + ns；`ssh` = 首台主机 + 凭据引用）。
- **最小必填校验**：不通过则停在当前步 + toast（原型约定：`openModal` 回调返回 `false` 时保持弹窗打开）。**凭据细节允许创建后再补**，不把向导做成凭据表单。
- 创建后：自动选中新环境并落到环境详情面板继续完善；初始状态 = 未配置。

#### 7.12.3 环境详情 = 对接配置面板

自上而下四段（原型 `.sec` 分段）：**基本信息 → 接入方式 → 凭据区（按 `access` 分流）→ 连接测试**。字段绑定统一走 `data-env-field="路径"`（支持 `kube.credRef` / `ssh.sudo` 这类嵌套路径）。

**① Kubernetes：凭据三种提供方式**（`kube.source`）

| 方式 | 字段 | 何时用 |
| --- | --- | --- |
| `ref` **引用凭据**（推荐） | 从凭据库选一条 `kubeconfig` 凭据（显示"被 N 个环境引用"） | 多环境共用同一集群；轮换只改一处 |
| `paste` **粘贴 kubeconfig** | 全文 YAML → 「解析并回显」 | 一次性对接，手上已有 kubeconfig |
| `manual` **手工填写** | `server`（kube-apiserver 地址）+ 认证方式 + 默认 context + `namespace` + TLS 开关 | 拿不到完整 kubeconfig，只能拿到 apiserver 地址 + Token |

**② 粘贴后必须"解析并回显"** —— 这是用户确认"我连的是哪台"的唯一手段（原型 `parseKubeconfig` 做预览；权威校验由 hub 侧 `yaml.Unmarshal` + `clientcmd` 完成）：

| 回显项 | 来源 |
| --- | --- |
| kube-apiserver 地址（server） | `clusters[].cluster.server` |
| CA 证书 | 有 `certificate-authority(-data)` |
| 跳过 TLS 校验 | `insecure-skip-tls-verify: true` |
| 认证方式 | `client-certificate(-data)` → 客户端证书；`token` → Bearer Token；`username`+`password` → basic |
| current-context | `current-context` |
| 默认命名空间 | `contexts[].context.namespace` |

解析失败**逐条给原因**，不笼统说"格式错误"：

| 情形 | 提示 |
| --- | --- |
| 无 `clusters:` 段 | 不是合法 kubeconfig |
| 有 `clusters:` 但缺 `server` | 无法定位 kube-apiserver 地址 |
| 命中 `exec:` | **平台不支持**（需执行本地二进制来签发证书；直连通道下等于在 **hub 侧允许任意代码执行**）→ 引导改用静态 Token / 客户端证书 |
| 认证材料全缺 | 未找到可用认证材料（`token` / `client-certificate-data` / `username+password` 至少其一） |

解析完成后**明文即被消费**：粘贴框清空、只留结构摘要卡，`raw` 不进环境记录。

**③ 主机（SSH）：目标主机列表**

| 字段 | 说明 |
| --- | --- |
| `host` / `port` | IP 或域名；端口默认 `22` |
| `user` | 登录用户，建议专用**非 root** 部署账号 |
| `authType` | `password`（用户名 + 密码）\| `key`（免密密钥 PEM + 可选 passphrase） |
| `secretRef` | **凭据引用名**（**hub 侧** Secret）；面板只显示"已配置 / 未配置" |
| `bastion` | 可选，跳板机 `ProxyJump`（`host:port`） |
| 环境级 `ssh.sudo` | 部署时用 `sudo` 提权（配合非 root 账号） |

- 主机可增删改（弹窗），面板以紧凑表格列 host / port / user / 认证 / 凭据引用 / 跳板机 / 操作。
- 多主机 = 一个环境的 `ssh.targets[]`；跨环境复用凭据 = `secretRef` 相同。

#### 7.12.4 凭据存储与脱敏（**沿用既有铁律，但凭据的物理位置变了**）

> ⚠️ **2026-09-21 更正**：直连通道的凭据**由 hub 持有**（hub 侧发起连接），**不是 runner 侧**。本节第一版按"目标侧 Secret"写，已改正。

1. **记录只存引用名**：环境 / 目标记录只落 `credentialRef`，**与 `repo_secret_ref` / `secret_ref` 同一套铁律**；hub **不新增"凭据明文列"**。
2. **凭据物理位置——未定**：候选 ① **hub 自身运行环境的 K8s Secret**（与 hub 的 Postgres DSN / 对象存储 key 同级托管）、② hub DB 加密列、③ 外部 Vault / KMS。注意本库 P0 拓扑**没有**独立 secret manager，故 ① 与 ② 的实际隔离差异比直觉小——**这条需单独拍板**（`shared/DATA-MODEL.md` §9.7 已登记）。
3. **敏感字段单向**：接口回显 `xxxSet: true` 布尔，**永不返回明文**；原型用 `••••••••` 掩码 + 「已配置」chip + 「重新设置」。
4. **输入即丢弃**：认证材料输入后立刻从内存态清空（原型在 `input` 监听里置 `credSet=true` 并清 `token/cert/password`），后续渲染只出掩码。
5. **权限**：看环境 = `config:read`（能看到"已配置"，看不到明文）；改凭据 = `config:update`（沿用 §7.9 的"环境与分组同属接入准备"）。
6. **审计**：凭据的新增 / 更新 / 引用变更写审计（谁在何时换了哪台集群或主机的凭据）；⚠️ **`ssh` / `kubeconfig` 直连执行的逐条命令证据链无现成表**（`shared/DATA-MODEL.md` §9.7 未定项）。

#### 7.12.5 连接测试 = 逐项 checklist，不是笼统一句"成功"

入口在面板「连接测试」分段右侧。**分维度探测、各项独立超时（建议 5s）**，避免一个不可达把整次测试挂死。

| `access` | 探测项（顺序即依赖） |
| --- | --- |
| `agent` | ① 目标已注册 ② Runner Agent 在线（心跳新鲜度） ③ 命名空间已声明 ④ 部署权限（dry-run create deployment） |
| `kubeconfig` | ① kube-apiserver 可达（TCP/TLS 握手） ② TLS / CA 校验（或已显式跳过） ③ 认证通过 ④ 命名空间可访问 ⑤ 部署权限（dry-run create/update deployment） |
| `ssh` | ① TCP 可达 ② 主机指纹校验（known_hosts） ③ SSH 认证通过 ④ 部署目录可写 ⑤ sudo 提权可用（未启用则记"无需提权"） |

- 渲染：`✓/✕` + 项名 + 明细（如 `心跳 12s 前 · agent v0.4.2`）+ "N/M 项通过"徽章 + 最近测试时间。
- 前置项未过时，后续项标"前置项未通过，跳过"，**不伪造成功**。
- **测试失败不阻塞保存，但挡住发布门禁**（与 §1.2「权限不足」同类：触发即拒 vs 运行中拒）。

#### 7.12.6 环境状态机

`env.status` 复用环境树的状态点（`.dot.succeeded / paused / unknown`，§7.7）：

| 状态 | 含义 | 树上的点 |
| --- | --- | --- |
| **未配置** | 关键字段缺失 | 灰 `unknown` |
| **已配置 · 未验证** | 字段齐了但没测过 | 灰 `unknown` |
| **验证通过** | 连接测试 N/N 通过 | 绿 `succeeded` |
| **验证失败** | 存在未通过项 | 黄 `paused` |

改动任一关键字段（`targetId` / `ns` / `kube.credRef` / `kube.server`）→ **状态回落**为"已配置 · 未验证"并清空上次测试结果。

#### 7.12.7 端点与后端依赖

| 用途 | 端点 | 状态 |
| --- | --- | --- |
| 目标下拉 | `GET /api/v1/targets` | ✅ 已有（`RegisterCRUD`） |
| 环境 CRUD | `POST/GET/PUT/DELETE /api/v1/environments`、`GET /components/:id/environments` | ✅ 已有 |
| 环境创建 | `POST /api/v1/environments` | ⚠️ 请求体需扩 `access` / `kubeconfigSecretRef?` / `sshTargets?` / `sshSecretRef?`（现仅 `targetId` / `namespace` / `envType`） |
| 环境分组 | `environment_groups` + `environments.group_id` | ⚠️ 见 [hub 数据模型 §8](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)（DDL 已拟，未落库） |
| 连接测试 | `POST /api/v1/environments/:id/test` → 逐项 checklist | ✅ **已落地** —— `EnvironmentService.Test` / `TestReport`（配置完整性结构校验；连通性项如实返回 `skip`，hub 无出站能力），结果持久化到 env |
| 凭据库 | `GET/POST/PUT/DELETE /api/v1/credentials`（只回 `valueSet`，不返明文） | ✅ **已落地（2026-09-23）** —— `internal/credentials`（AES-GCM 信封加密落库，列前缀 `enc:v1:`；API 仅回 `valueSet`）+ console `CredentialsView.vue`（平台管理第 3 个 Tab） |
| kubeconfig 解析 | `POST /api/v1/credentials/parse-kubeconfig` | ✅ **已落地** —— 结构化回显 `server`/`caPresent`/`insecureSkipTLS`/`authMethod`/`currentContext`/`defaultNamespace` + `errors`（**拒绝 `exec:` 插件**） |
| 目标注册 token | `POST /api/v1/targets/:id/enroll-token`（一次性） | ✅ **端点已落地** —— `TargetHandler.EnrollToken` / `TargetService.GenerateEnrollToken`（一次性 + 过期）。⚠️ 网关仍用全局共享 `GATEWAY_TOKEN`，per-target 身份约束（`agent_version` 上报 + 凭据流转）属 `§9.9` 引导特性 |

> **SSH 属净新增能力**：hub 全仓无 `ssh` 命中、hub 亦无 `client-go`（**零出站能力**）；`sshTargets` / `sshSecretRef` / `POST /environments/:id/test` / `POST /environments/:id/exec` 均需新建。按层分写约定，列定义应落 `docs/shared/DATA-MODEL.md`、请求体与响应落 `docs/shared/API-REFERENCE.md`；本节只给 console 侧的消费形状。**凭据由 hub 侧持有**（§7.12.4）。

> ⚠️ **`targets` 只覆盖 `agent` 通道**：`environments.target_id` 是 **NOT NULL FK**，**表达不出非容器目标**；非容器目标需给 `targets` **扩表**（`targetKind` + 直连凭据列，`shared/DATA-MODEL.md` §9.7）。本节的 `ssh.targets[]` 只是**环境内**的主机清单，**不等于**跨环境复用的目标注册表。

#### 7.12.8 「执行命令」的两条路径（**别混用**）

非容器环境要支持「执行命令」。这个能力有**两条形态不同**的路径，文档与 UI 都必须区分：

| | ① 流水线任务（自动化 · 主路径） | ② 面板手动诊断（人工 · 辅助） |
| --- | --- | --- |
| 入口 | 编排页的流水线任务（`Build` / `Release` 的类型扩展，见下） | 环境详情面板「接入方式」区的 **「▷ 远程执行（诊断）」**按钮 |
| 粒度 | 一次运行 = 一套 DAG（多阶段 / 多任务 / 可并行） | **一次一条命令**，不建 DAG、不重试 |
| 触发者 | 流水线触发（含审批门禁） | 有 `target:exec` 权限的操作人 |
| 审计 | `task_runs` 状态回流 + 运行记录（DAG + 截图式日志） | **逐条命令审计**（谁在何时对哪台目标执行了什么） |
| 走哪条通道 | 全部（`agent` / `kubeconfig` / `ssh` 按环境 `access` 分流） | 仅**直连通道**（`kubeconfig` / `ssh`）；`agent` 通道无此入口 |
| 输出 | 落 `GET /runs/:id/tasks/:name/log` | **流式回显在弹窗内**，不落运行记录 |

**任务侧的执行后端（未立项，仅登记形状）**：现 `TaskRunSpec` 只有一种执行实现（目标集群里的 K8s Job，`runner/pkg/executor/job_builder.go`）。`ssh` 目标没有 Job / 命名空间 / 卷，其任务语义须改为**「制品分发到主机 + 在主机上执行脚本」**，工作区是**目标主机上的临时目录**。这需要一个 `executor backend` 判别维度（`README.md` §5.6 / `shared/DATA-MODEL.md` §9.7 未定项）。

> 原型现状：**② 已做出**（kubeconfig 面板与 SSH 面板各有「▷ 远程执行（诊断）」，mock 输出）；**① 的任务类型扩展尚未设计**（属编排页任务模型改造，需连同 `TaskRunSpec` 一起立项）。

---
