> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · 附 E 历史未完成项快照 + 附 G/H/I 实现落地记录（C-01/02、C-12、R-8）
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 附 E：历史未完成项快照（2026-09-09，仅供追溯）

> ⚠️ **本表是历史快照，不是当前状态**。G1–G6 已于 2026-09-06 全部落地。**当前进度请查** [`hub/STORY-BACKLOG.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md)（另有 [`plans/STATUS.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 跟踪当前状态与未完成项）。

| ID | 项 | 影响 | 快照时状态 | 后续 |
| --- | --- | --- | --- | --- |
| **G7** | service 层权限校验多处 TODO | 安全债（非功能阻断） | 🟢 已完成 | 设计已落（[hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) 两层 RBAC + 审批表 / 本文 §7.9 UX）；**P3a 已实现**：路由级 `HasPermission` 改用 §7 action、`component.go` 等接入 §7.5 Enforcement、Keycloak `groups` 经 `UserContext` 注入；console 权限页 P3c 支持 user/group 主体 + §7 角色选择器 + 自审提示 |
| **R1** | chart/manifest 施加生产化 | runner 发布链路 | 🟡 | chart 仓库鉴权接入；values `--set` 注入端到端验证 |
| **R2** | 日志持久化读路径 | 运行日志 | 🟡 | 已由 G2 hub DB 读路径解决，runner 侧归档可走 G5 upload-url |
| **R3** | 镜像与默认参数固化 | runner 生产镜像 | 🟡 | git/artifact/helm 镜像替换为 pinned 生产镜像；常量配置化（registry 确定后定值） |

---

## 附 G：实现落地记录 —— C-01 ⌘K 全局搜索 + C-02 暗色主题（2026-09-22）

> 本附是**实现态**记录（设计规格在 §5.3 / §7.1 / §7.5 / §9.1 / §9.2 / §9.5 / §9.6，**正文未改动**）。
> 目的：让"文档写了、代码里有没有"一眼可查；并把本轮**刻意不做**与**新发现的偏差**记账，
> 免得下次审计把同一批差异当新问题重新报一遍。

### G.1 落地清单

| 编号 | 项 | 落地物（console `src/`） | 规格依据 |
| --- | --- | --- | --- |
| C-02 | 双主题令牌 + 机关 | `styles/tokens.css`（`:root` / `:root[data-theme="dark"]` 双块 + `:root.gray`）、`utils/theme.ts`（纯逻辑，零 import）、`composables/useTheme.ts`（单例状态 + 副作用）、`index.html` 首屏内联引导（防白闪） | §9.2 令牌表、§9.6 主题机制、§8.1 状态色 |
| C-02 | 顶栏控件 | `layout/MainLayout.vue`：搜索(⌘K) / 主题（图标 + 动作文案）/ 灰阶 三件套 | §7.1 顶栏、§9.5 顶部导航 |
| C-02 | 左栏纠正（落 P4） | 底色由硬编码海军蓝 → `--rail-bg`（light=surface / dark=#141720）；选中态**去 3px 竖条**，改「圆角块 + `--rail-active-bg` 底 + `--rail-active-fg` 字」；条目图标换成原型 `ICON` 表的线性 SVG | §7.1、§9.2、§9.5 |
| C-01 | 搜索浮层 | `components/CommandPalette.vue`（四态 + 键盘）+ `composables/useGlobalSearch.ts`（索引/防抖/选中）+ `utils/search.ts`（**纯**打分/排序/路由/键盘，零 import） | §5.3、§7.5 |
| C-01 | 深链定位 | `views/ServiceTreeView.vue` 消费 `?node=<id>`：命中即选中该节点；不在当前组织时逐个换组织重载后查 | §5.3「Service → 服务树页定位」 |
| C-01 | 索引来源 | `composables/useResourceMap.ts` 扩展出 `services` / `components` 池（与运行中心**共用同一次**树遍历，不多打一遍 API） | 附 A N-8（降级路径） |

**分层理由（顺手保留了可测性）**：纯逻辑 → `utils/*.ts`（零 import，node 原生类型剥离可直接 import 断言）；
副作用（localStorage / DOM 属性 / API）→ `composables/*.ts`；渲染 → `.vue`。
与 `constants/runCenter.ts` + `scripts/runcenter-url-smoke.mjs` 既有手法一致。

### G.2 与设计规格的**显式差异**（3 条，均已记账）

| # | 差异 | 裁定与理由 |
| --- | --- | --- |
| 1 | **顶栏没有面包屑** | §7.1 要求面包屑只有顶栏一条、内容区不再重复。实现态仍是各页 `.page-head > .crumb` 自带。清理要同时改 10+ 个 view（且需先裁定各页段位），**本轮不做** —— 不与 C-01/C-02 混进同一个 diff。作为独立任务排期 |
| 2 | **顶栏没有「ⓘ 设计备注」** | §8.4 决定把那 6 处内联后端依赖说明收进该开关。但备注内容是**按视图维护的评审数据**（原型 `NOTE` 表），console 尚无该数据源。按本文档自己的铁律「不渲染无 handler 的装饰控件」，**先不渲染该按钮** —— 不做一个点了没反应的开关 |
| 3 | **用户区在顶栏，不在左栏底部** | §5.1 的 ASCII 示意图把用户画在左栏底部，但**同一段的括号说明**「主题/灰阶/设计备注在顶栏」、§9.5「顶部导航：56px 高 + … + 头像」、以及原型 `renderRail()`（不输出 `.rail-foot`，用户菜单在 `.topbar`）三处一致指向**顶栏**。按原型 + §9.5 落在顶栏；§5.1 的示意图视为过期示意（未回改正文，先在此记录） |

### G.3 门禁与验证

| Gate | 命令 | 结果 |
| --- | --- | --- |
| 类型 | `vue-tsc --noEmit` | ✅ |
| 构建 | `vite build` | ✅（暗色块与 `--rail-*` / `--term-*` 均已进产物 CSS，压缩后仍为 `:root[data-theme=dark]`） |
| 既有契约冒烟 | `pnpm test:runcenter` | ✅ 16/16（未回归） |
| 新增契约冒烟 | `pnpm test:theme-search` | ✅ 25/25 |

`scripts/theme-and-search-smoke.mjs` 的覆盖（node 原生类型剥离**直接 import 出厂 `.ts`**）：

- **主题**：存储键/属性名固定、大小写与垃圾值归一、`localStorage` 优先于系统偏好、灰阶只认字符串 `'1'`、按钮文案 = 下一步动作；
- **搜索**：20 条上限与 200ms 防抖常量、⌘K/Ctrl+K 判定（裸 `k` 不算）、**精确命中排第一**、名称命中优于路径命中、同分保持原序（结果可重复）、三条打开路由（组件/流水线/Service）、`?node=` 深链**确实被消费**、↑↓ 不环绕且无选中时按下键从第一条开始；
- **防白闪漂移**：静态断言 `index.html` 内联脚本的键名/属性/取值与 `utils/theme.ts` 同步，且脚本位于 `</head>` **之前**；
- **防回潮**：静态断言暗色块存在且**真的覆盖**关键令牌、左栏走 `--rail-bg`、海军蓝与 3px 竖条不再以**声明**形式出现（注释里保留改动说明不算违规）、`PermissionsTab` 不再引用未定义令牌。

**未跑（如实标注）**：真实浏览器交互（无头 e2e 未接）—— 浮层的键盘导航、主题持久化在 DOM 侧的端到端行为**没有**自动化覆盖，只有纯逻辑单测 + 源码静态断言。

### G.4 顺带修掉的真实缺陷（均不在原清单）

| # | 缺陷 | 后果 |
| --- | --- | --- |
| 1 | `PermissionsTab.vue` 引用三个**从未定义**的令牌 `--border` / `--primary` / `--muted-fg` | 整条声明被浏览器丢弃 → 该页边框与文字色**静默失效**；已统一到 §9.2 权威名 |
| 2 | 左栏底色是固定海军蓝 `--menu-bg: #001529`，与 §9.2「light 全浅、dark 全深，消除割裂（P4）」直接冲突 | 暗色主题下唯一**不跟随**的板块；且 light 也与设计不符 |
| 3 | 日志/终端面板硬编码 `#0f172a` / `#e2e8f0`（`LogsTab` / `RunMonitorView`） | 暗色主题下与 `--bg`（#101216）几乎同色，面板**失去边界**；已抽 `--term-bg` / `--term-fg` 双主题令牌 |

---

## 附 H：实现落地记录 —— C-12 流水线全生命周期（2026-09-22）

> 承接 **附 G**（C-01 / C-02）。本附记 §6.1 · §7.4 · 附 D 的落地状态、**显式差异**与顺带修掉的真实缺陷。

### H.1 落地清单

| 位置 | 交付物 |
| --- | --- |
| 列表（§7.4） | `views/component/tabs/PipelinesTab.vue`：五列（名称 / 类型 / 版本 / 最近运行 / 操作「运行 · 编辑 · 删除」）+ 右上 `＋ 新建流水线`；「最近运行」用 `GET /runs?componentId=` **一次**取回后本地分组（避免 N+1） |
| 新建（§6.1 C1） | 名称 / 类型 / 描述 + **所属组件只读锁定** → `POST /pipelines` → 保存后**直接进编辑器** |
| 删除（§6.1 D1） | **强确认（输入名称）** → `DELETE /pipelines/:id`；成功 toast（提示"历史运行日志保留"）；`409 + {reasons}` 渲染「无法删除」弹窗，reasons **原样**来自后端、前端不加工 |
| 编辑器（§7.4） | `views/PipelineEditorView.vue`：**改直取 `GET /pipelines/:id`**；头部「编辑信息」；阶段 `◀ ▶` 重排 + 子任务 `▲▼` 重排；阶段头 `executionMode` 一键切换；工具条 `[保存] [▶ 触发] [🗑 删除流水线]` |
| 请求体预览（附 D.4） | 保存前弹 **JSON / YAML 双视图** + 端点标注 + **实际调用序列** |
| 子任务表单（附 D.3 / §7.4 拍板） | `components/TaskFormDrawer.vue`：**去掉三态原词三选一**，改为顶部展示派生出的产品语言 + 三段配置；`type` 由配置派生 |
| 纯逻辑层 | `src/utils/pipeline.ts`（零 import）：`deriveTaskType` / `taskNature` / `nextExecutionMode` / `moveItem` / `buildPipelineRequest` / `expandPipelineCalls` / `readDeleteVerdict` / `pickLatestRuns` |
| hub 侧 | `pipeline_stages.execution_mode`（`migrations/0010`）+ 模型字段 + `StageService` 枚举校验 + `PUT /stages/:id` 透传；`GET /runs?componentId=` 可选过滤 |

### H.2 与设计规格的**显式差异**（2 条，均已记账）

1. **「发布目标」不是任务级字段。** §7.4 / 附 D.3 的措辞是「填了**发布目标** → `Release`」。但 hub 的 `releaseConfig`（= runner `ReleaseSpec`）**没有**任务级"发布目标"字段 —— 目标在**触发时**由 `TriggerRequest.targetId` 选定（附 D.3 自己那句"发布目标决定它落在哪个环境"说的正是**运行级**目标）。
   - 按既有铁律「不渲染无 handler 的装饰控件」，**不新增**一个落不了库的"发布目标"输入框。
   - 派生信号改用**真实落库**的两组配置：`releaseConfig`（chart / manifest 有值）→ 发布任务；`approvalConfig.allowedApprovers` 有值 → 人工审核阶段。
   - 优先级 Release > Approval（与原型 `deriveType` 一致）；两组都填时**显式提示**"按发布任务处理，审批人将被忽略"，不静默丢弃。
   - 顺带收紧：原型用 JS 真值判断，**纯空白串会被误判为已填**（派生出 Release 却没有任何发布配置）；改为 trim 后判空。
2. **`executionMode` 的调度行为 ✅ 已落地（2026-09-23，C-06）。** 字段存得下、读得回、UI 可切换；hub `buildSpec` 为 serial 阶段按模板顺序派生「紧邻前驱」`DependsOn` 链，runner `serialBlocked()` 据此严格先后 —— serial 阶段里的子任务**不再并发启动**。（本条写于该调度落地前，已更正。）

### H.3 「保存」的实际语义（附 D.4 落差的落地形态）

hub **没有"整 DAG 一次提交"端点**，因此：

- **结构性增删**（建 / 删阶段、建 / 删 / 改子任务）走**即时落库** —— 各只对应一个已存在的端点，且新建后需要服务端下发的 id；
- **[保存]** 只冲刷三类**局部**改动：① 元信息 → `PUT /pipelines/:id`；② 每个阶段的 `sequence` + `executionMode` → `PUT /stages/:id`；③ 每个阶段内子任务的 `displayOrder` → `PUT /tasks/:id`。
- 预览面板因此**同时**展示「产品视图 body」（附 D.4 结构）与「实际调用序列」—— 只展示前者会让用户以为那一个包真的被发出去了。

### H.4 门禁与验证

```
vue-tsc --noEmit            ✅
vite build                  ✅（PipelinesTab / PipelineEditorView 均为懒加载分包）
pnpm test:runcenter         ✅ 16/16   ← 既有门禁无回归
pnpm test:theme-search      ✅ 25/25   ← 既有门禁无回归
pnpm test:pipeline          ✅ 41/41   ← 本轮新增
（hub）go build / vet / test ✅ 全绿
```

新增 `scripts/pipeline-editor-smoke.mjs`：node 直接 `import` 出厂 `.ts`（与另两个冒烟同手法）。除纯逻辑断言外，含三类**防契约回退**的静态断言：① `TaskFormDrawer` **模板**里不得出现三态原词；② 编辑器必须直取 `GET /pipelines/:id`、不得残留 `?componentId=` 反查；③ 阶段 `executionMode` 开关必须真的落库（否则就是装饰控件）。

> **断言器自身踩坑记录**：首版有两条断言误报 —— ① 把注释里**解释历史**的"无单查端点"当成过时结论；② 要求编辑器里出现 `pipelineApi.createTask`，而子任务建 / 改实际在 `TaskFormDrawer`。两条都是**校验器**的问题而非代码问题，已修正断言（并保留注释的解释力）。

### H.5 顺带修掉的真实缺陷（均不在原清单）

1. **`TaskFormDrawer` 直接违反 §7.4 拍板**：把 `Build` / `Release` / `Approval` 原词做成三选一控件暴露给用户 —— 而按拍板它们是**内部派发码**，`type` 本应由配置派生。
2. **编辑器头上挂着过时结论**：注释与实现都按"pipeline 无单查端点"绕路（`?componentId=` 反查组件流水线列表），而 `GET /pipelines/:id` **一直存在**。
3. **删除了过时的客户端闸门**：列表按 `kind !== 'build'` 拦截编辑，而 `kind` 是自由分类（hub 侧无校验），与可编排范围无关（N-7）。
4. **类名静默失效隐患**（本轮在写组件**之前**发现并对齐，未进入产物）：列表徽章原计划自造 `st-*` 类，而 `tokens.css` 已有全局 `.b-succ/.b-run/.b-fail/.b-pend/.b-warn`（§8.1 六态）—— 自造类未定义会让状态色**静默丢失**（与 C-02 那轮 `PermissionsTab` 引用未定义令牌同源）。已改为复用全局类。

## 附 I：实现落地记录 —— R-8 服务树规模化（2026-09-22）

> 承接 **附 G**（C-01 / C-02）与 **附 H**（C-12）。本附记 §4.1(R-8) · §5.2 · §5.3 与附 A N-8/N-9 的落地状态、
> **显式差异**、**顺带修掉的真实缺陷**，以及本轮**仍未做**的部分。

### I.1 落地清单

| 位置 | 交付物 |
| --- | --- |
| 懒加载（§5.2） | `views/ServiceTreeView.vue` 重写：四态状态机（`collapsed` 未展开=未请求 / `loading` / `expanded` / `error`）；展开组织 → `GET /orgs/:id/services`，展开服务 → `GET /services/:id/components`；折叠**不回收**子节点（再展开不重取），并把子节点数记进 `knownCount` |
| 服务端搜索（§5.2/§5.3） | 搜索框输入即查 `GET /search`（防抖 200ms），结果行 = 名称 + 类型标签 + **所属路径**；**不需要展开树**；含请求序号以**丢弃过期响应** |
| 虚拟滚动（§5.2） | 可见行扁平化 + 窗口化渲染，阈值 200（§4.1）；行高/阈值/overscan 与窗口计算同源于 `utils/tree.ts` |
| 独立滚动容器（§5.2） | `.tree-scroll` 自身 `overflow-y:auto` + 高度有界；页面不随树变长；`ResizeObserver` 供实时视口高度 |
| 纯逻辑层 | `src/utils/tree.ts`（零 import）：`flattenVisible` / `computeWindow` / `shouldVirtualize` / `expandAction` / `lazyHintLabel` / `ensureVisible` |
| api 层 | `src/api/search.ts`（`GET /search`）+ `api/catalog.ts` 新增 `listByOrg`（N-9） |
| ⌘K 改造（§5.3） | `composables/useGlobalSearch.ts`：非空查询走**服务端**、空查询与降级走**客户端索引**；`CommandPalette.vue` 增降级提示条（不静默） |
| hub 侧 | 新模块 `internal/search`（models / repository / service / handler）+ `GET /search`；`internal/catalog` 新增 `ListByOrg` + `GET /orgs/:id/services` |
| 门禁 | `scripts/service-tree-smoke.mjs`（22 条断言）+ hub 侧 `search` 单测（服务层）/ 查询形状 DB-free 回归测试（仓储层） |

### I.2 与设计规格的**显式差异**（2 条，均已记账）

1. **折叠态提示不编造 N。** §5.2 原型写「N 项 · 点开时加载」，但 N 只有请求过才知道 —— 提前请求就等于放弃懒加载。
   这里选择诚实：**计数未知时只说「点开时加载」**，折叠回来过（计数已知）才显示「N 项 · 点开时加载」。
2. **组件行改为"点击选中、双击进详情"**（原为单击直接跳组件详情页）。理由：§5.2 明确要求"三层节点点击都有右侧详情页"，
   而原实现的组件分支是**死代码**（单击就跳走了，永远选不中组件）。现在选中显示详情 + 详情面板里「进入组件详情 →」按钮承担跳转，
   与附 C 的删除按钮位置约定（`进入组件详情 / 编辑 / 删除` 三按钮在详情面板头部）也对得上。

### I.3 顺带修掉的真实缺陷（均不在原清单）

1. **虚拟滚动窗口在"滚过头"时会反转区间**（`start > end`）。浏览器缩放/内容变化会给出超出内容高度的 `scrollTop`，
   此时原实现算出 `start(994) > end(500)`，上层 `slice` 得到空数组 —— 表现为**整棵树突然白掉**。
   已夹取为"吸附到最后一屏"。**这条是写冒烟断言时被断言器抓到的**（不是事后发现的）。
2. **⌘K 的客户端索引有语料上限**：`useResourceMap` 每层固定 `pageSize:100`，单服务超过 100 个组件时
   索引**静默漏掉**后面的组件 —— 表现为"库里明明有却搜不到"。服务端搜索没有这个上限（`limit` 是**结果**上限而非**语料**上限）。
   这也是把非空查询切到服务端的实质收益，不只是"少拉一次树"。
3. **`common.ErrBadRequest` 之类的包级单例被 `WithError/WithMessage` 就地改写**：两个并发请求会互相覆盖消息。
   新增的 search 模块改用"只读模板 + 值拷贝"构造错误，并在单测里钉住"两次不同入参的消息各自独立"。
   （既有的 `common/handler.go` 仍在使用 `ErrBadRequest.WithError(err)` 的写法 —— **列为待清理项**，不在本轮改动范围。）
4. **`GET /orgs/:id/services` 把两跳并一跳**：服务树是组织的 1:1 影子，原路径必须先
   `GET /orgs/:id/service-tree` 换树 id 再列服务；懒加载恰好是"每展开一次多一跳"的场景，省掉的正是这一跳。

### I.4 门禁与验证

```
vue-tsc --noEmit            ✅
vite build                  ✅（ServiceTreeView 仍为懒加载分包，16.88 kB）
pnpm test:runcenter         ✅ 16/16   ← 既有门禁无回归
pnpm test:theme-search      ✅ 25/25   ← 既有门禁无回归（含新增的 service 深链两态断言）
pnpm test:pipeline          ✅ 41/41   ← 既有门禁无回归
pnpm test:service-tree      ✅ 22/22   ← 本轮新增
（hub）go build / vet / test ✅ 全绿（含 search 服务层单测 + 查询形状 DB-free 回归测试）
```

新增 `scripts/service-tree-smoke.mjs`：node 直接 `import` 出厂 `.ts`（与另三个冒烟同手法）。
除纯逻辑断言外，含四类**防契约回退**的静态断言：① 服务树页必须走 N-9 端点、不得恢复"预拉组件"的旧实现；
② 行高不得在 CSS 里另写一个（双真相来源）；③ 树面板必须自身滚动且高度有界；④ 服务端搜索必须有请求序号（丢弃过期响应）+ 失败必须可见。

hub 侧新增 `internal/search/repository/search_dryrun_test.go`：**DB-free 查询形状回归测试**
（与 `internal/db/schema_dryrun_test.go` 同手法，DryRun 只生成 SQL）。钉三件"写错也不报错"的事：
① `ORDER BY` 真的出现（GORM 的 `Order()` **不认识 `gorm.Expr`**，传错会静默丢弃排序）；
② LIKE 元字符被转义（不转义时输入一个 `_` 就命中全表）；
③ 软删过滤逐表到位、且 `service_trees`（无 `deleted_at` 列）**不**参与过滤。

### I.5 本轮**仍未做**（如实标注，勿误读为已完成）

1. **服务端搜索不做权限过滤**：只回"类型 + 名称 + 路径 + id"这类导航信息，资源访问仍由各详情端点把关。
   收窄需要等 Epic C（账号权限）D1–D6 拍板后按 `ACCOUNT-PERMISSION-MODEL.md` §10 的对账结论做。
2. **`?node=` 深链只承载 Service id**：组件命中跳组件详情页、流水线命中跳编辑器，所以定位只需到 Service 层。
   若日后要让组件也深链定位到服务树，需要在寻找路径上**展开沿途服务**（当前实现只展开到组织这一层）。
3. **单层 100 条上限仍在**（`PAGE.pageSize=100`）：被截断时行尾显示「已加载 N/M」，**不静默**；
   但真正的解决要等服务端分页 + 滚动加载（`GET /orgs/:id/services?page=`）具备后再接。
4. **服务树页的"搜索"是"替换面板"而非"过滤树"**：§5.2 要求"不需要展开树"，替换式最贴合；
   代价是搜索期间看不到树的当前展开状态（清空输入即恢复）。
