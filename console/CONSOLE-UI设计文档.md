# SDP Console 前端设计文档（合并版）

> 本文档合并自 `console/docs/design/` 下四份设计文档，形成唯一的前端设计真相源：
> - `CONSOLE-DESIGN.md` —— 设计系统（色板 / 状态色 / 字阶 / 组件形态）+ 6 屏页面构成
> - `CONSOLE-LAYOUT.md` —— 布局骨架 / 信息架构 IA v2（菜单收敛 / 组件详情 Tab 化 / 权限双轨）
> - `CONSOLE-MODULES.md` —— 后端端点契约 / 模块 Backlog（MOD-0~10）/ 三态子任务表单
> - （`OPEN-ITEMS.md` 已随文档合并整合进各组件 Backlog 与本文附 B，不再单独保留）
>
> 合并时间：2026-09-09。交互原型保留 `console-ia-v2-prototype.html`（IA v2 决策依据）。
>
> **标注约定**：`【假设】`= 原文档未覆盖、由本文据上下文推导，需你确认；`【待补充】`= 设计尚未落档，需补；`【待确认】`= 存在歧义 / 待拍板。

---

## 0. 合并说明与文档边界

| 原文档 | 在本文档的位置 | 合并后状态 |
| --- | --- | --- |
| CONSOLE-DESIGN（设计令牌 + F1–F6 构成） | §9 视觉系统 + §7/§8 页面构成 | 其 §3 页面结构 / §4 路由表曾被 LAYOUT 标记为"被覆盖"，已以 LAYOUT 为准 |
| CONSOLE-LAYOUT（IA v2） | §5 信息架构 + §7 页面布局 | 布局唯一权威源 |
| CONSOLE-MODULES（契约 + Backlog） | §4 功能清单 + 附 A 契约 | 模块/端点唯一权威源 |
| OPEN-ITEMS（未完成项） | 附 B 当前未完成项 | G1–G6 已全部落地，仅 G7 + R1–R3 残留 |

**现状快照（2026-09-09）**：Console 前端 MOD-0~MOD-10 全部页面与组件已落地，`vue-tsc` + `vite build` 全绿；hub 后端 G1–G6 缺口已于 2026-09-06 全部补齐，仅剩 **G7（权限校验 TODO，安全债）**；runner 剩 **R1–R3（生产化收尾：chart 鉴权 / values 注入验证 / 镜像固化）**。端到端链路「构建→测试→发布(灰度可控)→审批→看日志→下制品」已可跑通，只待 runner 联调。

> **文档完整性**：核心任务流程的**执行模型 + 异常分支**已于 §6 补全（权限分支依赖 G7，见 §1.2）；各页面**四态**已于 §8.2 按双向钢人论证补充；**用户侧验收（按目标执行、达成目标）**已于 §10.2 定义；**自动化功能测试（API 各阶段组合）**范围已于 §10.3 锁定，实现推迟到后期独立自动化测试项目。当前无遗留 `【待补充】` 主块。唯一未决的架构项 `stage_runs` 已据双向钢人论证**确认不建**（见 [hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) §6.3）。

---

## 1. 问题与目标

- **产品定位**：SDP（Software Distribution Platform）Console 是平台的前端控制台，目标是通过**纯界面交互**，把软件的「构建 → 测试 → 发布到多套环境」完整跑通。技术栈 Vue 3 + Pinia + Vue Router + OIDC/Keycloak。
- **目标用户**：平台管理员 / 组件负责人 / 研发工程师 / 审批人 / 集群接入方（角色定义见 [hub 用户故事](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/user-stories.md)）。
- **核心目标（一句话）**：用户不必写脚本或登录多套系统，在控制台内按「服务树 → 组件 → 环境 → 配置 → 流水线 → 运行」的引导路径，把软件成功发布到多套环境（测试 / 转测 / 生产等）。
- **成功标准**：
  - 端到端一次发布可在控制台内完成，无需跳出到 CLI / K8s；
  - 同一组件可对接多套环境（测试 / 转测 / 生产），流水线按环境差异注入参数；
  - 运行态（DAG / 进度 / 日志 / 灰度）实时可见；
  - 生产发布可经审批门禁，且权限管控在基本功能完成后**紧接着落实**（见 §1.2）。

### 1.1 标准流水线模式（4 类，编排模板参考）

流水线 = 阶段（Stage）的有序组合，**阶段串行**执行；每个阶段内含若干子任务（Task），子任务按该 Stage 的 `executionMode` **串行或并行**执行（**已确认 `ExecutionMode` 放在 Stage 级**），全部子任务完成 = 该阶段完成，才进入下一阶段。任务三态 `Build` / `Release` / `Approval`（见附 A.3）。以下 4 类为典型模式，供在控制台编排时参考：

| 模式 | 阶段 / 任务组合 | 说明 |
| --- | --- | --- |
| **日常流水线** | 构建(Build) → 部署到测试环境(Release→测试 env) | 每次提交后快速验证，部署到测试环境 |
| **版本归档流水线** | 创建版本分支 → 构建(Build) → 归档(Release→制品库/对象存储) | 产出可复用的"版本包"，供转测/生产流水线获取 |
| **转测流水线** | 版本包获取(Consumes 归档产物) → 发布到转测环境(Release→转测 env) | 消费版本归档产物，发布到转测环境 |
| **生产流水线** | 版本包获取 → 审批(Approval) → 多环境发布(Release→多 env) | 经审批门禁后，向多套环境依次/并行发布 |

> 注：「版本包获取」对应任务间的 `Produces/Consumes` 产物依赖（[hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）；「多环境发布」在同一组件下多环境目标内完成（Pipeline 锚定单 Component 不变式）。

### 1.2 落地顺序（基本功能优先，权限紧随）

1. **先完成基本功能**：服务树 → 组件 → 环境 → 配置 → 流水线创建/编排/运行 → 多环境发布全链路贯通（console MOD-0~MOD-10 + hub G1–G6 + runner R1–R3）。
2. **紧接着落实权限管控**：基本功能可用后，立即实现权限体系——平台级用户/角色 + 组件级 role-bindings + 环境/操作级管控（如生产环境强制审批）。当前 G7 为权限校验 TODO，是下一优先项。

---

## 2. 用户与场景

角色（对齐 [hub 用户故事](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/user-stories.md)）：平台管理员、组件负责人、研发工程师、审批人、集群接入方。

- **场景 A｜编排与触发（组件负责人 / 研发）**：服务树建组件 → 配环境与参数 → 编排日常 / 版本归档流水线 → 触发运行 → 运行中心看 DAG 进度。
  - *易错点*：参数管理是"预置变量库"，触发参数是"本次运行的具体值"，两者在触发对话框组装——概念易混。
- **场景 B｜版本流转（研发）**：版本归档流水线产出版本包 → 转测流水线获取并发布到转测环境 → 生产流水线获取、过审批、多环境发布。
- **场景 C｜灰度与审批（发布负责人 / 审批人）**：生产流水线到 Approval 节点，审批人批准 / 拒绝；灰度发布可暂停 / 晋升 / 回滚。
- **场景 D｜集群接入（集群接入方）**：注册 K8s 集群（仅出向连接），流水线任务下发到该集群执行。

---

## 3. 竞品与参考

| 参照对象 | 借鉴点 | 避坑点 |
| --- | --- | --- |
| 老前端 `old/go-devops/go-devops-ui` | `MainLayout`（深色菜单 + header + router-view）、`ServiceTreeManage`（搜索树 + 详情面板 + 节点操作）、`PipelineRunMap`（阶段组 + 状态图例 + 编号节点）、`user/*` + `product/ProductManage`（列表模式）、i18n 中/EN + 登录 | 旧版**服务树常驻侧栏**挤压主内容 → 已否决，降级为独立页面 |
| GitLab / Argo CD / Tekton Dashboard / Backstage | 成熟布局范式（功能菜单 + 主内容）、运行态 DAG 可视化 | — |
| Ardot 画布（设计稿） | 视觉稿来源：`https://ardot.tencent.com/file/720332157478724` | 画布为静态稿，落地以本文档令牌为准 |

---

## 4. 范围与功能清单

状态：⬜ 未开始 · 🟨 桩已存在待对齐 · 🟩 已可对接后端 · 🟥 页面已建但无数据通道。

### 第一版 Must-have（均已实现 🟩）

| ID | 模块 | 对应页面 |
| --- | --- | --- |
| MOD-0 | 应用骨架 / 导航 / 设计系统组件 | 全局骨架 + tokens |
| MOD-1 | 服务树导航（Org→Service→Component） | 服务树页 master-detail |
| MOD-2 | 组件详情 + 参数管理 | 组件详情 Tab |
| MOD-3 | 流水线编排器 + 三态子任务表单 | 流水线编排 |
| MOD-4 | 运行触发对话框 | F4→F5 入口 |
| MOD-5 | 运行监控（DAG + 进度轮询） | 运行监控 |
| MOD-6 | 审批决策 | 监控页 Approval 节点 |
| MOD-7 | 日志查看 | 监控页日志面板 + 日志页 |
| MOD-8 | 灰度/发布进度 | 灰度发布 |
| MOD-9 | 制品库 | 制品列表/详情 |
| MOD-10 | 权限 / 访问控制 | 组件详情权限 Tab + 平台管理 |

### 后续 Later（刻意不做 / 待补）

- ❌ 暗色模式（令牌已预留 Action Blue 深色变体，后续迭代）
- ❌ DAG 自由画布编辑器（线性阶段组先行，`DependsOn` 并行需求出现后再升级，评估 vue-flow）
- ❌ API 管理模块（新平台无此后端域）
- 🟡 G7 权限校验 TODO（安全债，非功能阻断，最后处理）
- 🟡 R1–R3 runner 生产化（见附 B）

---

## 5. 信息架构

**布局决策（IA v2）**：全局导航第一公民 = **功能菜单**（非服务树）；服务树降级为独立页面（master-detail）；流水线编排采用**阶段组横向流**；设计风格沿用 CONSOLE-DESIGN 令牌，布局重写不动视觉系统。

**功能菜单（4 项）**：

| 组 | 菜单项 | 路由 | 说明 |
| --- | --- | --- | --- |
| 工作台 | 总览 | `/dashboard` | KPI + 最近运行 |
| 工作台 | 服务树 | `/service-tree` | 唯一资源定位入口；点组件→全屏详情 |
| 工作台 | 运行中心 | `/runs` | 唯一全局巡视入口（跨组件 + phase 过滤） |
| 平台管理 | 用户与平台权限 | `/admin/permissions` | 平台级用户/角色 |
| 平台管理 | 集群 | `/admin/clusters` | 集群健康 |

**权限双轨**：平台级用户/角色 → 平台管理；组件级 role-bindings → 组件详情「权限」Tab。

**组件详情 9 Tab（全屏子路由）**：overview / config / pipelines / runs / releases / artifacts / environments / permissions / logs。

**旧 flat 路由**（/pipelines / /releases / /artifacts / /environments / /permissions / /logs）保留 redirect，兼容 deep link。

---

## 6. 核心任务流程

### 6.0 执行模型（已确认）

- **阶段（Stage）串行**：流水线由有序阶段组成，按 `sequence` 从前到后逐阶段执行；前一阶段全部子任务完成（成功/跳过）才解锁下一阶段。
- **阶段内子任务按 `executionMode` 串行/并行**（**`ExecutionMode` 已确认放在 Stage 级**，一个阶段统一一种模式）：
  - `Parallel`（默认）：阶段内子任务并发启动，互不等待；
  - `Serial`：hub `buildSpec` 按 `DisplayOrder` 在各子任务间推导 `DependsOn` 链，严格先后；
  - **阶段完成条件**：该阶段所有子任务 `Succeeded` 或 `Skipped` 即视为完成；任一 `Failed` 且不可重试 → 阶段失败，下游不调度（DAG `Skipped`）。
- **数据与执行解耦（推送模型，已确认）**：触发 `POST /runs` 时 hub 先把"任务落实到数据库"（`pipeline_runs` + 按 DAG 种子的 `task_runs` + `dispatch_jobs`），再把整份已解析 spec 经 WebSocket **推送**给目标环境 runner；runner 在集群内建 CRD 执行，**不直连 hub DB**，状态经 WS `status_update` 流回 hub 写回 `task_runs`。详见 [hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) §6 / runner `STORY` §4.3。

### 6.1 用户旅程（正向主干）

1. **配置参数**：组件详情 → config Tab → 增/改/删 ComponentConfig（key/value/isSecret/来源/环境）。
2. **编排流水线**：服务树→组件→pipelines → 编排器阶段组横向流；加阶段时设 `executionMode`（串行/并行开关），加子任务（三态 Build/Release/Approval 抽屉表单）。
3. **触发运行**：编排器 / 组件详情 → 触发对话框（选集群 + 注入本次 params，可预填参数管理 key）→ `POST /runs`。
4. **监控运行**：运行中心 / 下钻 → 运行监控（顶部**阶段进展条** + 子任务网格 + DAG + 进度轮询 2~3s + 重新投递 + 日志面板）。
5. **审批卡点**：轮询发现 task `phase==WaitingApproval` → 审批卡 → `POST .../decision`。
6. **灰度控制**：releases → 灰度（步骤器 + 健康指标 + 暂停/晋升/回滚，经 G4 端点）。
7. **看日志 / 下制品**：日志面板（`GET /runs/:id/tasks/:name/log`）+ 制品库（签名 URL 直连）。

**关键数据链路**：参数管理（预置变量库）→ 触发参数（本次值）→ hub dispatch 前替换进任务 command/args/env。

### 6.2 异常分支（子任务 → 阶段 → 运行 三级）

| 异常 | 触发 | 子任务级 | 阶段级 | 运行级 | 用户操作入口 |
| --- | --- | --- | --- | --- | --- |
| 任务失败可重试 | 命令非零退出 / Pod OOM | `retryPolicy` 自动重试（≤N 次退避），超次置 `Failed` | 阶段标 `Failed`，下游 `Skipped` | `Failed` | 运行监控→失败节点「查看日志 / 重新投递(redispatch)」 |
| 任务终态失败 | 重试耗尽 / 硬错误 | `Failed` | 阶段 `Failed` | `Failed`；可整跑重投或单阶段重跑 | redispatch / 跳到失败阶段重跑 |
| 上游失败跳过 | 依赖任务 `Failed` | 未调度，`Skipped` | — | — | 查看 DAG 跳过关系 |
| 超时 | `timeoutSeconds` 到 | `Failed(Timeout)` | 阶段 `Failed` | `Failed` | 调大超时后重投 |
| 权限不足 | G7 未授权 / 生产环境无审批权限 | 触发即拒或运行中拒 | — | `Failed(PermissionDenied)` | 申请 role-binding / 走审批（见 §1.2） |
| 回滚 | 灰度健康度不达标 / 手动 | — | Release 阶段可回滚 | `Succeeded` 后走回滚流程 | 灰度步骤器「回滚」 |
| 审批拒绝 | 审批人 `Rejected` | Approval 任务 `Failed` | 阶段 `Failed` | `Failed` | 修正后重跑该 Approval 阶段 |

> 权限相关分支依赖 **G7**（生产环境强制审批 + 组件级 role-bindings），按 §1.2 为"基本功能后紧接着"的优先项；当前为安全债占位。

---

## 7. 页面布局

### 7.1 全局骨架（三段式：菜单 + 顶栏 + 内容）

```
┌──────────────────────────────────────────────────────────┐
│ 顶栏 56px：☰ Logo │           🔍 🔔 中/EN 👤            │
├──────────┬───────────────────────────────────────────────┤
│ 功能菜单  │  主内容区（router-view）                       │
│ 220px    │  padding 24 · Parchment 底 · max-width 1280   │
│ (可折叠   │                                               │
│  →64px)  │                                               │
└──────────┴───────────────────────────────────────────────┘
```

- 菜单：深色 `#001529`（v1 沿用老前端）或浅色（Ink 文字 + Action Blue 选中）；选中项左侧 3px Action Blue 指示条。
- 顶栏右侧：语言切换 / 通知 / 用户下拉。面包屑随路由变化（Org / Service / Component / Pipeline）。

### 7.2 总览 Dashboard

4 KPI 卡（运行数/成功率/活跃环境/注册集群）+ 最近运行表格 + **异常 Runner 提示条**（离线集群 >0 时显示）。

### 7.3 服务树页（master-detail）

左侧 300px 树面板（搜索 + 虚拟滚动 + hover「+」加子节点），右侧详情面板（基本信息 + 子节点列表 + 组件→跳详情）；操作：新增子节点/编辑/删除。

### 7.4 组件详情（全屏子路由 Tab 化）

服务树点组件 → 全屏 `/components/:id`（面包屑 + 头部 + Tab 横排 `<router-view>`）。9 Tab 内容见 §5。

### 7.5 流水线编排（阶段组横向流）

```
┌──────────────────────────────────────────────────┐
│ build-test [编辑YAML] [+新建阶段] [▶触发]          │
│ ┌─────┐  → ┌─────┐  → ┌─────┐  阶段组横向流        │
│ │①构建│    │②测试│    │③发布│                      │
│ │任务a│    │任务c│    │任务d│  阶段内任务纵排      │
│ │任务b│    │     │    │任务e│                      │
│ └─────┘    └─────┘    └─────┘                      │
└──────────────────────────────────────────────────┘
```

- 阶段号带状态色；任务卡类型图标（⌘ Build / ⬇ Release / ✓ Approval）；点击开三态子任务抽屉。
- 每个阶段头部有**串行/并行开关**（`executionMode`，已确认 Stage 级）；`Serial` 时阶段内任务按 `DisplayOrder` 纵排并标注 `DependsOn` 链，`Parallel` 时并行平铺。阶段间恒为依赖（前一阶段完成才解锁）。`DependsOn` 自由画布待并行需求明确后升级（评估 vue-flow）。

### 7.6 运行监控（DAG + 日志面板）

运行头部（#run / phase / 触发人 / 预计耗时 / 重新投递）+ **顶部阶段进展条**（每阶段一个状态色块 + X/Y 完成度，数据来自 `GET /runs/:id/stage-progress`）+ **子任务网格**（并行阶段平铺多卡、串行阶段进度链）+ DAG 横向流（节点按状态描边）+ 选中任务详情（命令/镜像/重试/退出码/进度）+ 日志面板（v1 归档于对象存储，v2 接实时流）。**高频轮询** `GET /runs/:id/progress`（2~3s），阶段卡顺带 `stage-progress` 派生刷新。审批节点展开操作区；失败节点红描边 + 查看日志 + 重新投递。

### 7.7 发布/灰度

步骤器（10%→50%→100%）+ 健康指标 3 卡 + 控制按钮（暂停/晋升/回滚）+ 规则说明。

### 7.8 其余列表页

制品库/环境/权限 = 「筛选栏 + 表格 + 分页 + 行内操作」标准布局。

### 7.9 权限与审批 UX（设计已落，待实现；对应 [hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）

> 授权分层与后端表设计见 [hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) §7：**Keycloak 管身份、k8s 管 runner 部署边界、hub 内两层 RBAC + 审批表**。前端只消费 hub 鉴权结果。钢人论证见对话记录（结论：组件级权限以"管理员/组映射为主" → 不引入 Keycloak UMA；默认审批人 = 组件 owner/管理员）。

**授权分层（前端视角）**

| 层 | 前端表现 | 数据来源 |
| --- | --- | --- |
| 平台级 | 顶部导航/页面按 `platform_role` 显隐；设置页仅管理员可见 | hub `platform_role_bindings`（KC 组映射，§7.2） |
| 组件级 | 组件详情「成员与角色」Tab；按 `component_role` 控制按钮 | hub `component_role_bindings`（§7.3） |
| 审批 | 运行监控 Approval 节点展开审批卡（§7.6） | hub `pipeline_approvals`（§7.4） |

**平台级权限页（页面 × 增删改查颗粒度全面分析，对应 §7.2）**

平台管理员在「设置 → 平台权限」管理 `keycloak_group → platform_role` 映射。各页面颗粒度：

| 页面 / 资源 | 查看 | 新增 | 修改 | 删除 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 总览 Dashboard | ✅ 登录用户 | — | — | — | 只读聚合 |
| 服务树 | ✅ | 🔒 `org:manage` | 🔒 `org:manage` | 🔒 `org:manage` | 组织/目录管理归平台管理员 |
| 组件（列表/详情） | ✅ 平台级 view | 🔒 `component:create`（全局） | 组件级 `component:update` | 组件级 `component:delete` | 单组件 CRUD 走组件级角色 |
| 流水线（编排/触发） | 组件级 `pipeline:read` | 组件级 `pipeline:create` | 组件级 `pipeline:update/delete` | 组件级 `pipeline:delete` | 触发 = `pipeline:trigger` |
| 配置 config | 组件级 `config:read` | — | 组件级 `config:update` | — | 仅修改 |
| 运行监控 / 日志 | 组件级 `pipeline:read` | — | — | — | 随流水线权限 |
| 发布/灰度 | 组件级 `pipeline:read` | — | 🔒 `release:manage`（建议 editor/approver） | — | 灰度控制收紧 |
| 制品库（§7.8 已列） | 组件级 `artifact:read` | — | — | 🔒 `artifact:delete`（管理员） | 下载 = read |
| 设置页（平台） | 🔒 `user:manage`/`org:manage` | 🔒 | 🔒 | 🔒 | 仅平台管理员 |

> 🔒 = 需对应角色；未持有则按钮隐藏 + 路由守卫拦截（见错误态）。

**组件级「成员与角色」Tab（对应 §7.3）**

组件详情新增 Tab「成员与角色」，管理 `component_role_bindings`：

| 操作 | UI | 权限要求 |
| --- | --- | --- |
| 查看成员列表 | 表格（用户/组、角色、来源） | `component:read` |
| 添加成员/组 | 抽屉：选用户或 KC 组 + 选角色(viewer/editor/approver) | `component:update` |
| 修改成员角色 | 行内下拉 | `component:update` |
| 移除成员 | 行内删除（确认） | `component:update` |

- 三种组件角色：`component-viewer`（只读）/ `component-editor`（读写+触发+配置）/ `component-approver`（+`approval:approve`）。
- **默认成员（创建组件时自动生成，满足"默认审批人=owner/admin"）**：组件 owner → `component-approver`；组件 admin 组 → `component-editor`（见 [hub 数据模型 §7.3/§7.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）。
- 权限实时生效；无权限按钮在界面禁用/隐藏，而非仅报错。

**审批卡 UX（对应 §7.4 / §6.2 审批分支）**

运行监控（§7.6）中 Approval 子任务 `phase==WaitingApproval` 时展开审批卡：

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

---

## 8. 交互细节与状态

### 8.1 状态色（唯一权威，徽章/节点/箭头一致复用）

| 状态 | 底色 | 文字/点 | 用途 |
| --- | --- | --- | --- |
| Succeeded | `#E6F4EA` | `#1E8E3E` | 成功 |
| Running | `#E8F0FE` | `#0066CC` | 运行中 |
| Failed | `#FCE8E6` | `#D93025` | 失败 |
| Pending | `#F1F3F4` | `#5F6368` | 待执行 |

- DAG 节点描边：成功 1px 绿 / 运行 2px 蓝 / 待执行 1px 灰 / 失败 1px 红（粗细区分"已完成/当前活跃"）。
- 步骤器节点同规则，active 步骤 2px 蓝；箭头与左节点状态同色。
- KPI 数值 Ink / Action Blue，指标向好时用绿（Succeeded 语义）。

### 8.2 各页面四态（空 / 加载 / 错误 / 成功）—— 双向钢人论证后补充

> 先不盲目给每页塞四种状态。对每类状态做"是否必要 + 触发条件 + 替代方案"的双向论证，再落到逐页映射。结论：**加载态收敛为"路由首屏骨架"，轮询刷新不进加载态；成功态不作独立整页态（用 toast + 数据呈现）；空态与错误态是真正必须设计的两种。**

**状态分类论证**

| 状态 | 正方（必须有专门态） | 反方（可省 / 降级） | 结论 |
| --- | --- | --- | --- |
| 加载态 | 首屏无数据时应占位，防"白屏被误判为坏了" | 应用每 2~3s 轮询，若每次轮询都弹骨架会闪烁；数据已呈现时轮询只是后台更新 | **仅路由首次加载用骨架屏**；轮询刷新只加极轻量"刷新中"点状指示（或不显式提示），不进入加载态 |
| 空态 | 首次使用（用户自建集合：流水线/运行/发布/配置/制品）无数据时，需引导"如何创建" | 项目用读时自举默认数据（服务树/组件有默认值），核心实体不易空；空态仅作用于用户生成集合 | **必须有，但作用域收敛到用户生成集合**；首屏给出"新建"引导而非空白 |
| 错误态 | 网络/5xx/404/权限(G7) 必须可见，否则用户以为卡死 | 过度错误态会吓人；部分错误可被轮询自愈（临时断网恢复后数据回来） | **必须有，且区分"可重试"与"终态"**：网络/5xx→重试按钮；G7 权限拒绝→引导申请 role-binding（见 §1.2），不只是一句报错 |
| 成功态 | — | 控制台里"成功"通常是瞬时确认 + 数据出现，独立整页成功态罕见且易过度设计；运行监控的 Succeeded 是**数据态**（§8.1 状态色）而非页面态 | **不作独立整页态**：用 toast + 数据呈现（如列表新增一行、运行变绿）；仅 Run Monitor 通过 §8.1 状态色表达成功 |

**逐页四态映射**

| 页面 | 空态（作用域） | 加载态（仅首屏骨架） | 错误态 | 成功态（toast + 数据） |
| --- | --- | --- | --- | --- |
| 总览 Dashboard | 无空态（KPI 为 0 也算数据） | 首屏骨架 + KPI 卡占位 | 聚合接口失败→重试；异常 Runner 提示条（§7.2） | 刷新后数值更新（无独立成功态） |
| 服务树 | 极少空（自举默认）；真空闲时"暂无节点 + 新增子节点" | 树面板骨架 | 拉取失败→重试；G7 无读权限→提示申请 | 新增节点后树展开并定位 |
| 组件详情（各 Tab） | 各 Tab 内用户集合为空时引导（如 pipelines Tab 无流水线→"编排第一条流水线"） | Tab 首屏骨架 | Tab 数据失败→重试；无组件读权→G7 引导 | 操作后对应行/项出现 |
| 流水线编排 | 无流水线→画布空态"新建阶段开始编排" | 打开编排器骨架 | 保存/校验失败→行内错误 + 重试 | 保存成功 toast + 阶段/任务落盘呈现 |
| 运行监控 | 运行中心列表空→"触发一次运行"；单运行不存在→404 引导 | 首屏阶段卡/网格骨架 | 进度接口失败→重试；运行被 G7 拦截→权限引导 | 阶段变 Succeeded（§8.1 状态色），无独立成功页 |
| 灰度发布 | 无 Release→"发起一次发布" | 步骤器骨架 | 健康度拉取失败→重试；生产环境无审批权→G7 引导 | 步骤晋升 toast + 权重变化 |
| 日志面板 | 日志为空（运行刚起/无输出）→"等待输出" | 流式连接建立中骨架 | 日志拉取/流失败→重试；无读权→G7 引导 | 日志持续追加（流本身即"成功"） |
| 制品库/环境/权限（列表页） | 集合空→"上传/新建"引导 | 表格骨架 | 列表失败→重试；权限不足→G7 引导 | 新增行呈现 |

> 统一组件：`<EmptyState icon+title+action>`、`<ErrorState message+retry>`、`<Skeleton>`（仅首屏）、`<Toast>`（成功/轻错）。空/错态在 G7 落地后需接"申请权限"入口（见 §1.2）。

### 8.3 关键交互反馈规则

- 触发运行：对话框校验集群必选；提交后跳运行监控或运行中心。
- 重新投递：运行失败/卡住时按钮（`redispatch`），需确认避免重复派发。
- 审批：批准/拒绝均需填意见；拒绝后运行终止并标记。
- 参数管理删除：后端曾有 501（G3 已修），前端保留容错 toast。

---

## 9. 视觉设计系统

### 9.1 设计原则

| 原则 | 说明 |
| --- | --- |
| Apple 风格克制 | 仅必要处用阴影；列表/卡片用 1px hairline；背景留白克制 |
| 药丸 CTA | 主操作 9999 圆角药丸；次操作矩形 8/10 圆角描边 |
| 状态色语义化 | 4 档状态色在徽章/节点/箭头一致复用 |
| 结构先行 | 顶栏 56px + 侧栏 220~280px + 主内容三段式贯穿全站 |
| 信息密度可调 | 表格/表单 13~14px；标题 24~28px；大数字 32px；脚注 12px |

### 9.2 色板

| Token | Hex | 用途 |
| --- | --- | --- |
| Action Blue | `#0066CC` | 主操作/链接/选中/Running |
| Ink | `#1D1D1F` | 一级文字/深色按钮 |
| Near-Black | `#272729` | 备选深色填充 |
| Parchment | `#F5F5F7` | 画布底色 |
| Hairline | `#E0E0E0` | 卡片描边/分隔线 |
| Sub Hairline | `#F0F0F2` | 表格行间分隔 |

### 9.3 字体

- 字体：Inter（数字/拉丁）+ Noto Sans SC（中文）。
- 字号阶（px）：12 caption / 13 small / 14 body / 17 subtitle / 24 / 28 title / 32 display。
- 标题字重 600（徽章 Inter Bold，标题 Noto Sans SC SemiBold）。

### 9.4 间距与圆角

- 间距：4 / 8 / 12 / 16 / 24 / 32。
- 圆角：药丸 9999 / 卡片 12 / 徽章 9999 / 图标按钮 8 / Tag chip 6。

### 9.5 组件

- 按钮：`Primary`（药丸/Action Blue/白字）/ `Dark`（药丸/Ink/白字）/ `Pearl`（矩形/白底 hairline/深字）。
- 徽章：药丸 + 状态点 + 文字。
- 顶部导航：56px 高 + 底部 hairline + Logo + 5 入口 + 右侧搜索/铃铛/头像。
- 侧栏服务树（旧）：240px + Parchment 底 + 节点 30px 行高 + active 节点 E8F0FE 底 + Action Blue 文字（IA v2 已改为功能菜单）。

---

## 10. 测试与迭代计划

### 10.1 验证门禁（宣称完成前必须全绿）

- `console`：`vue-tsc --noEmit` + `vite build` ✅
- `hub`：`go build ./...` + `go vet ./...` + `go test ./internal/...` ✅
- `runner`：`go build ./...` + `go vet ./...` ✅
- 端到端：建组件→配参数→编排三态→触发→监控/审批→灰度控制→看日志→制品上传/下载，全链路通。

### 10.2 用户侧验收（按目标执行、达成目标）

> 用户测试计划 = **实际按 §1 的北极星目标执行一遍，确认目标达成**，不做脱离目标的"可用性走查"。验收门槛：平台工程师（或陌生同事）**仅靠控制台 UI**，不碰命令行/代码，走通以下端到端链路且结果符合预期。

**验收即目标**：通过纯界面交互，把软件「构建 → 测试 → 发布到多套环境」完整跑通。

**验收用例（对应 §1.1 四类流水线模式，必须全部可经 UI 触发并达成）**

| 用例 | 操作（纯 UI） | 达成判据（目标是否达成） |
| --- | --- | --- |
| 环境准备 | 服务树→建组件→建组件对接环境 | 组件与环境在树/列表中可见、可选 |
| 日常流水线 | 编排[构建→部署测试]→触发→监控阶段进展→看日志 | 软件构建成功并部署到测试环境，阶段卡全绿 |
| 版本归档 | 编排[建版本分支→构建→归档]→触发→监控 | 产出可复用"版本包"进入制品库 |
| 转测流水线 | 编排[版本包获取→发布转测]→触发 | 版本包从制品库消费并发布到转测环境 |
| 生产流水线 | 编排[版本包获取→审批→多环境发布]→触发→审批卡点决策→多环境发布 | 经审批门禁后发布到多套环境，目标达成 |
| 异常回归 | 故意令某任务失败→验证重试/重投/阶段跳过（§6.2）→回滚（灰度） | 异常分支行为符合 §6.2，不卡死、可恢复 |

**验收信号（关注失败点）**
- 在哪一步用户"不知道点哪" → 编排/触发/监控的信息架构问题；
- 在哪一步"点了没反应/报错看不懂" → 错误态（§8.2）或后端契约问题；
- 目标未达成（如发布没到多环境、版本包没复用）→ 链路/权限(G7)问题。
- **验收通过 = 上述用例全部以纯 UI 操作达成目标，且无人需借助 kubectl/代码兜底**。

### 10.3 自动化功能测试：API 各阶段组合（后期）

> 用户侧验收（§10.2）证明"人能用 UI 走通目标"；但"各阶段组合是否都正确"属于**功能正确性**范畴，应脱离 UI、用 API 直接模拟组合来验证——这部分**计划在后期独立的自动化测试项目中实现**，本报告先锁定其范围与契约依赖，避免将来重新论证。

**两层验证的关系**
- §10.2（UI 验收）= 用户视角：**目标是否可达成**；覆盖"端到端跑通"，不穷举组合。
- §10.3（API 组合测试）= 工程视角：**各阶段组合的编排/执行逻辑是否正确**；穷举组合、可重复、CI 可跑。两者互补，不互相替代。

**测试对象与入口（直连 hub API，不经 UI）**
- 复用 hub 的契约（`POST /pipelines` 编排、`POST /runs` 触发、`GET /runs/:id/progress` + `GET /runs/:id/stage-progress` 查进展，详见附 A 与 [hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) §6.5）。
- 绕开 console 前端，直接构造 pipeline spec（stages + tasks + `ExecutionMode` + task 类型 Build/Release/Approval），调 hub 触发，断言 `task_runs`/`pipeline_runs` 的最终态与阶段进展聚合符合 §6 执行模型。

**组合维度（穷举的"各阶段组合"指这些）**
1. **阶段顺序排列**：日常 / 版本归档 / 转测 / 生产 四类（§1.1）及其变体；
2. **阶段内 `ExecutionMode`**：Serial vs Parallel（§6.0、[hub 数据模型 §6.4①](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）；并行下验证"子任务并发完成=阶段完成"、串行下验证 `DependsOn` 链顺序；
3. **任务类型组合**：Build / Release / Approval 的任意混入，尤其 Approval 在不同阶段位置（中段挂起、末段门禁）；
4. **异常注入**：在阶段首/中/末注入任务失败，断言 §6.2 的"可重试 / 终态失败 / 上游 Skipped / 超时 / 回滚"分支行为；
5. **多环境发布**：生产流水线一次触发发布到多套环境的 fan-out 正确性。

**落地形态（计划，非本报告交付物）**
- 独立的自动化测试项目，按上述维度参数化用例；CI 中对接一套最小 runner（或 stub executor）跑通真实 stage/子任务调度逻辑。
- 断言基准 = [hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) §6 的执行模型 + 进展回收契约；用例即契约的活文档。

---

## 附 A：API 契约与模块 Backlog（事实来源）

### A.1 hub `/api/v1` 端点契约（console 桩状态）

| 域 | 方法 & 路径 | console 桩 |
| --- | --- | --- |
| Org | `GET /orgs` | org.ts ✅ |
| Org | `GET /orgs/:id/service-tree` | org.ts ✅ |
| Catalog | `GET /service-trees/:treeId/services` | catalog.ts ✅ |
| Component | `GET /services/:serviceId/components` | component.ts ✅ |
| Config | `GET /components/:componentId/configs?environmentId=` | component.ts ✅ |
| Config | `PUT /components/:componentId/configs/:key` | component.ts ✅ |
| Config | `DELETE /components/:componentId/configs/:key` | component.ts ✅（G3 已修） |
| Cluster | `GET /clusters` | cluster.ts ✅ |
| Environment | `GET /components/:componentId/environments` | environment.ts ✅ |
| Pipeline | `GET /components/:componentId/pipelines` | pipeline.ts ⚠（旧假定单查端点，后端无） |
| Stage | `POST/GET/DELETE /pipelines/:pipelineId/stages` `/stages/:id` | pipeline.ts ✅ |
| Task | `POST/GET/PUT/DELETE /stages/:stageId/tasks` `/tasks/:id` | pipeline.ts ✅ |
| Run | `POST /pipelines/:pipelineId/runs` | run.ts ✅ |
| Run | `GET /pipelines/:pipelineId/runs` `/runs/:id` `/runs/:id/tasks` | run.ts ✅ |
| Run | `GET /runs/:id/progress` | run.ts ✅ |
| Run | `GET /runs/:id/stage-progress` | run.ts（**确认新增**；后端按 `StageName` 聚合下发，见 [hub 数据模型 §6.3/§6.5](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)） |
| Run | `POST /runs/:id/redispatch` | run.ts ✅ |
| Run | `POST /pipelines/:pipelineId/runs/:runId/tasks/:taskName/decision` | run.ts ✅（后端 `h.Approve` 已实现） |
| Artifact | `GET /components/:componentId/artifacts` `/artifacts/:id` `/download` `/DELETE` | artifact.ts ✅ |
| Permission | `POST/GET /components/:componentId/role-bindings` `/DELETE /role-bindings/:id` `GET /roles` `GET /users` | permission.ts ✅ |

**关键事实**：后端无 `GET/POST/PUT/DELETE /pipelines/:id`（仅按组件列出）→ 流水线自身 CRUD 曾受 G1 影响，G1 已修；无 `PUT /stages/:id`（G6 已修）；无独立 Rollout 控制/日志读取端点（G4/G2 已修）。

### A.2 三层数据模型

| 层 | 来源 | console 关注 |
| --- | --- | --- |
| 定义态 | `PipelineStage` + `PipelineTaskTemplate` | 编排器画法 / 子任务表单 |
| 运行态 | `PipelineRun` + `TaskRun` | DAG / 进度轮询 |
| 参数态 | `ComponentConfig` + `TriggerRequest.Params` | 参数管理 + 触发注入 |

### A.3 三态子任务表单（MOD-3，核心）

| 类型 | 含义 | 表单字段 |
| --- | --- | --- |
| **Build** | 命令型：工具镜像跑命令 | `image` + `command`([]string) + `args` + 可选 `scriptPath` + `produces`/`consumes` + `timeoutSeconds` + `retryPolicy` |
| **Release** | 声明式施加软件单元 | `releaseConfig.chart`(repo/name/version 或 chartUrl) + `releaseConfig.values` + `releaseConfig.manifest`；带 `rolloutConfig` 走金丝雀 |
| **Approval** | 人工卡点 | `approvalConfig`（审批人/条件） |

保存 = `POST /stages/:stageId/tasks`（新建）或 `PUT /tasks/:id`（更新）。

---

## 附 B：当前未完成项（2026-09-09 快照）

> G1–G6 已于 2026-09-06 全部落地，以下仅剩残留：

| ID | 项 | 影响 | 阻塞 | 建议 |
| --- | --- | --- | --- | --- |
| **G7** | service 层权限校验多处 TODO | 安全债（非功能阻断） | 🟡 低 | 设计已落（[hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) 两层 RBAC + 审批表 / console §7.9 UX）；待实现：`component.go`/`org.go`/`environment.go`/`catalog/service.go` 接入 §7.5 Enforcement |
| **R1** | chart/manifest 施加生产化 | runner 发布链路 | 🟡 | chart 仓库鉴权接入；values `--set` 注入端到端验证 |
| **R2** | 日志持久化读路径 | 运行日志 | 🟡 | 已由 G2 hub DB 读路径解决，runner 侧归档可走 G5 upload-url |
| **R3** | 镜像与默认参数固化 | runner 生产镜像 | 🟡 | git/artifact/helm 镜像替换为 pinned 生产镜像；常量配置化（registry 确定后定值） |

---

## 附：通用验收标准

1. **一句话测试** —— 能否一句话说清：给平台工程师，统一管理软件分发全链路的控制台。
2. **5 秒测试** —— 陌生用户看首屏 5 秒内明白"这是干嘛的"。
3. **三步测试** —— 最高频操作（触发一次运行）能否 3 步内完成。
4. **灰阶测试** —— 去掉颜色后，层级与状态是否仍靠形状/大小/位置分辨（状态色已同时用图标+文字表达）。
5. **陌生人测试** —— 找一个没见过产品的人试做一次发布，观察卡在哪（【待补充】测试任务设计）。
