> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · §1 问题与目标 / §2 用户与场景 / §3 竞品与参考
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

- **产品定位**：SDP（Software Distribution Platform）Console 是平台的前端控制台，目标是通过**纯界面交互**，把软件的「构建 → 测试 → 发布到多套环境」完整跑通。技术栈 Vue 3 + Pinia + Vue Router + OIDC/Keycloak。
- **核心目标（一句话）**：用户不必写脚本或登录多套系统，在控制台内按「服务树 → 组件 → 环境 → 配置 → 流水线 → 运行」的引导路径，把软件成功发布到多套环境（测试 / 转测 / 生产等）。
- **目标用户**：平台管理员 / 组件负责人 / 研发工程师 / 审批人 / 集群接入方（角色定义见 [`hub/user-stories.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/user-stories.md)）。
- **重设计动因（均基于代码事实）**：

| # | 现状问题 | 证据 |
| --- | --- | --- |
| P1 | 导航太薄、资源埋太深：只有 4 项功能菜单，组件/流水线/发布/制品/环境/权限全塞进"组件详情 9 Tab"；无法跨组件巡视流水线/发布/待审批 | `layout/MainLayout.vue` `groups` 仅 4 项 |
| P2 | 总览是 hack：沿 `Org→Tree→Service→Component→Pipeline` 遍历，只为取"第一条流水线的最近运行"当全局运行；KPI 亦为 O(n) 累加，脆弱 | `views/DashboardView.vue` `onMounted` |
| P3 | 组件详情 9 Tab 过载，分组的"心智模型"不清晰（一等公民 vs 次级混排） | `views/ComponentDetailView.vue` `tabs` 9 项 |
| P4 | 视觉调性内耗：内容区 Apple 克制浅色，导航却是 antd 海军蓝 `#001529`；无暗色模式 | `src/styles/tokens.css` `--menu-bg: #001529` |
| P5 | 流水线 CRUD 缺失：**无新建入口**（PipelinesTab 注释明说"仅编排已有"）；编辑器只允许 `kind==='build'`；**无流水线级删除**；`pipelineApi.update` 存在但 UI 从未调用 | `component/tabs/PipelinesTab.vue` L36、`openEditor()` L24；`api/pipeline.ts` L67 `createCrud('/pipelines')` |
| P6 | 资源导航无规模化设计：服务树只有"跳进去看全树"一种模式，组件增长后**逐层展开找节点**不可用；且无搜索、无懒加载、无虚拟滚动 | `views/ServiceTreeView.vue`（现状为一次加载 + 树形渲染） |

- **成功标准**：
  - 端到端一次发布可在控制台内完成，无需跳出到 CLI / K8s；
  - 同一组件可对接多套环境（测试 / 转测 / 生产），流水线按环境差异注入参数；
  - 运行态（DAG / 进度 / 日志 / 灰度）实时可见；
  - 生产发布可经审批门禁，且权限管控在基本功能完成后**紧接着落实**（见 §1.2）；
  - 修订 S1｜**任意资源直达**：**全局搜索（⌘K）输入 → 点结果**，≤2 步（键盘可达）进入任一组件/流水线。~~初稿"左栏常驻树 ≤1 击"已废弃~~；~~v2「左栏最近访问 ≤1 击」已废弃（v4 删该分组）~~；
  - 修订 S2｜**全局可巡视**：跨组件浏览全部**运行 / 发布**，无需逐树钻取 —— 统一收在左栏「运行中心」的**两个视图**内（v4：不再为流水线/发布各占一个菜单项；v4.4：也不再有"流水线"视图）；
  - 新增 S3｜**流水线全生命周期在 UI 内闭环**：新建 → 编排 → 保存 → 编辑 → 删除，无需 CLI；
  - 新增 S4｜**双主题可用**：明/暗主题切换后，层级与状态信息均不依赖颜色仍可分辨；
  - 修订 S5｜**规模不变量**：左栏条目数**恒为 5 且与资源数量/用户行为均无关**（v4：删掉"最近访问"后，左栏不再有任何"随使用变长"的区域）；应用启动**不发起任何资源树请求**；服务树页首屏只请求一层，展开才请求下一层。【用户反馈约束】

### 1.1 标准流水线模式（4 类，编排模板参考）

流水线 = 阶段（Stage）的有序组合，**阶段串行**执行；每个阶段内含若干子任务（Task），子任务按该 Stage 的 `executionMode` **串行或并行**执行（**已确认 `ExecutionMode` 放在 Stage 级**），全部子任务完成 = 该阶段完成，才进入下一阶段。任务三态 `Build` / `Release` / `Approval`（见附 D.3）。以下 4 类为典型模式，供在控制台编排时参考：

| 模式 | 阶段 / 任务组合 | 说明 |
| --- | --- | --- |
| **日常流水线** | 构建(Build) → 部署到测试环境(Release→测试 env) | 每次提交后快速验证，部署到测试环境 |
| **版本归档流水线** | 创建版本分支 → 构建(Build) → 归档(Release→制品库/对象存储) | 产出可复用的"版本包"，供转测/生产流水线获取 |
| **转测流水线** | 版本包获取(Consumes 归档产物) → 发布到转测环境(Release→转测 env) | 消费版本归档产物，发布到转测环境 |
| **生产流水线** | 版本包获取 → 审批(Approval) → 多环境发布(Release→多 env) | 经审批门禁后，向多套环境依次/并行发布 |

> 注：「版本包获取」对应任务间的 `Produces/Consumes` 产物依赖（[hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）；「多环境发布」在同一组件下多环境目标内完成（Pipeline 锚定单 Component 不变式）。
> 原型中的 JSON 映射：这 4 类对应 `PIPELINE_GRAPHS` 的 `日常流水线` / `版本归档` / `转测流水线` / `生产发布`；**阶段内任务的 `type` 由配置派生**（填了发布目标 → `Release`，填了审批人 → `Approval`，否则 `Build`），编辑器只显示产品语言，不露三态原词（见 §7.4）。

### 1.2 落地顺序（基本功能优先，权限紧随）

1. **先完成基本功能**：服务树 → 组件 → 环境 → 配置 → 流水线创建/编排/运行 → 多环境发布全链路贯通（console MOD-0~MOD-10 + hub G1–G6 + runner R1–R3）。
2. **权限管控已落地**：基本功能可用后实现的权限体系——平台级用户/角色（`platform_roles`/`platform_role_bindings`）+ 组件级 role-bindings（`component_roles`/`component_role_bindings`，subject 支持 user/group）+ 审批子系统（`pipeline_approvals`，含防自审）——已于 P1/P2/P3 整体落地（见 [hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）。G7（service 层 §7 Enforcement）已在 P3a 完成。

---

## 2. 用户与场景

角色（对齐 [`hub/user-stories.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/user-stories.md)）：平台管理员、组件负责人、研发工程师、审批人、集群接入方。

- **场景 A｜编排与触发（组件负责人 / 研发）**：服务树建组件 → 配环境与参数 → 编排日常 / 版本归档流水线 → 触发运行 → 运行中心看 DAG 进度。
  - *易错点*：参数管理是"预置变量库"，触发参数是"本次运行的具体值"，两者在触发对话框组装——概念易混。
- **场景 B｜版本流转（研发）**：版本归档流水线产出版本包 → 转测流水线获取并发布到转测环境 → 生产流水线获取、过审批、多环境发布。
- **场景 C｜灰度与审批（发布负责人 / 审批人）**：生产流水线到 Approval 节点，审批人批准 / 拒绝；灰度发布可暂停 / 晋升 / 回滚。
- **场景 D｜接入管理（集群接入方）**：注册 K8s 集群（仅出向连接），流水线任务下发到该目标执行。
- **场景 E｜全局巡视（平台工程师 / 组件负责人）**：上班第一件事不是钻进某棵树，而是"看跨组件运行态势 + 处理待我审批 + 看失败运行"。→ 由 **左栏「运行中心」（运行 / 发布 两视图）+ Dashboard 待办区** 承接。
- **场景 F｜流水线全生命周期（组件负责人）**：在组件内新建流水线 → 编排阶段/任务 → 保存 → 后续改参数/加阶段 → 不再需要时删除。→ 由 **P5 的 CRUD 设计** 承接。**易错点**：删除流水线时历史运行是否保留、进行中运行能否删除。
- **场景 G｜主题切换（任何用户）**：白天浅色、夜间/投屏暗色；色弱或黑白打印时靠灰阶仍可辨状态。→ 由 **双主题 + 状态非纯色化** 承接。
- **场景 H｜深层资源定位（任何用户，新增）**：已知组件名（或只知道大概叫 "gateway"），要**直接到它**，不想知道它在哪个 Org/Service 下。→ 由 **全局搜索（⌘K）+ 服务树页搜索服务端 `/search`** 承接。**易错点**：搜索结果必须显示**所属路径**（`platform-eng / svc-b`），否则同名组件无法区分。
- **场景 I｜资源规模增长（平台管理员，新增）**：组件从 20 涨到 500+。→ 由 **S5 规模不变量**承接：左栏不增长、启动不拉树、树懒加载 + 虚拟滚动。

---

## 3. 竞品与参考

| 参照对象 | 借鉴点 | 避坑点 |
| --- | --- | --- |
| **Backstage** | 左栏 = 插件级导航（数量恒定）；Catalog 是**独立页**，列表 + 侧栏 filter + **服务端搜索** | **不要把 Catalog 全量树搬进左栏**——Backstage 自己也只在页内展开；树无限层会淹没导航 |
| **Argo CD** | 应用/资源全局列表 + 顶部 filter + 搜索，跨实体巡视 | 列表列过密 → 保留"实体名/所属/状态/时间"四列为核心 |
| **GitHub Actions** | workflow 列表 → 单条编辑 → run 列表 → 单 run 详情，CRUD 闭环清晰 | workflow 编辑器 YAML 化不适合非研发 → 保留可视化阶段组 |
| **GitLab / Vercel 侧栏** | 侧栏项**固定且可折叠**，项目列表放页内（`?search=`） | 项目下拉做成可搜索浮层，避免侧栏随项目数增长 |
| 旧前端 `old/go-devops/go-devops-ui` | 服务树 + 详情面板；`MainLayout`（深色菜单 + header + router-view）、`ServiceTreeManage`（搜索树 + 详情面板 + 节点操作）、`PipelineRunMap`（阶段组 + 状态图例 + 编号节点）、i18n 中/EN + 登录 | 旧版服务树**常驻侧栏**挤压主内容被否决（P6）→ 本次沿用"树放内容区、主内容不被挤压"，只升级为独立页 + 懒加载 |
| 现版本 v2 | 功能菜单 + 组件全屏 Tab | antd 海军蓝导航与浅色内容割裂（P4）→ 导航统一浅色 / 暗色双主题 |
| Tekton Dashboard / Spinnaker | 运行态 DAG 可视化、人工卡点（Manual Judgment） | — |
| ~~初稿 v1（已废弃）~~ | ~~左栏内联资源树，≤1 击直达组件~~ | ~~违反 S5：条目随组件数无界增长、启动即拉全量树 → 用户否决~~ |

---
