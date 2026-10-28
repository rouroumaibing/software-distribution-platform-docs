> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · 附 E 历史未完成项快照 + 附 G/H/I 实现落地记录（C-01/02、C-12、R-8）
> **拆分说明**：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 附 E：历史未完成项快照（仅供追溯）

> ⚠️ **本表是历史快照，不是当前状态**。G1–G6 已于 全部落地。**当前进度请查** [`hub/STORY-BACKLOG.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md)（另有 [`plans/STATUS.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 跟踪当前状态与未完成项）。

| ID | 项 | 影响 | 快照时状态 | 后续 |
| --- | --- | --- | --- | --- |
| **G7** | service 层权限校验多处 TODO | 安全债（非功能阻断） | 🟢 已完成 | 设计已落（[hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) 两层 RBAC + 审批表 / 本文 §7.9 UX）；**P3a 已实现**：路由级 `HasPermission` 改用 §7 action、`component.go` 等接入 §7.5 Enforcement、Keycloak `groups` 经 `UserContext` 注入；console 权限页 P3c 支持 user/group 主体 + §7 角色选择器 + 自审提示 |
| **R1** | chart/manifest 施加生产化 | runner 发布链路 | 🟡 | chart 仓库鉴权接入；values `--set` 注入端到端验证 |
| **R2** | 日志持久化读路径 | 运行日志 | 🟡 | 已由 G2 hub DB 读路径解决，runner 侧归档可走 G5 upload-url |
| **R3** | 镜像与默认参数固化 | runner 生产镜像 | 🟡 | git/artifact/helm 镜像替换为 pinned 生产镜像；常量配置化（registry 确定后定值） |

---

## 附 G：实现落地记录 —— C-01 ⌘K 全局搜索 + C-02 暗色主题

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

## 附 H：实现落地记录 —— C-12 流水线全生命周期

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
2. **`executionMode` 的调度行为 ✅ 已落地（C-06）。** 字段存得下、读得回、UI 可切换；hub `buildSpec` 为 serial 阶段按模板顺序派生「紧邻前驱」`DependsOn` 链，runner `serialBlocked()` 据此严格先后 —— serial 阶段里的子任务**不再并发启动**。（本条写于该调度落地前，已更正。）

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

## 附 I：实现落地记录 —— R-8 服务树规模化

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

---

## 附 J：修正记账（追加，不改写上文历史行）

- **`pnpm test:pipeline` 断言数口径：41 → 63。** 附 H.4 / 附 I.4 所记「41/41」是 C-12 / R-8 落地当时的口径；实测现行 `scripts/pipeline-editor-smoke.mjs` 为 **63/63**（断言随后续迭代扩充）。按「只追加」铁律，上文「41/41」历史行保留不改写，当前口径以本条为准。

---

## 附 K：实现落地记录 —— 原型缺口补齐轮（仅原型；console 实现未动）

> 承接附 G/H/I/J。本轮性质与前几轮**相反**：不是"文档写了、代码补齐"，而是**原型先补齐、实现后跟进**——
> 的缺口分析（运行域「看得到状态、执行不了动作」+ 平台管理占位）当轮在 `CONSOLE-UI-prototype.html`（2562 → 约 2860 行）落齐。
> 设计规格增量见 ui-05 **§7.13**；新增依赖见 ui-09 **附 A 补充**（N-16/N-17）。

### K.1 落地清单（原型侧，全部带 handler，无装饰控件）

| 域 | 落地物 |
| --- | --- |
| 运行详情页 | 新页面 `pageRunDetail`（PAGES 注册 `rundetail` + 面包屑段 + 左栏高亮归属运行中心）：stage/task 时间线 + 任务日志块 + phase 感知动作区（终止 / 重跑 / 仅失败任务） |
| 审批 | `openApproval`：批准 / 驳回 + 意见 → 改 run 状态 + 写审计（`approval.approve/reject`）；`waiting` 表行与详情页双入口 |
| 终止 | `openCancelRun` 强确认；`PH` 增 `canceled ⊘ 已终止` 徽章 |
| 触发 | `openTriggerModal`（环境 / 参数 / 版本）接编辑器「▶ 触发」与列表「运行」；确认后真实插入 RUNS 并写审计 |
| 灰度 | `openCanaryCtrl`：步宽 10/25/50/100% + 暂停 / 晋级 / 回滚，真实改 RELEASES + 写审计 |
| 平台管理 | 「用户与权限」重写（组映射编辑 ROLE_MAP + 平台用户表 + 审计日志表 + 导出）；「接入管理」（注册 K8s 集群 / 登记主机真实进注册表、Runner 安装/升级、凭据轮转 / 新建） |
| 通知 | 顶栏铃铛 + 未读角标 + 下拉（待审批 / 失败运行 / 目标异常，条目按 todoCard 同语义直达） |
| 运行中心 | 分页（`page/pageSize`）+ 时间范围筛选（RUNS_AGO 分钟前 mock）+ 行动作 详情 / 审批 |
| 其他 | 个人中心 / 退出弹窗（原 toast 占位补齐）；制品页「版本矩阵」（`GET /package-versions` 消费 UI）；流水线运行历史弹窗行加「详情」直达 |

### K.2 与真实实现的映射与**显式差异**（记账，实现跟进时逐条对齐）

1. **三个动作已有现成桩，无新后端依赖**：终止 → `runApi.cancel`（`src/api/run.ts:149`）；审批 → `decision`（`run.ts:124`）；仅失败任务重跑 → `redispatch`（`run.ts:112`）。D.1 表缺 cancel 登记，已在 ui-09 附 A 补充段补记。
2. **`canceled` vs `Cancelled`**：原型 `PH.canceled` 为自造键；hub `PipelineRunPhase` 枚举是 `Cancelled`。实现版状态徽章必须用真实枚举值直传（§7.6「两层命名」铁律同源），不得照抄原型键名。
3. **mock 数据边界**：`RUN_DETAILS`（stage/task/日志）、`RUNS_AGO`（时间筛选）、`NOTIFICATIONS`、`PLATFORM_USERS`、`AUDIT_LOGS`、`VERSION_MATRIX`、`ROLE_MAP` 均为原型内存 mock；实现版分别接 `GET /runs/:id` + `stage-progress`、`?createdAfter=`（N-1 已落地）、前端聚合（N-17）、审计端点（N-16，待立项）、`GET /package-versions`。
4. **审批 UX 未展开项**：§7.9 的**防自审**（申请人禁批）与**历史决策留痕展示**，原型审批弹窗未含——留待实现版，不在原型伪装。
5. **运行详情 URL 形态未裁决**（§7.13 ③【待拍板】）：`/runs/:id` 独立路由 vs 运行视图 drawer；原型为内存页面态。
6. **通知未读状态不持久**：无后端已读语义，角标数为 mock 常量；N-17 立项前不接受"跨设备已读"类需求。
7. **版本矩阵按钮落点**：放「制品」页工具栏为原型裁决（版本是制品域信息）；若实现版认为归属「环境」页可再议，属可逆调整。

### K.3 门禁与验证

```
awk 提取内联 <script> → node --check         ✅
DOM stub 无头冒烟（vm.runInThisContext）     ✅
  ├─ 全部页面渲染（runs 含分页/时间筛选/两视图、rundetail × 3 phase 分支、admin-perm、admin-target × 3 Tab、artifacts、logs、editor）
  ├─ 全部 11 个新弹窗打开
  └─ 状态变更回调真实生效（审批批准 → phase=running；审计头 = approval.approve）
```

冒烟**抓出真 bug 1 个**：`pageRunDetail` 引用未声明的 `meta`/`sp`（编辑时漏带两行声明）——`node --check` 抓不住（标识符在模板字符串内），靠运行时冒烟兜住，已修。
（stub 要点备忘：`document.body` / `createElement` / **裸 `matchMedia`** 必须有——boot 用的是裸调用而非 `window.matchMedia`；toast 走 createElement+appendChild。）

### K.4 本轮仍未做（如实标注，勿误读为已完成）

1. **403/404 错误页与全局路由守卫错误态**（§7.9「权限不足错误态」原型仍未展开）；
2. **日志实时流指示**（WS/SSE 连接态）、下载日志、按 task 折叠分组（现平铺合并展示）；
3. 运行详情的阶段级时序视图（现仅列表化时间线）；
4. ~~console 实现侧跟进~~ → 已由 **附 L** 落地（下午）。

---

## 附 L：console 实现侧落地记录（接 K.4 第 4 条）

按 §7.13 把原型缺口落到 console 仓真实代码。**落码前先逐项核对了仓内现状**（Explore 全仓映射），结论与 K.2 的预期不同，如实记录：

### L.1 核对结论：K.1 列的多数 P0 缺口**仓内已实现**，无需落码

| K.1 缺口 | 仓内现状 |
|---|---|
| 单次运行详情页 | **已有** `RunMonitorView.vue`（`/pipelines/:pipelineId/runs/:runId`，DAG 横向流 + 任务详情 + 3s 轮询 + 日志面板） |
| 审批操作 | **已有**（`runApi.approve` → RunMonitorView 审批弹窗，意见 + 批准/拒绝） |
| 取消 / 重跑 | **已有**（`cancel` 两段式内联确认、`redispatch`、单任务 `rerunTask`；相位判定在 `utils/run.ts`，由 run-control smoke 钉住） |
| 带参触发对话框 | **已有** `TriggerRunDialog.vue`（MOD-4：目标/命名空间/参数 KV/版本 picker/409 策略拒绝渲染） |
| 分页 | **已有** `PaginationBar.vue`（RunCenter / RunList 消费，URL query 化） |
| 通知中心 | **已有基础版**（铃铛 + 面板 + link 直达）；本轮补轮询（见 L.2） |
| Runner 安装/升级 | **已有** `AgentOpsView.vue`（SSE 实时输出 + 台账） |
| 灰度控制 | **已有** pause/promote/rollback（`runApi.rollout`，G4）；步宽调节依赖 runner CurrentWeight 回流（协议级缺口），不做假 UI |

### L.2 本轮实际落码（console 仓）

1. **时间范围筛选**（§7.13 ⑤，全链路）：
   - `constants/runCenter.ts`：`RunCenterQuery` 增 `time` 字段；`RUN_TIME_RANGES`（''/1h/24h/7d）+ `timeToCreatedAfter()`（key → ISO，下推 hub `GET /runs?createdAfter=`，**hub 端点已支持**，核对过 `pipeline_run.go:141`）；
   - `RunCenterView.vue`：工具栏时间按钮组（与 phase 筛选并排）+ `buildQuery()` 统一 query 组装（setPhase/setTime/setPage 共用，切筛选回第 1 页）；
   - `runcenter-url-smoke.mjs`：16 → **21** 断言（time 归一化 / 非法 key 丢弃 / createdAfter 换算 / 幂等）。
2. **注册接入目标**（§7.13 ⑦）：`PlatformAdminView` targets section 加「＋ 注册目标」Modal —— k8s（kubeconfig `parseKubeconfig` 预检，**明确标注不随目标保存**）+ host 两分支；成功后展示一次性 `enrollToken`（hub `POST /targets/:id/enroll-token` 已有，`api/target.ts` 补封装）；`Target` 类型补 `targetKind`（hub 模型本来就有，console 侧一直缺）；targets 表加「类型」列。
3. **显式凭据轮转**（§7.13 ⑦）：`CredentialsView` 行操作加「轮转」——与编辑共用表单但**值必填**（留空 = 保留旧密文 = 没轮转），标题/按钮文案随 rotateMode 变化；openCreate/openEdit 重置 rotateMode 防状态残留。
4. **版本矩阵消费**（`GET /package-versions` 已有）：新建 `api/packageversion.ts`；`AgentOpsView` 页头展示 hub/runner 目标版本（install/upgrade 排队的版本来源可见）。落点与 K.2 第 7 条「制品页工具栏」不同：核对后发现该端点是**平台自身三版本**（console/hub/runner 部署时常量），语义属 Runner 安装域而非制品域。
5. **个人中心**：MainLayout user-chip 改下拉（姓名/用户名/邮箱/sub/realm 角色，hub 无用户表，只展示 Keycloak profile）；退出按钮保留。
6. **通知轮询**：MainLayout 通知 30s setInterval（此前仅 onMounted 拉一次），onBeforeUnmount 清理；无已读端点前 unread = 列表长度（与 N-17 前端聚合一致）。

### L.3 门禁（全绿）

```
pnpm build（vue-tsc --noEmit + vite build）   ✅（抓出 2 个类型错并修复：Target 缺 targetKind、reactive 字面量推宽）
pnpm test（7 个 smoke 脚本）                   ✅ 全过
  └─ runcenter-url：16 → 21 断言
```

### L.4 落码后仍 open（B 类 / 后端依赖，未做假实现）

1. **平台审计日志**（N-16）：hub 已有 `audit_log` 表 + `AuditLogRepository.Recent()`（`middleware/audit.go` 只写不读），**无查询 HTTP 端点** —— 前端无端点可接，不落假 UI；下一步小改（hub 加 `GET /audit-logs`）即可解锁整个 console 消费端。
2. **灰度步宽调节**：依赖 runner CurrentWeight 回传 TaskRun（已知唯一协议级回流缺口），现状步进为写死 10%→50%→100% 近似。
3. **通知已读语义 / assignee=me**（N-2/N-17 后端侧）。
4. 403/404 错误页（K.4 第 1 条延续）。

### L.5 追加轮：L.4 四项中三项收口（状态以 STATUS.md 为准）

1. **审计日志 ✅**：hub `GET /audit-logs` 落地（`AuditLogRepository.Query` 六维 filter，挂 platformGroup 过平台级 `user:manage`，DryRun 查询形状回归 + 路由测试）；console `api/audit.ts` + `/admin/audit` section（`PlatformAdminView.vue`）。
2. **通知已读 ✅（console 半边）**：`MainLayout.vue` localStorage 按 token sub 存 `lastReadAt`（60s skew 容忍），打开面板推进游标，修「角标恒亮」；hub 半边设计入 `runner-reflux-spec.md` §6。
3. **403/404 ✅**：`ErrorView.vue`（双语义）+ router catch-all + `api/http.ts` 响应拦截器（403 → `/forbidden`，`skip403Redirect` 豁免 + 防循环；400/404/409 仍就地呈现）。
4. **灰度步宽**：协议设计定稿（同 spec §3），实现 gate 真流量环境，未落码。

### L.6 P2 落实轮（灰度步宽收口 + P2 五项全落码）

1. **灰度步宽 ✅（runner→hub 回流协议落码）**：`ReleaseDetailView.vue` 轮询 `releaseApi.listByRun`（GET /releases?pipelineRunId=），活跃行 `currentWeight` 优先、无快照退回任务完成数近似 `approxPercent`；协议见 `runner-reflux-spec.md` §3（v3：§4 Artifacts 降为协议预留）。
2. **日志面板三件 ✅**：`RunMonitorView.vue` —— 下载（Blob 本地导出 `runId-task.log`）、折叠（>8000 字符默认只渲染尾部 + 展开全部）、流式指示（`● 实时` live-dot，运行活跃时显示）。
3. **⌘K 非组件直达 ✅**：`utils/search.ts` 增 `nav` 类型（id=路由 path）；`useGlobalSearch.ts` 客户端静态池 `NAV_HITS`（总览/服务树/运行中心/平台管理四 section），不依赖资源索引与服务端 /search；结果追加在资源命中之后、整体截 SEARCH_LIMIT。
4. **表格窄屏 ✅**：`styles/tokens.css` `@media (max-width: 768px)`——`.card overflow-x: auto`（容器横向滚动，不裁列）+ 单元格收紧 + toolbar 换行 + 栅格单列。
5. **运行中心组件/触发人筛选 ✅**：hub `FindAll` 5 参（+`triggeredBy`，`GET /runs?triggeredBy=`）；console `RunCenterView` 工具栏组件下拉（`index.components` 供选）+ 触发人输入框；URL 契约 `RunCenterQuery` 增 `componentId`/`triggeredBy`（runcenter-url-smoke 21 → **22** 断言，新增深链往返用例）。
6. **门禁**：`pnpm build`（vue-tsc + vite）✅；`pnpm test` 7 smoke 全绿（runcenter 22/22、theme-and-search 26/26（+nav 直达断言）、service-tree 63/63（类型标签断言修正为「服务端三型 + nav 仅客户端」）、run-control 22/22）。

### M.1 原型路线图落地轮（仅原型，console 实现仓未动）

1. **范围**：`CONSOLE-UI-prototype.html` 内联 JS，路线图（`plans/CONSOLE-UI-PROTOTYPE-ROADMAP-2026-10-12.md`，已删，权威入 ui-12 R5）P0–P2 全部收口：4.2 版本一等对象 + 指定版本回滚（append 新 release 记录；目标版本来源 = 新契约 `GET /components/:id/versions`，N-33）、4.1 版本 diff + 变更说明、4.4 三处高危操作原因必填（配置保存 / 审批 / 凭据轮转）、4.3 触发器 Tab 切换 + cron 校验预览 + 写回 `TRIGGERS`、5.1 审批策略卡 + 时间线、5.2 订阅规则（事件 × 渠道）。
2. **顺带**：原型 5 项代码小修（TDZ / 审计分类 / 角标 / PAT 安全 / 配置版本 v5）+ 文件名实际落盘改名（文档 §0.2 #11 早已按新名记录，磁盘迟至今日对齐）+ 版本矩阵语义勘误（`GET /package-versions` = 平台自身三版本，组件级矩阵改引 N-33）。
3. **门禁**：`node --check` 抽 `<script>` SYNTAX_OK；纯函数冒烟（cronParse/cronNext/diffLines）**20/20**——抓出并修复 `*/15` 步长 cron 解析 bug；内容复核 51 个新标记在盘 / 3 个旧模式清零。
4. **B 类登记**：`GET /components/:id/versions`（hub 侧待立项，N-33）；环境覆盖档执行路径维持 R4 结论（本文不重复登记）。

### M.2（晚）原型运行时缺陷修复轮（仅原型，console 实现仓未动）

1. **背景**：用户以 jsdom 对 M.1 产物做入口级回归（19 个入口），报 2 处崩溃；本轮修复后复验，又由自建 jsdom harness 抓出 1 处功能级死链（用户方法只查报错，漏「不报错但不工作」类）。
2. **修复 ①（用户报告）启动 TDZ**：`renderNotif()` 在模块加载期被立即调用，而 `NOTIF_READ` 等 const 声明在其后 → `Cannot access 'NOTIF_READ' before initialization` → 脚本中断 → 后续数据块全部未初始化（服务树 / 接入管理 / 通知中心 / PAT / 触发器 / 订阅规则全崩）。**未采用用户建议的单点前移**，改用结构性方案：**全部 17 个 const 数据块统一前移至 boot IIFE 之前**（新增「数据块统一区」，区块注释随行），整类 TDZ 根治——`setTimeout(render,0)` 只挡「启动时同步 render」，挡不住加载期其他调用。
3. **修复 ②（用户报告）服务树 `node is not defined`**：`${nodeGovernanceHtml(node)}` 写在 IIFE 闭合之后，而 `node` 是 IIFE 内 const → 服务树每次渲染必崩。修法：插值移入 IIFE 返回的模板内（治理卡片与节点信息同 pane，语义本就如此）。
4. **修复 ③（harness 抓出）铃铛下拉深链全死**：`#notifDrop` click handler 首行 `e.stopPropagation()`，事件到不了 `#topbar` 委托监听（`go()` 在内）→ 通知条目与「查看全部通知 →」只关下拉不跳转；左栏无通知中心入口 ⇒ **5.2 通知中心整页不可达**。修法：drop handler 内对 `[data-nav]` 直接 `go(nav.dataset.nav, runTab, runFilter)`。同类审计：全文件 4 处 `stopPropagation`，另 3 处（userBtn / userDrop / notifBtn）均在各自 handler 内直接导航，无此患。
5. **门禁（复现用户方法并加强）**：受管 node 工作区装 jsdom 自建 harness——① 加载零报错（TDZ gate）② 逐页穷举 **64 个交互入口**（导航 / 动作 / Tab / 树节点 / 子 pill；destructive 动作黑名单）+ **11 个弹窗 settle**（含输入填充、原因必填拦截、回滚 append 路径）③ **34/34 行为断言**：触发器 Tab 切换 + cron 合法 / 非法预览 + 保存写回（重开校验持久化）、灰度回滚（原因必填拦截 → append 新 release 记录 + 「（历史）」标记 + toast）、配置版本两版本 diff 输出 + 回滚 append vN、凭据轮转原因必填、PAT 无「永不过期」+ admin 二次确认 + 明文仅展示一次、铃铛角标标记已读后 -1。

### M.3（设计裁定）个人中心角色来源 = `/api/userinfo`（非 `profile.realm_access`）

> 来源：`shared/ACCOUNT-PERMISSION-MODEL.md` §10 #13 双向钢人（全文 `shared/ACCOUNT-PERMISSION-STEELMAN-2026-10-27.md`）。本段为对 §M 行 293「个人中心展示 realm 角色 from Keycloak profile」的设计层更正，**不改写该行历史记录**，仅标明角色展示的权威来源已裁定切换。

1. **裁定**：个人中心的**身份**四字段（姓名 / 用户名 / 邮箱 / sub）仍来自 `oidc-client-ts` 的 `profile`（OIDC 标准、零额外往返、dev 降级简单）；**授权相关展示**（平台角色 `roles` / 组织 `orgs`）**必须来自 hub `GET /api/userinfo`**，禁止读 `profile.realm_access`。
2. **理由**：`realm_access`（Keycloak realm 级）与 hub 平台角色（RBAC 表级）是两套命名空间；个人中心若显示 `realm_access`，会与「用户与权限」页显示的 hub 平台角色冲突，制造「两个角色来源」歧义。hub 是唯一权限权威（§2.1 / §2.2），授权展示的唯一真相源应为 `/api/userinfo`。
3. **实现落点（Task 10）**：console 新增 `userinfoApi`（`GET /api/userinfo`），`auth` store 在 `init`（登录恢复 / 回调后）拉取并缓存 `roles` / `orgs`；`MainLayout` 个人中心改用 `userinfo.roles`（标注「平台角色」），`profile` 仅留身份四字段。`/api/userinfo` 不可用时角色区静默降级为空，不阻断登录态。
4. **红线澄清**：§8 #1「前端不解析 token」精确为「应用代码不据 token 声明做授权判定」；`oidc-client-ts` 库级解析（renew / Bearer 注入 / `user.expired` 登录态）不可避免、不在红线范围。console 当前无 `if token.roles.includes` 类授权判断，安全语义已达成。
6. **harness 抓 bug 经过（留痕）**：初版 17/21 → 4 个 FAIL 中定位 3 个为 harness 自身缺陷（徽章选择器 `.badge` vs 实际 `.hint`、`hidden` 属性 vs `style.display`、T3 导航路径假设错误——T2 后页面停在运行中心），1 个为真 bug（即修复 ③）。
7. **遗留**：用户路线图仍开放项（4.2 版本详情 / 晋级、4.3 上游触发与触发来源列、5.1 策略配置界面、5.3 / 5.4 / 5.5 / 6.x 及第四期）不在本轮范围；console 实现仓仍未动。

## 附 N-36 · M1 用户与组管理页 console 落地（2026-10-27）

`PlatformAdminView.vue`（permissions section）按 ui-05 §7.14 M1 实现「用户 / 用户组」两区，紧邻平台角色区之前：

1. **用户区**：列表（用户名 / 邮箱 / 启用态 + 待改密徽章）+ 行动作（重置密码、启用/停用）+ 新建用户弹窗。一次性临时口令经 `pwShow` 弹窗只展示一次（与 enroll-token 同语义）+ 复制按钮。
2. **用户组区**：列表（组名 / 路径，`/org:*` 载体组标「系统管理」只读）+ 建组弹窗（客户端校验与 hub `validateRBACGroupName` 对齐：非空、禁 `/`、禁 `org`/`org:*`）+ 成员管理弹窗（目录用户下拉添加 / 移出）。
3. **降级语义**：目录代理不可用（KC 未配置 → 404）时 `dirAvailable=false`，两区整块隐藏，M2/M3 授权表单退化「已绑定主体 + 手输」不变。
4. **门禁**：vue-tsc 通过；8 套 smoke 全绿（platform-perm 21/21 契约不变——它只测 `utils/permission.ts` 纯逻辑）；`pnpm build` 通过。
5. 页首与页尾注释同步为现状（旧「没有用户目录」表述移除）；原型与规范见 ui-05 §7.14 M1 / `CONSOLE-UI-prototype.html`。
