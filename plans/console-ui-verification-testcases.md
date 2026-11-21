# Console UI 验证测试用例计划

> 定位：可执行的 UI 验证用例清单，逐条给出步骤与判据，补齐现有 E2E 只覆盖「5 页导航 + DOM 关键字」的验证空白。
> 范围：`software-distribution-platform-console`（Vue3 + Vite）。本文件是**待执行计划**，不是执行报告；进度与判定以 `plans/STATUS.md` 为准。
> 权威来源：`console/features/ui-08-testing-acceptance.md` §10.2 验收 A/B + 附 F、`console/features/CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md`、`plans/audits/2026-11-18-console-verification-system.md`（建议 5）、`plans/audits/2026-11-19-verification-article-alignment-gap.md`（T1 / V2 / V7 / E1）。
> 执行入口：扩展现有 `scripts/e2e-verify.mjs`（CDP 驱动，零外部依赖），不新增 playwright 依赖；逐用例把 `feature_map` 从「页面级」细化到「选择器 / 快捷键级」。

---

## 一、现有覆盖与「验证完」的定义

### 1.1 现有 E2E 覆盖了什么

| 维度 | 现状 | 证据 |
| --- | --- | --- |
| 页面可达 | 5 页（`/dashboard`、`/service-tree`、`/runs`、`/admin/targets`、`/forbidden`） | `e2e-verify.mjs` FLOW 五项；`manifest.json` steps=5, failures=0 |
| 断言深度 | `ready && png>1000B && bodyLen>20 && 含关键字`（唯一断言形态） | `e2e-verify.mjs:136` |
| 后端数据 | **无**：`network[]` 全是 `/src/*` 静态资源 + 两个 404，**零 `/api/*` 调用** | `evidence/.../responses/01-dashboard.json` |
| 交互 | **无**：无 `Input.dispatchMouseEvent` / `insertText` / `dispatchKeyEvent` | `e2e-verify.mjs` 全文 |
| 五态 / 异常态 | **无**：无空 / 加载 / 错误 / 403 驱动 | 仓内无清单；`golden-set.md` GC-03 已记录该缺口 |
| 视觉 | 5 张一次性截图 + sha256；无基线 / 稳定时刻 / 容差 / 灰阶比对 | `evidence/` 无 `baseline/` |
| 路由覆盖 | 5 / 26 顶层路由；11 个组件子 Tab 全未覆盖 | `src/router/index.ts` |

### 1.2 完成定义（DoD）

四层齐全才算「验证完」，缺一层即未闭环：

- **L1 行为交互**：每个用例的点击 / 输入 / 键盘 / 滚动 / 弹窗动作均有断言，且捕获对应 `/api/*` 请求与响应字段。
- **L2 五态异常**：§2 清单内每视图覆盖空 / 加载 / 错误 / 成功 / 无权限，403 三策略各取样；「预期报错」判 done 不判失败。
- **L3 视觉基线**：关键页面截图有首版人确认的基线（sha256 + 稳定时刻 + 视口 + 驱动版本），比对有可机器判定的 `diff_metric` 与容差参数。
- **L4 业务链路**：`ui-08` §10.2 验收用例 A 六条链路纯 UI 走通，不借助命令行 / 代码兜底。

### 1.3 通用判据与失败处理

- done 指向**真实系统可观测状态**（DOM + API 响应字段），不靠自述；结论附退出码与证据路径。
- 超时 = fail，**不重试**；网络失败 / 403 / 表单校验 / 409 verdict 属预期报错，按 done 记。
- 同一门连续失败 3 轮转人（`governance/redlines.yaml` 的 `max_consecutive_gate_failures`）。
- 截图按 `screenshot` 一等证据类型入包：`sha256` + 基线引用 + 场景 id + 比对指标。
- 运行时证据不入库、采集端不落盘凭据；基线作例外入库并受保护（对齐 E1 判据）。

---

## 二、用例编号与字段约定

| 前缀 | 类别 | 条数 | 对应层 |
| --- | --- | --- | --- |
| `UI-B` | 行为交互（导航 / 深链 / CRUD / 弹窗 / 主题） | 12 | L1 |
| `UI-S` | 五态与异常态（含 403 三策略） | 10 | L2 |
| `UI-V` | 视觉基线与比对协议 | 5 | L3 |
| `UI-F` | 业务链路（四类流水线 + 异常回归） | 6 | L4 |
| `UI-P` | 认证与权限守卫 | 5 | L1 / L2 |

每条用例字段：**ID / 前置 / 步骤 / 判据 / 证据 / 关联**。证据落点统一为 `evidence/<stamp>/<UI-x>/<id>.{png,json,log}`，`manifest.json` 记录每步的 `sha256`。

执行顺序按依赖推进：`UI-B` → `UI-P`（守卫决定后续角色视角）→ `UI-S` → `UI-V` → `UI-F`；首批先把 `UI-B01/B04/B05` 的 API 捕获能力补进 harness。

---

## 三、行为交互用例（UI-B）

### UI-B01 全路由可达性冒烟
- **前置**：Vite + 认证旁路（`VITE_AUTH_DISABLED`）就绪。
- **步骤**：逐条导航 `src/router/index.ts` 的 26 个路由 + 11 个 `component-*` 子路由；每页等 `document.readyState==='complete'` 后读 DOM、截图、抓 `/api/*`。
- **判据**：HTTP 200、无未捕获 JS 异常、DOM 非空、每页至少 1 个 `/api/*` 请求（静态页 `/forbidden` 除外）。
- **证据**：`UI-B01.json` 含逐路由 `path/status/apiCalls/jsErrors`。
- **关联**：补齐 FLOW 5 页 → 全路由；`verify.yaml` feature_map 更新。

### UI-B02 ⌘K 全局搜索直达
- **前置**：任一页，服务树含 `gateway` 组件。
- **步骤**：`Input.dispatchKeyEvent` 发 `Meta+K` → 断言浮层出现 → `Input.insertText` 输入 `gateway` → 读结果项 → Enter。
- **判据**：≤2 步进入目标组件详情；结果项文本含所属路径（`org/service`）；浮层关闭。
- **证据**：`UI-B02.png`（浮层）+ `UI-B02.json`（`resultText/url/steps`）。
- **关联**：`ui-08` 验收 B「任意资源直达」、附 F「三步测试」。

### UI-B03 服务树懒加载与虚拟滚动
- **前置**：服务树有 ≥2 层 ≥200 节点数据。
- **步骤**：进 `/service-tree` 记首屏 `/api/tree*` 请求数 → 点展开 Org → 记新增请求 → 滚动容器到中段 → 读 DOM 节点数与索引。
- **判据**：启动 0 条树请求、首屏仅 1 层请求、展开才发下一层；虚拟滚动窗口索引连续且 DOM 节点数 ≪ 总数。
- **证据**：`UI-B03.json` 含 `requestsByStep[]` / `domCount` / `windowIndices`。
- **关联**：`service-tree-smoke.mjs`（静态断言）→ 行为级验证；`ui-08` 规模不变量。

### UI-B04 运行中心视图切换与筛选分页
- **前置**：hub 有跨组件 `run` 与 `release` 数据。
- **步骤**：`/runs` → 读列表行数 N → 选状态筛选 `Failed` → 读行数 M 与每行徽章 → 切「发布」视图 → 翻到第 2 页。
- **判据**：M < N 且每行状态徽章一致（筛选真实生效）；两视图可切、跨组件列表可见、翻页 `page=2` 生效。
- **证据**：`UI-B04.json` 含 `rowsBefore/rowsAfter/filter/apiCalls[]`。
- **关联**：`ui-08` 验收 B「全局巡视」；`runcenter-url-smoke.mjs`。

### UI-B05 视图深链五子情形
- **前置**：同 UI-B04。
- **步骤**：依次打开 ①`/runs?view=releases&page=2` ②`/runs` ③连续切视图后按浏览器返回 ④旧链 `/releases` ⑤旧链 `/pipelines`，各记 URL、面包屑、左栏高亮、离站次数。
- **判据**：①发布视图 + 第 2 页 + 面包屑 `SDP / 运行中心 / 发布`；②地址栏归一为 `/runs?view=runs`；③**一次**退出运行中心（人工点验项）；④展示发布列表非运行列表；⑤落 `/service-tree` 不复活已删视图。
- **证据**：`UI-B05.json` 含五组 `url/breadcrumb/activeMenu/exitCount`。
- **关联**：`ui-08` 验收 B N-13（①②④⑤ 已有静态覆盖，③ 本用例补人工点验）。

### UI-B06 组件详情 11 Tab 切换
- **前置**：存在任一组件 id。
- **步骤**：进 `/components/:id/overview` → 逐 Tab 点击 `概览/配置/流水线/运行/发布/制品/环境/权限/审计/日志/变量与密钥` → 每 Tab 读 URL、标题、首屏接口。
- **判据**：11 Tab 全部可切换、URL 与内容同步、无空白页；面包屑按现状降级（component→repoUrl）不误判为失败。
- **证据**：`UI-B06.json` 含逐 Tab `url/title/apiCalls[]`。
- **关联**：`ui-08` 验收 B「组件详情 Tab」（按现状 11 Tab；7 Tab 收敛后复核）。

### UI-B07 流水线 CRUD 与 409 verdict 强确认
- **前置**：组件存在、`component:manage` 角色。
- **步骤**：新建 → 编排 [构建→部署测试] → 保存 → 改名称 → 删除（输入名称强确认）→ 对有进行中运行 / 待审批运行的流水线再删一次。
- **判据**：全链路纯 UI 完成；删除弹强确认；后端 `409 + {reasons}` 的 verdict 原样渲染（前端不预计算影响面）。
- **证据**：`UI-B07.png`（确认弹窗 + verdict）+ `UI-B07.json`（`reasons[]` 与请求序列）。
- **关联**：`pipeline-editor-smoke.mjs`、`ui-04` §6.1 D1 / N-5。

### UI-B08 总览待办卡深链与筛选生效
- **前置**：有待审批 / 失败 / 暂停的运行各 ≥1。
- **步骤**：打开 `/dashboard` → 点「待我审批」卡 → 读落地 URL 与筛选控件状态 → 另两张卡重复。
- **判据**：直达对应视图**且筛选真实生效**（不是仅跳页）；筛选语义降级（assignee=me 未落地、实现版不渲染 `paused`）按 `ui-05` 现状标注，不误判为失败。
- **证据**：`UI-B08.json` 含 `card/landingUrl/filterState/rows`。
- **关联**：`ui-04` §3 用户旅程、`ui-05` 总览待办卡契约。

### UI-B09 灰度发布控制
- **前置**：存在 `phase=paused` 的 release。
- **步骤**：进 `/releases/:id` → 依次触发 pause / promote / rollback → 每步读步骤器状态与后端响应。
- **判据**：三个动作均发真实请求并推进状态；任务级状态近似回退（`ReleaseDetailView.vue:54,68`）按现状标注。
- **证据**：`UI-B09.png`（步骤器各态）+ `UI-B09.json`（请求与状态序列）。
- **关联**：`ui-04` 用户旅程「灰度」、`run-control-smoke.mjs`。

### UI-B10 运行监控审批弹窗
- **前置**：存在待审批运行。
- **步骤**：进 `/pipelines/:pipelineId/runs/:runId` → 点审批入口 → 弹窗内填意见 → 同意 / 拒绝 → 读阶段进展与日志区。
- **判据**：审批动作发真实请求、阶段状态更新；日志端点未就绪时静默占位（`RunMonitorView.vue:95`）按现状标注。
- **证据**：`UI-B10.png`（弹窗）+ `UI-B10.json`（审批请求/响应 + 阶段状态）。
- **关联**：`ui-04` §3 运行异常分支「审批拒绝」。

### UI-B11 弹窗 / 抽屉生命周期
- **前置**：可触发 `Modal` / `Drawer` / `HighRiskConfirm` / `TriggerRunDialog` 的页面。
- **步骤**：对每个组件执行 open → 校验遮罩与焦点 → confirm / cancel → close → 断言 DOM 清理与事件监听解绑。
- **判据**：四态可循环 ≥2 次无残留节点；高风险确认必须显式输入才能提交。
- **证据**：`UI-B11.json` 含逐组件 `openNodes/closedNodes/repeatable`。
- **关联**：`REVIEW.md` C6「新增界面组件 → 视觉基线 + 异常态用例映射」。

### UI-B12 双主题与灰阶切换
- **前置**：明 / 暗 / 灰阶三种模式入口可见。
- **步骤**：在总览、服务树、运行中心、运行监控、审批弹窗各切主题 → 开灰阶 → 截图比对层级与状态可辨性。
- **判据**：三模式下图标形状可辨、文字对比度 ≥4.5:1；灰阶下五态靠形状 / 图标 / 文字区分。
- **证据**：`UI-B12-<page>-<mode>.png` 九宫格 + `UI-B12.json`。
- **关联**：`ui-08` 验收 B「双主题」、附 F「灰阶测试」、`theme-and-search-smoke.mjs`。

---

## 四、五态与异常态用例（UI-S）

> 驱动方式：用 CDP `Network.setBlockedURLs` / 拦截响应注入 500 / 空数组 / 延迟 9s，或用无权限 token；每个用例对 §2 清单内**取样视图**执行，清单全集逐项登记在 `UI-S00.json`。

### UI-S00 五态覆盖矩阵登记
- **步骤**：对五态规范 §2 的 16 组视图（配置版本、审批中心、通知、变量组、审计、服务树、制品、Runner、PAT 等）逐项登记触发方式、截图点、断言、对应基线 id。
- **判据**：每组四态 + 无权限态均有可执行触发方式；截图 ↔ 用例一一映射；无「只写不做」项。
- **证据**：`UI-S00.json`（映射表，作为 `REVIEW.md` C6 的 feature map 附件）。
- **关联**：五态规范 §2、`plans/audits` 建议 5 ③。

### UI-S01 加载态
- **步骤**：注入 1.5s 延迟 → 观察首屏骨架 / spinner → 注入 9s 延迟 → 观察降级。
- **判据**：首屏骨架优先、翻页行内 spinner；>8s 自动降级为「加载超时，点击重试」，不无限转圈；加载态禁操作。
- **证据**：`UI-S01-loading.png`、`UI-S01-timeout.png`。

### UI-S02 空态
- **步骤**：拦截 API 返回空数组 → 观察列表区。
- **判据**：空盒图标 + 「暂无数据」+ 引导动作；主行动按钮按权限门控渲染。
- **证据**：`UI-S02.png`。

### UI-S03 错误态
- **步骤**：分别注入 500、网络中断、超时 → 观察错误区 → 点重试恢复正常。
- **判据**：警告图标 + 错误摘要 + 「重试」；不暴露原始堆栈；重试后回到成功态。
- **证据**：`UI-S03-<kind>.png` 三组 + `UI-S03.json`。

### UI-S04 成功态
- **步骤**：正常响应 → 观察列表 / 详情。
- **判据**：数据正常渲染、行数与响应条数一致、徽章枚举符合契约。
- **证据**：`UI-S04.png` + `UI-S04.json`（`rows/apiCount`）。

### UI-S05 无权限（列表级 403）
- **步骤**：用无权限 token 打开受限视图 → 观察锁态。
- **判据**：锁图标 + 固定文案「无权限查看」+ 所需权限标识（如 `component:manage`），橙色区别于错误红。
- **证据**：`UI-S05.png`。
- **关联**：五态规范 §3.1。

### UI-S06 403 三策略
- **步骤**：各取一个隐藏 / 禁用+tooltip / 可点后拦截场景，用无对应权限 token 操作。
- **判据**：隐藏策略入口不渲染；禁用策略按钮 disabled 且 hover 显示所需权限；拦截策略点击弹说明含操作名 + 缺失权限 + 建议动作；文案不写模糊措辞。
- **证据**：`UI-S06-<strategy>.png` 三组。
- **关联**：五态规范 §3；`AuditTab.vue:38-47` 已有内联锁态作对照样本。

### UI-S07 权限判定顺序
- **步骤**：无权限 token 打开受限列表 → 抓 `/api/*` 请求 → 与有权限 token 对照。
- **判据**：先判 403 再判加载 / 空 / 错误 / 成功；无权限用户**不发**列表请求（无审计噪声）。
- **证据**：`UI-S07.json` 含 `apiCallsByRole`。
- **关联**：五态规范 §3.2。

### UI-S08 制品库错误态（已知缺口）
- **步骤**：在 `/components/:id/artifacts` 注入拉取失败 → 观察错误区。
- **判据**：应有错误态 + 重试；当前实现缺失（`ui-05:220` 确认），执行时标记 `known-gap` 并转缺陷，不静默跳过。
- **证据**：`UI-S08.png` + `UI-S08.json` 标记 `status: known-gap`。
- **关联**：`ui-05-page-layouts.md:209-227`。

### UI-S09 日志区状态切换
- **步骤**：运行无日志 → 观察空态「等待输出」→ 注入延迟看骨架 → 注入 500 看重试 → 模拟断线重连。
- **判据**：空 / 加载 / 错误三态齐；断线重连属错误态子类，重连成功后回到实时流。
- **证据**：`UI-S09-<state>.png` 三组。
- **关联**：`ui-05:229-239`；五态规范 §4 注记。

### UI-S10 五态灰阶可辨
- **步骤**：对 UI-S01~S05 各态开灰阶截图。
- **判据**：旋转 / 空盒 / 警告三角 / 对勾 / 锁五种形状互不混淆，去色后仍可辨。
- **证据**：`UI-S10-<state>.png` 五组。
- **关联**：五态规范 §1.1、附 F「灰阶测试」。

---

## 五、视觉基线与比对协议（UI-V）

### UI-V01 基线首版人确认
- **步骤**：对 L3 关键页面（总览、服务树、运行中心两视图、运行监控、组件详情概览、审批弹窗、403 页）在固定视口 + 固定驱动版本下各截一帧；定义稳定时刻 = `document.fonts.ready` + 网络静止 500ms + 2 个 animation frame 后。
- **判据**：每基线记录场景 id / 视口 / 浏览器版本 / 稳定时刻定义 / `sha256`，**首版由人确认**，不由 agent 当次截图转正；基线入 `evidence/baseline/` 并列入 `protected_paths`。
- **证据**：`baseline/manifest.json` 含逐场景 `baseline_sha256/confirmedBy/viewport/driverVersion`。
- **关联**：`plans/audits` 建议 5 ①；拍板项③（容差阈值）。

### UI-V02 比对协议
- **步骤**：每次 E2E 对同场景截图 → 算 `actual_sha256` 与 `diff_metric`（像素差比例 / 感知阈值）→ 与容差阈值比对。
- **判据**：机器可判定；超阈值 = fail 不重试；字段对齐 `schemas.md` 的 `screenshot` 类型；容差作为参数写在 `governance/redlines.yaml`，阈值未定时不阻塞比对脚本落地。
- **证据**：`UI-V02.json` 含 `sceneId/baseline_sha256/actual_sha256/diff_metric/tolerance/verdict`。
- **关联**：`plans/audits` 建议 5 ②。

### UI-V03 漂移处置分岔
- **步骤**：比对失败时先归因：代码回归 / 有意 UI 变更 → 前者修代码重跑，后者人审后更新基线并附新旧对比与理由。
- **判据**：任何基线更新都有人审记录与理由；禁止把「更新基线」当修测试的捷径（`RT-18`）。
- **证据**：`UI-V03.json` 含 `cause/decision/reviewer/beforeAfterSha`。
- **关联**：`plans/audits` 建议 5 ②对抗推演。

### UI-V04 截图一等证据
- **步骤**：把每步截图按 `screenshot` 类型写入证据包（带 `sha256`、基线引用、场景 id、比对指标），由 harness 收集。
- **判据**：证据包缺截图项或字段不全则该步按未通过处理；运行时证据不入库，基线例外入库受保护（E1）。
- **证据**：`manifest.json` 的 `files[].screenshot` 段。
- **关联**：`plans/audits` 建议 5 ④；11-19 对齐 E1。

### UI-V05 基线与容差受保护
- **步骤**：验证 `evidence/baseline/**` 与容差配置在 `protected_paths` 内；CI 从 base 分支取基线与规则，评审绑 commit。
- **判据**：同 PR 改基线 / 容差不改代码无法自审通过；推新提交作废旧评审。
- **证据**：`UI-V05.json` 含 `protectedPaths[]/baseRef/commitBinding`。
- **关联**：`plans/audits` 建议 8 ①；11-19 对齐 V7。

---

## 六、业务链路用例（UI-F）

> 全部为**纯 UI 操作**，不碰命令行 / 代码；前置为 hub 与 runner 可用、四类流水线数据已备。

| ID | 操作（纯 UI） | 达成判据 | 证据 |
| --- | --- | --- | --- |
| UI-F01 环境准备 | 服务树 → 建组件 → 建组件对接环境 | 组件与环境在树 / 列表可见可选 | `UI-F01.json` |
| UI-F02 日常流水线 | 编排[构建→部署测试] → 触发 → 监控 → 看日志 | 构建成功并部署测试环境，阶段卡全绿 | `UI-F02.png/json` |
| UI-F03 版本归档 | 编排[建版本分支→构建→归档] → 触发 → 监控 | 版本包进入制品库可复用 | `UI-F03.png/json` |
| UI-F04 转测流水线 | 编排[版本包获取→发布转测] → 触发 | 版本包从制品库消费并发布到转测环境 | `UI-F04.json` |
| UI-F05 生产流水线 | 编排[版本包获取→审批→多环境发布] → 触发 → 审批决策 → 发布 | 经审批门禁后发布到多套环境 | `UI-F05.png/json` |
| UI-F06 异常回归 | 令任务失败 → 重试 / 重投 / 阶段跳过 → 灰度回滚 | 异常分支符合 `ui-04` §6.2，不卡死可恢复 | `UI-F06.png/json` |

- **关联**：`ui-08` §10.2 验收用例 A 六项；`ui-04` 四类流水线模式与用户旅程七步。
- **判据补充**：runner → hub 回流缺口（canary `CurrentWeight` / `agent_version` / TaskRun 产物不回传）按现状标注，用例不依赖这些字段作断言。

---

## 七、认证与权限守卫用例（UI-P）

### UI-P01 L1 守卫
- **步骤**：用非 `platform-admin` token 直接打开 `/admin/*` 各页。
- **判据**：统一跳 `/forbidden`，不渲染管理台内容；URL 带来源记录。
- **证据**：`UI-P01.json` 含 `attempted/landed`。

### UI-P02 L2 守卫
- **步骤**：非 `orgAdmins` 打开 `/org/dashboard?org=<slug>`；组织管理员再打开一次。
- **判据**：前者跳 `/forbidden`；后者进入且组织卡片渲染（页面占位状态按现状标注）。
- **证据**：`UI-P02.png/json`。

### UI-P03 未认证跳转
- **步骤**：清 session 后打开需登录页 → 观察登录 URL。
- **判据**：跳 `/user/login?redirect=<原路径>`；登录后回跳原路径。
- **证据**：`UI-P03.json` 含 `before/after/redirect`。

### UI-P04 登录双模式与 SSO 回调
- **步骤**：用户名密码登录 → 首登改密 → 登出 → 走 `/auth/callback` SSO 回调。
- **判据**：两模式均可建立会话；回调后落 `/dashboard`；失败回登录页且不泄露凭据。
- **证据**：`UI-P04.json` + 脱敏响应（不落盘 cookie）。

### UI-P05 认证旁路标记
- **步骤**：用 `VITE_AUTH_DISABLED` 跑全套用例。
- **判据**：结果显式标注 `authBypassed: true`，不与真实认证结果混记；旁路与真实认证各留一份 manifest。
- **证据**：`UI-P05.json`。
- **说明**：现有 5 页 E2E 即在此模式下运行，其证据不得冒充真实认证链路验证。

---

## 八、执行批次与验收 gate

| 批次 | 用例 | 前置 | 验收 gate | 需拍板 |
| --- | --- | --- | --- | --- |
| 一：补 harness 能力 | UI-B01 / B04 / B05 | 无 | `pnpm test:e2e` 在每页能捕获 `/api/*` 请求与响应字段；`manifest.json` 含 `apiCalls[]` | 无 |
| 二：行为与守卫 | UI-B02 / B03 / B06~B12、UI-P01~P05 | 一批 | 各用例判据全绿；`feature_map` 细化到选择器 / 快捷键级 | 无 |
| 三：五态异常 | UI-S00~S10 | 二批 | 16 组视图映射表齐全；403 三策略各取样；`known-gap` 转缺陷 | 无 |
| 四：视觉基线 | UI-V01~V05 | 三批 | 基线首版人确认、`diff_metric` 可机判、基线入 `protected_paths` | 容差阈值（拍板项③） |
| 五：业务链路 | UI-F01~F06 | 四批 | 六条链路纯 UI 达成；runner 回流缺口按现状标注 | 无 |
| 六：稳定性压测 | 全量重跑 ≥3 轮 | 五批 | 多轮结果一致、无 flaky；E2E 入 CI 提交边界 | observe→enforce 切换时机 |

- 与 `plans/audits/2026-11-18-console-verification-system.landing-plan.md` 的批次对应关系：本计划第一批 = 落地计划第二批「跑通 verify 循环」的深化；第三 / 四批 = 落地计划第三批「建前端视觉判据」的用例展开；第六批对应 V2「harness 压测」。

---

## 九、证据留存边界（E1）

- `evidence/` 运行时产物（截图 / 响应 / cookie）不入库；仅 `evidence/baseline/` 作受保护例外入库。
- 采集端遇 `Set-Cookie` / `sdp_sess` 一律脱敏或丢弃，不落盘凭据；`UI-P04` 证据须经此检查。
- 每份 manifest 记录 `stamp` / `base` / `authBypassed` / 用例 id / `sha256` / 退出码；agent 结论只能引用证据路径，不转述结论。

---

## 十、已知降级点（验证时标注，不误判为失败）

| 位置 | 现状 | 用例中的处理 |
| --- | --- | --- |
| `OrgDashboardView.vue:4,28` | 组织台为入口占位 | UI-P02 判据注明 |
| `ComponentDetailView.vue:24-25` | 面包屑降级为 repoUrl | UI-B06 判据注明 |
| `RunCenterView.vue:308` | 全局聚合端点待补，按最近 N 条聚合 | UI-B04 判据注明 |
| `RunMonitorView.vue:95` | 日志端点缺失静默占位 | UI-B10 / UI-S09 判据注明 |
| `ConfigTab.vue:83` | 删除配置后端不支持 | UI-F01 环境准备时记录 |
| `constants/runCenter.ts:34` | 「待我审批」assignee=me 未落地 | UI-B08 判据注明 |
| `ArtifactsTab.vue` + `ui-05:220` | 制品库错误态未实现 | UI-S08 标 `known-gap` 转缺陷 |
| `MainLayout.vue:124-156` | 左栏平台管理员实见 7 项，设计文档要求恒 5 项 | 单列文档—实现漂移项，待裁定后再定 UI-B12 断言 |
| `api/http.ts`（403 统一出口） | 路由守卫类 403 跳 `/forbidden`；API 偶发越权按 ui-05 §7.9 就地错误态（dashboard 已落地，其余视图仍走全局跳页） | UI-S05 判据按就地「操作被拒绝，请申请」；其余视图的就地化待逐项展开 |
| `DashboardView.vue` + `visual-diff.mjs` | dashboard 含 KPI / 最近运行 / target 在线状态等动态数据，字节级 sha 无法判定视觉回归 | dashboard 归入 volatile，只留 diff 与实际截图供人审；像素级区域比对待接入 |

---

## 变更历史

| 时间 | 变更 |
| --- | --- |
| 2026-11-20 | 初版：按四层 DoD（行为 / 五态 / 视觉 / 业务链路）规划 38 条 UI 验证用例，附执行批次、证据留存边界与已知降级点清单。 |
| 2026-11-20 | 六批按取样执行（本地 kind）：26/38 条用例全绿——UI-B 8/12、UI-S 5/10（连续 3 轮 5/5）、UI-V 5/5、UI-F 4/6、UI-P 4/5，集群模式 harness 9/9；其余 12 条（UI-S00 映射表、403 三策略全集、部分 CRUD / 深链 / 异常回归与 auth bypass）未展开。期间修复 hub 未 seed 内置 component 角色导致的组件子资源 403。UI-S 改用通配拦截 + 命中计数断言消除「注入未生效」的假绿；S05 判据按 403 全局跳转实现修正；dashboard 归入 volatile。视觉基线 `confirmedBy` 待人审。 |
| 2026-11-21 | 第一性原理根因修复：最本质根因是判据来源错置（PASS 定义权在脚本、判据从实现反推），S03/S05/S10/F02a 同根。新增 `console/scripts/criteria.mjs` 判据契约 SSOT + `assertContract` 守卫 + `verdict` 统一判定，`e2e-states.mjs` 只引用契约；接入后 S03/S05 诚实 FAIL 暴露此前假绿。产品修复 dashboard 错误态（500 吞成空态、403 全局跳页 → 就地错误态，符合 ui-05 §7.9 与五态规范 §1），runs 请求透传 `skip403Redirect`。新镜像 `v0.0.2-ui` 部署后 UI-S 5/5 真通过（pos=2/2），UI-P 4/4 / UI-F 4/4 / UI-B 8/8 回归全绿。遗留：契约当前仅覆盖 UI-S 5 条，其余套件待契约化。 |
| 2026-11-21 | 判据执行权收口与全套件推广：遗留项的本质是「契约是可选库、判定权仍分散」，且旧报「26/38」按脚本 record 数拼凑、口径失真。新增 `console/scripts/contract-runner.mjs` 唯一判定点（脚本只产出观测事实，自带 `ok/spec/target/positive/forbidden` 即抛错）；`criteria.mjs` 扩展到计划全部 38 条 + 套件归属，`assertCoverage()` 与套件声明完整性在启动时强制校验。UI-B/UI-S/UI-V/UI-F/UI-P 五套件全部改由 runner 驱动，每份 manifest 记规范引用与逐条正向证据命中。两轮全量压测统计一致、`failed=0` 无 flaky；按计划用例口径 **18 PASS + 4 known-gap（B03 单层树 / F02 无部署阶段 / P02 org_admin fixture / V01 基线待人审）+ 16 未展开**，不虚报为全量完成。未展开项集中在需真实造数的 S06~S10、B07~B11、F03~F06 与 V03/V05；本地 KC 写 `org_admin` 属性后 password grant 重置为 `UPDATE_PASSWORD` 的组织管理员 fixture 阻塞已取证。 |
